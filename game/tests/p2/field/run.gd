extends SceneTree
## End-to-end phase acceptance on the shipped field, using only the application commands and committed snapshots.
const Boot = preload("res://bootstrap/composition_root.gd")
const Config = preload("res://bootstrap/boot_config.gd")
const Canon = preload("res://contracts/canonical.gd")
const MIX := {"infantry":250,"archer":150,"cavalry":50,"mounted_archer":50}
const MARKERS := {"infantry":[46000,0,-4000],"archer":[31000,0,4000],"cavalry":[52000,0,-14000],"mounted_archer":[37000,0,12000]}
var app: RefCounted
var scope := ""
var tick := 0
var sequence := 0
var failures := 0
var checks := 0
var known_slots := {}
var known_handles := {}
var troop_slot := {}
var spawn_points := {}
var max_travel := {}
var mounted_roles := {}
var shots_by_role := {}
var hits_by_role := {}
var wounds := {}
var exits := {}
var downed := {}
var claimed := {}
var shots := 0
var hits := 0
var routs := 0
var first_wave_tick := 0
var tested_targets := []
var summary := {}
var assault := false

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		printerr("FAIL ",label)
	return condition

func ok(result: Dictionary, label: String) -> bool:
	return check(result.ok,label+" "+str(result.get("error","")))

func hud() -> Dictionary:
	return app.field_view("hud").value

func group(id: int) -> Dictionary:
	for row in hud().formations:
		if row.id==id: return row
	return {}

func order(g: Dictionary, kind: String, parameters := {}, position: Variant=null, target: Variant=null) -> bool:
	sequence+=1
	var id := "stage-player-%d"%sequence
	var cmd := {"mission_id":scope,"issuer_id":"player","order_id":id,"formation_ids":[g.id],
		"order_type":kind,"target_position":position,"target_formation_id":target,
		"parameters":parameters,"issued_tick":tick+1,"client_sequence":sequence}
	return ok(app.field_command("field.order",{"order":cmd,"revisions":{str(g.id):g.control_revision}},tick,id),"admit "+kind)

func key(handle: Dictionary) -> String:
	return "%d/%d"%[handle.index,handle.generation]

func observe(snapshot: Dictionary) -> void:
	tick=snapshot.tick
	for report in snapshot.system_reports:
		if report.id=="field.rules":
			for event in report.value.slot_events:
				exits[event.source_slot_id]=event.end_status
				if event.end_status=="wounded":wounds[event.source_slot_id]=true
		if report.id!="field.combat":continue
		var origins := {}
		for hit in report.value.hits:
			if hit.damage<=0 or hit.blocked:continue
			hits+=1
			var target_key:=key(hit.target)
			var shooter: int=known_handles.get(key(hit.attacker),-1)
			var target: int=known_handles.get(target_key,-1)
			if target>=0:wounds[target]=true
			if troop_slot.has(shooter):
				var role: String=troop_slot[shooter]
				hits_by_role[role]=hits_by_role.get(role,0)+1
			var hostile := shooter>=0 and target>=0 and (shooter<500)!=(target<500)
			var team := (0 if shooter<500 else 1) if hostile else -1
			if not origins.has(target_key):origins[target_key]=team
			elif origins[target_key]!=team:origins[target_key]=-1
		for event in report.value.events:
			match event.type:
				"projectile_launched":
					shots+=1
					var slot: int=known_handles.get(key(event.actor_handle),-1)
					if troop_slot.has(slot):
						var role: String=troop_slot[slot]
						shots_by_role[role]=shots_by_role.get(role,0)+1
				"routed": routs+=1
				"downed":
					var handle_key:=key(event.actor_handle)
					if known_handles.has(handle_key):
						var victim: int=known_handles[handle_key]
						downed[victim]=true
						wounds[victim]=true
						if origins.get(handle_key,-1)==1:claimed[victim]=true
	if tick==1 or snapshot.spawned_slots.size()!=known_slots.size():
		for row in snapshot.entities:
			if row.source_slot==null:continue
			known_handles[key(row.handle)]=row.source_slot
			troop_slot[row.source_slot]=row.components.troop_def_id.get_file()
			if not spawn_points.has(row.source_slot):
				var mm: Array=row.components.spawn_position_mm
				spawn_points[row.source_slot]=Vector3(mm[0],mm[1],mm[2])*0.001
		for id in snapshot.spawned_slots:known_slots[id]=true
		if tick>1 and first_wave_tick==0:first_wave_tick=tick

