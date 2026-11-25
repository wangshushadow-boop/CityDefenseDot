extends "res://tests/p2/field/run.gd"
## A separate close deployment runs through the normal composition in this process.
const FILE := "res://content/base/field/river_plain.scene.json"
const DEFINITIONS := "res://content/base/field/field.json"
func deploy_nearby() -> bool:
	var read := Canon.decode_source(FileAccess.get_file_as_bytes(FILE))
	if not ok(read,"read actual field marker resource"):return false
	var markers: Dictionary=read.value
	var positions := {"west":[3250,0,0],"east":[-3250,0,0],"line":[0,0,0]}
	for marker in markers.markers:
		if positions.has(marker.id): marker.position_mm=positions[marker.id]
	var scratch := "user://field-accept-%d" % OS.get_process_id()
	var pack_file := ProjectSettings.globalize_path(scratch+".pck")
	var data := FileAccess.open(scratch+"-markers.json",FileAccess.WRITE)
	if not check(data!=null,"writable test-only marker resource"):return false
	data.store_string(JSON.stringify(markers))
	data.close()
	var pack:=PCKPacker.new()
	if not check(pack.pck_start(pack_file)==OK,"create test package"):return false
	if not check(pack.add_file(FILE,ProjectSettings.globalize_path(scratch+"-markers.json"))==OK,"add map markers"):return false
	var definitions := Canon.decode_source(FileAccess.get_file_as_bytes(DEFINITIONS))
	if not ok(definitions,"read original troop and scene definitions"):return false
	for item in definitions.value:
		if item.id=="field:scene/river_plain":item.metadata.spawn_columns=80
	var spec_data:=FileAccess.open(scratch+"-definitions.json",FileAccess.WRITE)
	if not check(spec_data!=null,"writable test deployment definition"):return false
	spec_data.store_string(JSON.stringify(definitions.value))
	spec_data.close()
	if not check(pack.add_file(DEFINITIONS,ProjectSettings.globalize_path(scratch+"-definitions.json"))==OK,"load wide formation"):return false
	if not check(pack.flush()==OK and ProjectSettings.load_resource_pack(pack_file,true),"activate QA map for this process"):return false
	return check(Canon.decode_source(FileAccess.get_file_as_bytes(FILE)).value==markers,"resolved alternate field markers")

func battle() -> void:
	if not deploy_nearby():return
	var config:=Config.resolve([],DisplayServer.get_name(),{})
	if not ok(config,"profile"):return
	app=Boot.new(root)
	if not ok(app.boot(config.value),"boot"):return
	var opened:Dictionary=app.start_field(500,1000,241124)
	if not ok(opened,"custom close mixed field"):return
	scope=opened.value
	if not check(hud().deployment_zones[0].position_mm==[3250,0,0],"normal session used close formation markers"):return
	var initial:Dictionary
	for retry in 60:
		await physics_frame
		initial=app.field_step()
		if initial.ok or initial.error.code not in ["Unavailable","StaleVersion"]:break
	if not ok(initial,"opening"):return
	observe(initial.value)
	var mix:Dictionary={}
	var mounts:=0
	var lanes := [{},{}]
	var sides := [0,0]
	for row in initial.value.entities:
		if row.source_slot==null:mounts+=1
		else:
			var role:String=row.components.troop_def_id.get_file()
			mix[role]=mix.get(role,0)+1
			var team:int=row.components.team_key
			sides[team]+=1
			lanes[team][row.components.spawn_position_mm[2]]=true
	if not check(mix==MIX and mounts==100 and known_slots.size()==500,"500 real people plus 100 mounts"):return
	if not check(sides==[250,250] and lanes[0].size()==80 and lanes[1].size()==80,"each side actually deployed in 80 columns"):return
	for f in hud().formations:
		if not order(f,"hold_fire"):return
	if not step():return
	for f in hud().formations:
		if not order(f,"move",{},[-7000,0,(f.id-2)*6000]):return
	if not step():return
	for n in 2600:
		if not step():return
		if n%30==0:await physics_frame
		if n%180==0:print("CLOSE tick=",tick," shots=",shots," hits=",hits," down=",downed.size()," winners_can_capture=",claimed.size()," entered=",known_slots.size())
		if not claimed.is_empty() and known_slots.size()>500:break
	if not ok(app.field_command("field.withdraw",{},tick,"close-withdraw"),"own side withdraws") or not step():return
	var result:Dictionary=hud().result
	var seen:Dictionary={}
	var totals:Dictionary={}
	var capture_slots:=[]
	for row in result.slot_outcomes:
		var id:int=row.source_slot_id
		if not check(id>=0 and id<1000 and not seen.has(id),"unique source"):return
		seen[id]=true
		var expected: String=exits.get(id,"wounded" if wounds.has(id) else "alive") if known_slots.has(id) else "not_spawned"
		if not check(row.end_status==expected and row.wounded==wounds.has(id),"wounded and final state from actual events"):return
		var captor:Variant=1 if claimed.has(id) and not exits.has(id) else null
		if not check(is_same(row.captor_team_key,captor),"winning attacker from actual downed generation"):return
		if captor!=null:capture_slots.append(id)
		totals[expected]=totals.get(expected,0)+1
	var entered := known_slots.size()
	check(first_wave_tick>1 and first_wave_tick<tick and entered>500 and entered<1000,"reinforcements arrived before withdrawal with reserves still waiting")
	check(seen.size()==1000 and totals.get("not_spawned",0)==1000-entered,"every unentered source remained in reserve")
	check(totals.get("withdrawn",0)>0 and result.outcome=="withdrawn" and result.winner_team_keys==[1],"living soldiers withdrew and the other side won")
	check(not capture_slots.is_empty() and totals.get("wounded",0)>=capture_slots.size() and hits>0,"the victor captured genuinely wounded soldiers")
	var unsigned:=result.duplicate()
	unsigned.erase("integrity_hash")
	var digest:=Canon.hash_value(unsigned)
	check(digest.ok and digest.value==result.integrity_hash and app.report().last_match.integrity_hash==result.integrity_hash,"normal routed server receipt and digest")
	summary={"scenario":"close_mixed_80_columns","ticks":tick,"mix":mix,"horses":mounts,"entered":known_slots.size(),
		"outcomes":totals,"shots":shots,"hits":hits,"routes":routs,"downed":downed.size(),
		"captured_slots":capture_slots,"first_reinforcement_tick":first_wave_tick,"winner":result.winner_team_keys}
	check(app.leave_field().ok,"release")
