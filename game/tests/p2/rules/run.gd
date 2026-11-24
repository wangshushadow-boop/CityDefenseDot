extends SceneTree
const Rules = preload("res://mission/rules/ports/field_rules.gd")
const Mission = preload("res://mission/runtime/runtime.gd")
const Combat = preload("res://mission/combat/ports/field_combat.gd")
const Move = preload("res://mission/movement/ports/field_movement.gd")
const Core = preload("res://core/runtime.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const R = preload("res://contracts/result.gd")
const UUID := "b48883c0-79fb-4cd3-96fe-43bb44dfddbb"
var failed := 0
var checks := 0
var core: RefCounted
var engine: RefCounted
var mission: RefCounted
var combat: RefCounted
var candidate: RefCounted
var movement: RefCounted
var rules: RefCounted
var scope: String
var login := RefCounted.new()
var physics_hits := 0
var fail_last := false
var is_rout := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		printerr("FAIL RULES ",label)
		failed += 1

func make_spec() -> Dictionary:
	var sides := []
	for i in 2:
		sides.append({"team_key":0 if i==0 else "0","faction_id":"river","commander_hero_id":null,"roster_allocations":[{"source_slot_range":[i,i+1]}]})
	return {"schema_version":1,"encounter_id":"encounter/"+UUID,"reservation_revision":1,"mode":"custom","scene_def_id":"field:scene/river_plain","ruleset_id":"field:ruleset/field_battle","rng_seed":"1234567890abcdef","environment":{},"sides":sides,"reserved_sources":[{"source_party_id":"party/"+UUID,"troop_def_id":"field:troop/infantry","hero_id":null,"count":2,"source_slot_range":[0,2],"loadout_snapshot_id":"issued"}],"battle_limit":2,"deployment_constraints":{},"siege_snapshot":null}

func actual_sweep(queries: Array, tick: int) -> Dictionary:
	var hits: Dictionary = engine.query_sweep_batch(queries,{"scope_id":scope,"tick":tick})
	if not hits.ok:
		return hits
	var contacts := []
	for shape in hits.value:
		if shape.entity_handle=="defender":
			physics_hits += 1
			contacts.append({"query_index":shape.query_index,"target":{"index":1,"generation":1},"region":shape.region,"fraction_ppm":shape.fraction_ppm})
	return R.ok(contacts)

func action(ctx: Dictionary, batch: Dictionary) -> Dictionary:
	candidate = combat.fork()
	var poses := {}
	for row in ctx.entities:
		var index: int = row.handle.index
		if not candidate.view(row.handle).ok:
			var registered: Dictionary = candidate.enlist(row.handle,{"team":index,"role":"infantry","hp":1 if index==1 else 100})
			if not registered.ok:
				return registered
		var pose: Dictionary = movement.view(row.handle)
		if not pose.ok:
			var mm: Array = row.components.spawn_position_mm
			var placed: Dictionary = movement.spawn(row.handle,Vector3(mm[0],mm[1],mm[2])*0.001)
			if not placed.ok:
				return placed
			pose = movement.view(row.handle)
		var position: Vector3 = pose.value.position*1000
		poses[index] = {"position_mm":[roundi(position.x),roundi(position.y),roundi(position.z)],"facing_ppm":[1000000 if index==0 else -1000000,0,0]}
	var morale := []
	if is_rout and batch.source_tick==2:
		morale.append({"actor_handle":{"index":1,"generation":1},"delta":-100})
	return candidate.step_field(batch.source_tick,batch.inputs,poses,actual_sweep,morale)

func publish_action() -> void:
	combat = candidate
	candidate = null

func reset_action() -> void:
	candidate = null

func status_of(h: Dictionary) -> Dictionary:
	return candidate.view(h) if candidate!=null else combat.view(h)

func position_of(h: Dictionary) -> Dictionary:
	var pose: Dictionary = movement.view(h)
	if not pose.ok:
		return pose
	var p: Vector3 = pose.value.position*1000
	return R.ok([roundi(p.x),roundi(p.y),roundi(p.z)])

func setup() -> bool:
	var encounter := make_spec()
	var positions := [[0,0,0],[1000,0,0]]
	var zones := []
	var exits := []
	for i in 2:
		var team: Variant = encounter.sides[i].team_key
		zones.append({"team_key":team,"quota":1,"rally_mm":positions[i],"points_mm":[positions[i]]})
		exits.append({"team_key":team,"min_mm":[positions[i][0]-250,-1000,-250],"max_mm":[positions[i][0]+250,1000,250]})
	var scene := {"id":encounter.scene_def_id,"simulation_scene":"res://tests/p2/rules/field.tscn","field_zones":zones}
	var rule := {"id":encounter.ruleset_id,"battle_mode":"field","wave_cooldown_ticks":2}
	mission = Mission.new(core,engine,"rules")
	mission.bind_field_clearance(func(_s,sites): var ok := []; ok.resize(sites.size());ok.fill(true);return R.ok(ok))
	var prepared: Dictionary = mission.prepare(encounter,scene,rule)
	if not prepared.ok:
		return false
	scope = prepared.value.mission_id
	for frame in 90:
		await physics_frame
		var synced: Dictionary = engine.sync_navigation(scope)
		if synced.ok and synced.value.status=="applied":
			var reachable: Dictionary = engine.query_path_batch([{"from":positions[0],"to":positions[1]}],synced.value.applied_revision,scope)
			if reachable.ok and reachable.value[0].reachable:
				break
	combat = Combat.new()
	movement = Move.new(engine,scope)
	var built := Rules.build(scope,encounter,exits,func(who,team,_action):return is_same(who,login) and is_same(team,0),status_of,position_of)
	if not built.ok:
		return false
	rules = built.value
	var opened: Dictionary = mission.apply_deployment([{"source_slot":0,"components":{"spawn_position_mm":positions[0]}},{"source_slot":1,"components":{"spawn_position_mm":positions[1]}}])
	if not opened.ok:
		return false
	rules.watch_commander(opened.value[1],"0")
	return mission.register_system("action",{"id":"combat","run":action,"commit":publish_action,"rollback":reset_action}).ok and mission.register_system("objectives",rules.system()).ok and mission.register_system("snapshot",{"id":"fault","run":func(_c,_b):return R.fail("Unavailable","sample") if fail_last else R.ok()}).ok

func run() -> void:
	core = Core.new("1234567890abcdef")
	engine = Adapter.new(root,true)
	if not await setup():
		printerr("FAIL rules setup")
		quit(1)
		return
	var handle := {"index":0,"generation":1}
	for tick in range(1,13):
		var inputs := []
		if tick in [1,4]:
			inputs.append({"actor_handle":handle,"weapon_slot":0,"input_phase":"start" if tick==1 else "release","direction":"up","target_hint":null})
		check(mission.step_fixed(tick,inputs).ok,"real combat fixed step")
		if rules.view().outcome!=null:
			break
	var decision: Variant = rules.view().outcome
	check(decision!=null and decision.outcome=="victory" and decision.winner_team_keys==[0] and physics_hits>0,"actual collision determines winner")
	check(rules.view().commander_downed,"real opposing commander down")
	check(not rules.request_withdrawal(0,login).ok,"decision is final")
	check(mission.dispose().ok,"dispose first battle")
	check(await setup(),"second battle")
	check(mission.step_fixed(1,[]).ok,"starting field")
	check(not rules.request_withdrawal("0",login).ok and not rules.request_withdrawal(0,{}).ok,"typed team and principal authorization")
	check(rules.request_withdrawal(0,login).ok and rules.request_withdrawal(0,login).ok,"idempotent authorized retreat")
	fail_last = true
	check(not mission.step_fixed(2,[]).ok and rules.view().outcome==null and mission.view().tick==1,"failed publication rolls decision back")
	fail_last = false
	check(mission.step_fixed(2,[]).ok and rules.view().outcome.winner_team_keys==["0"],"retry preserves same withdrawal and winner")
	mission.dispose()
	check(await setup(),"routed field")
	is_rout = true
	check(mission.step_fixed(1,[]).ok,"ready")
	var fled: Dictionary = mission.step_fixed(2,[])
	check(fled.ok and fled.value.entities.size()==1 and rules.view().outcome.outcome=="victory","routed unit reaches real exit")
	if fled.ok:
		var facts: Array = fled.value.system_reports[1].value.slot_events
		check(facts==[{"source_slot_id":1,"end_status":"withdrawn"}],"exit fact source slot")
	mission.dispose()
	check(engine.counts().scopes==0,"all scopes released")
	commander_and_reserves()
	print("P2-RULES-FIELD ","PASS" if failed==0 else "FAIL"," assertions=",checks," physical_contacts=",physics_hits)
	quit(0 if failed==0 else 1)

func commander_and_reserves() -> void:
	var spec := make_spec()
	spec.reserved_sources[0].count = 4
	spec.reserved_sources[0].source_slot_range[1] = 4
	spec.sides[0].roster_allocations = [{"source_slot_range":[0,2]}]
	spec.sides[1].roster_allocations = [{"source_slot_range":[2,4]}]
	var exits := []
	for team in [0,"0"]:
		exits.append({"team_key":team,"min_mm":[0,0,0],"max_mm":[0,0,0]})
	var b := Rules.build("test",spec,exits,func(who,team,_act):return is_same(who,login) and is_same(team,0),
		func(h):return R.ok({"hp":0 if h.index==0 else 10,"routing":false}),func(_h):return R.ok([0,0,0]))
	check(b.ok,"commander rule initialization")
	var ruleset: RefCounted = b.value
	var commander := {"index":0,"generation":1}
	check(ruleset.watch_commander(commander,0).ok,"watch local commander")
	var ctx := {"mission_id":"test","tick":0,"spawned_slots":[0,2],"entities":[
		{"source_slot":0,"handle":commander,"components":{"team_key":0}},
		{"source_slot":2,"handle":{"index":1,"generation":1},"components":{"team_key":"0"}}]}
	var pkt := {"mission_id":"test","source_tick":1}
	check(ruleset.stage(ctx,pkt).ok,"downed with reserves")
	ruleset.commit()
	check(ruleset.view().outcome==null and ruleset.view().commander_options==["spectate","delegate","withdraw"],"reserve keeps encounter open and preserves choices")
	check(not ruleset.request_downed_mode("0","delegate",login).ok and not ruleset.request_downed_mode(0,"delegate",{}).ok,"cannot claim another controller")
	check(ruleset.request_downed_mode(0,"delegate",login).ok,"authorized delegation")
	ctx.tick = 1
	pkt.source_tick = 2
	check(ruleset.stage(ctx,pkt).ok,"stage control mode")
	ruleset.rollback()
	check(ruleset.view().control_mode=="spectate" and ruleset.stage(ctx,pkt).ok,"failed tick cannot move control")
	ruleset.commit()
	check(ruleset.view().control_mode=="delegate","delegation publishes only with tick")