func record_travel() -> bool:
	var projected: Dictionary=app.field_view("visual")
	if not ok(projected,"actor projection"):return false
	for actor in projected.value.actors:
		var slot: int=known_handles.get(key(actor.handle),-1)
		if slot<0:continue
		var role: String=troop_slot[slot]
		var travel: float=actor.position.distance_to(spawn_points[slot])
		max_travel[role]=maxf(max_travel.get(role,0.0),travel)
		if actor.get("mount_handle")!=null:mounted_roles[role]=true
	return true

func step() -> bool:
	var advanced: Dictionary=app.field_step()
	if not ok(advanced,"fixed tick %d"%(tick+1)):return false
	if not check(advanced.value.tick==tick+1,"sequential authority tick"):return false
	observe(advanced.value)
	return true

func battle() -> void:
	var config:=Config.resolve([],DisplayServer.get_name(),{})
	if not ok(config,"profile"):return
	app=Boot.new(root)
	if not ok(app.boot(config.value),"boot"):return
	var opened: Dictionary=app.start_field(500,1000,241124)
	if not ok(opened,"river plain"):return
	scope=opened.value
	if not check(hud().phase=="deployment","deployment"):return
	var first: Dictionary
	for attempt in 60:
		await physics_frame
		first=app.field_step()
		if first.ok or first.error.code not in ["Unavailable","StaleVersion"]:break
	if not ok(first,"opening wave"):return
	observe(first.value)
	var humans: Dictionary={}
	var roles := {}
	var horses:=0
	for row in first.value.entities:
		if row.source_slot==null:
			horses+=1
		else:
			var role: String=row.components.troop_def_id.get_file()
			humans[role]=1+int(humans.get(role,0))
			roles[row.handle.index]=role
	if not check(humans==MIX and horses==100 and known_slots.size()==500,"opening 500 mixed people and 100 horses"):return
	var infantry: Dictionary=group(1)
	var delegate: String=hud().delegate_candidate
	if not check(infantry.owner=="player" and infantry.delegate==delegate and not delegate.is_empty(),"starting command grant"):return
	if not order(infantry,"layout",{"layout":"shield_wall"}) or not step():return
	if not check(group(1).layout=="shield_wall","shield wall applied"):return
	if not order(group(1),"delegate",{"actor":""}) or not step():return
	var recalled: Dictionary=group(1)
	if not check(recalled.delegate=="" and recalled.control_revision==infantry.control_revision+1,"player recalled delegate"):return
	if not order(recalled,"delegate",{"actor":delegate}) or not step():return
	var restored: Dictionary=group(1)
	if not check(restored.delegate==delegate and restored.control_revision==recalled.control_revision+1,"delegation restored"):return
	for formation in hud().formations:
		var role: String=roles[formation.members[0].index]
		if not order(formation,"move",{},MARKERS[role]):return
	var targets_seen := {}
	var ordered_assault := false
	for at in range(tick+1,5501 if assault else 3501):
		if not step():return
		if at%20==0:await physics_frame
		if at%120==0 and not record_travel():return
		if at%15==0 and tested_targets.size()<2:
			var reading:=hud()
			for target in reading.targets:targets_seen[target]=true
			for target in reading.targets:
				if target in tested_targets:continue
				if not order(group(1),"face_enemy",{},null,target):return
				if not step():return
				if not check(group(1).facing_target_id==target,"selected enemy target applied"):return
				tested_targets.append(target)
				break
		if assault and not ordered_assault and tested_targets.size()==2:
			for unit_group in hud().formations:
				if not order(unit_group,"charge",{},null,tested_targets[1]):return
			ordered_assault=true
		if at%240==0:print("FIELD_STAGE progress tick=",tick," seen_targets=",targets_seen.size()," shots=",shots," hits=",hits," downed=",downed.size()," captured_candidates=",claimed.size()," entered=",known_slots.size())
		if assault and tested_targets.size()==2 and first_wave_tick>0 and not claimed.is_empty() and routs>0:break
	if not check(tested_targets.size()==2,"two distinct visible enemy formations selected"):return
	for role in MIX:
		if not check(max_travel.get(role,0.0)>2.0,"field movement for "+role):return
	if not check(mounted_roles.has("cavalry") and mounted_roles.has("mounted_archer"),"both mounted troop roles rode live mounts"):return
	if not check(shots_by_role.get("archer",0)+shots_by_role.get("mounted_archer",0)>0,"ranged troop actually released a projectile"):return
	if not check(shots>0 and hits>0 and routs>0,"physical combat and morale"):return
	if not check(first_wave_tick>1 and known_slots.size()>500 and known_slots.size()<1000,"real second wave and remaining reserve"):return
	var withdrawn: Dictionary=app.field_command("field.withdraw",{},tick,"stage-withdraw")
	if not ok(withdrawn,"team withdrawal") or not step():return
	var end:=hud()
	if not check(end.phase=="ended" and app.session().query().value.state=="Results","normal result reached"):return
	var result: Dictionary=end.result
	var ledger: Dictionary={}
	var totals: Dictionary={}
	var verified_claims:=0
	for row in result.slot_outcomes:
		var slot: int=row.source_slot_id
		if not check(slot>=0 and slot<1000 and not ledger.has(slot),"unique reserved slot"):return
		ledger[slot]=true
		var expected := "not_spawned"
		if known_slots.has(slot):expected=exits.get(slot,"wounded" if wounds.has(slot) else "alive")
		if not check(row.end_status==expected,"authoritative terminal state for slot "+str(slot)):return
		if not check(row.wounded==wounds.has(slot),"wound flag from actual hit, down or wounded exit for slot "+str(slot)):return
		var captured: bool=claimed.has(slot) and not exits.has(slot)
		if not check((row.captor_team_key==1)==captured and row.captor_team_key in [null,1],"captor after terminal precedence for slot "+str(slot)):return
		if row.captor_team_key==1:verified_claims+=1
		totals[row.end_status]=totals.get(row.end_status,0)+1
	if not check(ledger.size()==1000 and totals.get("withdrawn",0)>0 and totals.get("wounded",0)>0,"1000 outcomes conserve the roster"):return
	if assault:check(verified_claims>0,"assault produced a positive capture candidate")
	else:check(verified_claims==0,"march produced zero capture candidates")
	var winners: Array=result.winner_team_keys
	var unsigned:=result.duplicate()
	unsigned.erase("integrity_hash")
	var digest:=Canon.hash_value(unsigned)
	if not check(winners==[1] and result.outcome=="withdrawn" and digest.ok and digest.value==result.integrity_hash,"withdrawal winner and digest"):return
	var receipt: Dictionary=app.report().last_match
	if not check(receipt.integrity_hash==result.integrity_hash and receipt.winner_team_keys==winners and receipt.result_id==result.result_id and result.encounter_id==null and result.loot_claims.is_empty(),"server match receipt"):return
	summary={
		"scenario":"assault" if assault else "march","ticks":tick,"mix":humans,"horses":horses,
		"targets":tested_targets,"delegate":delegate,"layout":"shield_wall",
		"first_reinforcement_tick":first_wave_tick,"entered":known_slots.size(),"outcomes":totals,
		"shots":shots,"damaging_hits":hits,"routes":routs,"downed":downed.size(),
		"wound_flags":wounds.size(),"exit_facts":exits.size(),"observed_travel_m":max_travel,
		"mounted_roles":mounted_roles.keys(),"shots_by_role":shots_by_role,"hits_by_role":hits_by_role,
		"verified_capture_candidates":verified_claims,"winners":winners,"integrity_hash":result.integrity_hash
	}
	check(app.leave_field().ok and not app.has_field(),"result released")

func run() -> void:
	assault="--assault" in OS.get_cmdline_user_args()
	await battle()
	if app!=null:check(app.shutdown().ok,"shutdown")
	print("FIELD_STAGE ",JSON.stringify(summary))
	print("FIELD_ACCEPTANCE checks=",checks," failures=",failures)
	quit(0 if failures==0 and not summary.is_empty() else 1)
