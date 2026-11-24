extends "res://tests/p2/mission/run.gd"
var keys: Variant = []
var snapshot_failure := false
var spoof := false
var delivered := []
var site_teams := []

func check_sites(_id: String,sites: Array) -> Dictionary:
	var answers := []
	for site in sites:
		site_teams.append(site.team_key)
		answers.append(true)
	return R.ok(answers)

func rule_phase(_ctx: Dictionary,_batch: Dictionary) -> Dictionary:
	return R.ok({"withdrawn_team_keys":keys,"retire_handles":delivered})

func run() -> void:
	var core := Core.new("1234567890abcdef")
	var bridge := Adapter.new(root,true)
	var encounter := spec("custom",[source(0,6)])
	encounter.ruleset_id="base:ruleset/field_battle"
	encounter.battle_limit=3
	encounter.sides=[]
	var scene := {"id":encounter.scene_def_id,"simulation_scene":"res://tests/p2/mission/ground.tscn","field_zones":[]}
	var teams := [0,"0",2]
	for i in 3:
		encounter.sides.append({"team_key":teams[i],"faction_id":"base:faction/a","commander_hero_id":null,"roster_allocations":[{"source_slot_range":[i*2,i*2+2]}]})
		var p := [i*1200,0,0]
		scene.field_zones.append({"team_key":teams[i],"quota":1,"rally_mm":[i*1200,0,1200],"points_mm":[p]})
	var game := Mission.new(core,bridge,"eligibility")
	game.bind_field_clearance(check_sites)
	var ready := game.prepare(encounter,scene,{"id":encounter.ruleset_id,"wave_cooldown_ticks":1})
	if not ready.ok:
		printerr("FAIL prepare ",ready)
		quit(1)
		return
	for frame in 120:
		await physics_frame
		var sync := bridge.sync_navigation(ready.value.mission_id)
		if sync.ok and sync.value.status=="applied":
			var probe := bridge.query_path_batch([{"from":[0,0,1200],"to":[0,0,0]}],sync.value.applied_revision,ready.value.mission_id)
			if probe.ok and probe.value[0].reachable:
				break
	check(not game.register_system("damage",{"id":"wrong","run":rule_phase,"can_gate_waves":true}).ok,"only field objectives gate waves")
	check(game.register_system("objectives",{"id":"rules","run":rule_phase,"can_retire":true,"can_gate_waves":true}).ok,"authority registered")
	game.register_system("objectives",{"id":"spoof","run":func(_c,_b):return R.ok({"withdrawn_team_keys":[2]}) if spoof else R.ok()})
	game.register_system("snapshot",{"id":"fault","run":func(_c,_b):return R.fail("Unavailable") if snapshot_failure else R.ok()})
	var first := game.step_fixed(1,[])
	if not first.ok or first.value.entities.size()!=3:
		printerr("FAIL initial deployment ",first.get("error",{}))
		quit(1)
		return
	for row in first.value.entities:
		delivered.append(row.handle)
	var before := game.view()
	for bad in [false,[1],["2"],[null]]:
		keys=bad
		check(not game.step_fixed(2,[]).ok and game.view()==before,"malformed projection rolls back")
	keys=[0]
	spoof=true
	var denied := game.step_fixed(2,[])
	check(not denied.ok and denied.error.code=="Unauthorized" and game.view()==before,"unregistered privilege")
	spoof=false
	snapshot_failure=true
	site_teams.clear()
	check(not game.step_fixed(2,[]).ok and game.view()==before,"wave after retirement is reversible")
	check(not site_teams.has(0) and site_teams.has("0") and site_teams.has(2),"no blocked team in real navigation/clearance batch")
	snapshot_failure=false
	keys=["0"]
	var retry := game.step_fixed(2,[])
	check(retry.ok and retry.value.entities.size()==2,"retry uses current authorization")
	if retry.ok:
		var entered: Array = retry.value.spawned_slots
		check(entered.size()==5 and entered.has(1) and entered.has(5) and not entered.has(3),"numeric and text team never alias")
	game.dispose()
	var arena := Mission.new(core,bridge,"arena")
	check(arena.prepare(spec("custom",[]),SCENE,RULE).ok,"non-field scenario")
	arena.register_system("objectives",{"id":"score","run":func(_c,_b):return R.ok({"withdrawn_team_keys":[0],"objective":"arena-score"})})
	var scored := arena.step_fixed(1,[])
	check(scored.ok and scored.value.system_reports[0].value.objective=="arena-score","other modes keep free report fields")
	arena.dispose()
	check(bridge.counts().scopes==0,"all scopes released")
	print("P2-WAVE-ELIGIBILITY failures=",failures)
	quit(1 if failures else 0)
