extends "res://tests/p2/rules/run.gd"
const Results = preload("res://mission/results/ports/field_results.gd")
const S = preload("res://contracts/schema.gd")
const C = preload("res://contracts/canonical.gd")
const Store = preload("res://infrastructure/persistence/save_service.gd")
const F = preload("res://tests/p1/application/fixture.gd")
var results: RefCounted
var network_receipts := 0
var settlement_calls := 0
var durable: RefCounted
var fault_after_hit := false
var had_hit := false
var points := [[0,0,0],[1000,0,0],[4000,0,0]]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL RESULTS ",label)

func require(reply: Dictionary, label: String) -> bool:
	check(reply.ok,label+" "+str(reply.get("error","")))
	return reply.ok

func battle(mode: String, count: int = 3) -> Dictionary:
	var spec := make_spec()
	spec.mode = mode
	spec.battle_limit = 3
	spec.sides.append({"team_key":2,"faction_id":"hill","commander_hero_id":null,"roster_allocations":[{"source_slot_range":[2,count]}]})
	var source: Dictionary = spec.reserved_sources[0]
	var hero := source.duplicate(true)
	hero.merge({"source_slot_range":[1,2],"count":1,"hero_id":"hero/"+UUID,"troop_def_id":null},true)
	var reserve := source.duplicate(true)
	reserve.merge({"source_slot_range":[2,count],"count":count-2},true)
	source.merge({"source_slot_range":[0,1],"count":1},true)
	spec.reserved_sources = [reserve,hero,source]
	return spec

func fresh(mode: String) -> RefCounted:
	results = Results.new()
	mission = Mission.new(core,engine,mode,results.build_result)
	mission.bind_field_clearance(func(_s,sites):var all := [];all.resize(sites.size());all.fill(true);return R.ok(all))
	return mission

func start_field(spec: Dictionary, hp: int, app: RefCounted = null) -> bool:
	var zones := []
	var exits := []
	for i in range(spec.sides.size()):
		var key: Variant = spec.sides[i].team_key
		zones.append({"team_key":key,"quota":1,"rally_mm":points[i],"points_mm":[points[i]]})
		exits.append({"team_key":key,"min_mm":points[i],"max_mm":points[i]})
	var scene := {"id":spec.scene_def_id,"simulation_scene":"res://tests/p2/rules/field.tscn","field_zones":zones}
	var rule := {"id":spec.ruleset_id,"battle_mode":"field","wave_cooldown_ticks":60}
	var prepared: Dictionary
	if app == null:
		fresh(spec.mode)
		prepared = mission.prepare(spec,scene,rule)
	else:
		prepared = app.prepare_mission(spec,scene,rule)
	if not require(prepared,"prepare production Mission") or not require(results.open(mission.view()),"open RESULTS"):
		return false
	scope = mission.view().mission_id
	for frame in 90:
		await physics_frame
		var nav: Dictionary = engine.sync_navigation(scope)
		if nav.ok and nav.value.status == "applied":
			var path: Dictionary = engine.query_path_batch([{"from":points[0],"to":points[1]}],nav.value.applied_revision,scope)
			if path.ok and path.value[0].reachable:
				break
	combat = Combat.new(scope)
	movement = Move.new(engine,scope)
	had_hit = false
	var built := Rules.build(scope,spec,exits,func(principal,_team,_act):return is_same(principal,login),status_of,position_of)
	if not require(built,"real RULES"):
		return false
	rules = built.value
	var orders := []
	for i in 3:
		orders.append({"source_slot":i,"components":{"spawn_position_mm":points[i]}})
	var opened: Dictionary = mission.apply_deployment(orders)
	if not require(opened,"real source binding"):
		return false
	if not require(combat.enlist(opened.value[1],{"team":1,"role":"infantry","hp":hp}),"hero combat registration"):
		return false
	var mount: Dictionary = mission.allocate_entity(null,{"type":"mount","spawn_position_mm":[5000,0,0]})
	if not require(mount,"nonhuman entity"):
		return false
	return require(mission.register_system("action",{"id":"combat","run":tracked_action,"commit":publish_action,"rollback":cancel_action}),"action hook") and require(mission.register_system("objectives",rules.system()),"rules hook") and require(mission.register_system("snapshot",{"id":"results","run":snapshot,"commit":results.commit,"rollback":results.rollback}),"snapshot hook") and require(mission.register_system("snapshot",{"id":"z.fault","run":fault}),"fault hook")

func tracked_action(ctx: Dictionary, batch: Dictionary) -> Dictionary:
	var report := action(ctx,batch)
	if not report.ok:
		return report
	var stored: Dictionary = results.observe_combat(ctx,batch,report.value)
	had_hit = not report.value.hits.is_empty()
	return report if stored.ok else stored

func cancel_action() -> void:
	reset_action()
	results.rollback()

func snapshot(ctx: Dictionary, batch: Dictionary) -> Dictionary:
	for rep in ctx.phase_reports:
		if rep.id == "field.rules":
			return results.stage_snapshot(ctx,batch,rep.value)
	return R.fail("NotFound","field.rules")

func fault(_ctx: Dictionary, _batch: Dictionary) -> Dictionary:
	return R.fail("Unavailable","injected.after_results") if had_hit and fault_after_hit else R.ok()

func strike(tick: int) -> Array:
	if tick not in [1,4]:
		return []
	return [{"actor_handle":{"index":0,"generation":1},"weapon_slot":0,"input_phase":"start" if tick==1 else "release","direction":"up","target_hint":null}]

func finish_field() -> Dictionary:
	var decision: Variant = rules.view().outcome
	if decision == null or not require(mission.request_end(decision),"outcome barrier"):
		return {}
	var fake: Dictionary = decision.duplicate(true)
	fake.winner_team_keys = ["forged"]
	check(not results.build_result(mission.view(),fake).ok,"reject caller-supplied winner")
	var done: Dictionary = mission.finalize()
	if not require(done,"production Mission.finalize"):
		return {}
	check(mission.finalize().value == done.value and done.value.slot_outcomes.is_read_only() and done.value.slot_outcomes[0].is_read_only(),"sealed stable immutable result")
	return done.value

func phase_one() -> Dictionary:
	var spec := battle("campaign",1000)
	if not await start_field(spec,1):
		return {}
	fault_after_hit = true
	var retried := false
	var tick := 0
	while tick < 15:
		tick += 1
		var stepped: Dictionary = mission.step_fixed(tick,strike(tick))
		if not stepped.ok and stepped.error.field == "injected.after_results":
			check(mission.view().tick == tick-1 and rules.view().outcome == null,"late fault leaves old tick active")
			fault_after_hit = false
			retried = true
			stepped = mission.step_fixed(tick,strike(tick))
		if not require(stepped,"real combat during field"):
			return {}
		if had_hit:
			break
	check(retried and had_hit and physics_hits >= 2,"physics hit replayed after rollback")
	require(rules.request_withdrawal(2,login),"third side withdraws with unused reserves")
	require(mission.step_fixed(tick+1,[]),"publish terminal decision")
	var started := Time.get_ticks_usec()
	var value := finish_field()
	var elapsed := Time.get_ticks_usec()-started
	if value.is_empty():
		return {}
	print("1000-source finalize_and_replay_us=",elapsed," canonical_bytes=",C.encode(value).value.size())
	check(value.winner_team_keys == [0] and value.slot_outcomes.size() == 1000,"typed winner, all 1000 sources")
	var rows: Array = value.slot_outcomes
	var all_reserved := true
	for i in range(3,1000):
		all_reserved = all_reserved and rows[i]=={"source_slot_id":i,"end_status":"not_spawned","wounded":false,"captor_team_key":null,"xp":0}
	check(all_reserved,"997 unentered slots retain their sources")
	check(rows[0].xp == 1 and rows[0].end_status == "alive","one genuine hostile hit awards one field XP after rollback")
	check(rows[1].end_status=="wounded" and rows[1].wounded and is_same(rows[1].captor_team_key,0),"downed enemy hero with battlefield capture evidence")
	check(value.hero_outcomes.size()==1 and value.hero_outcomes[0].source_slot_id==1 and value.hero_outcomes[0].hero_id=="hero/"+UUID,"hero row mirrors unique source")
	check(rows[2].end_status=="withdrawn" and not rows[2].wounded and value.stats.teams.size()==3 and value.stats.teams[2].not_spawned==997,"withdrawing side reserves classified")
	check(value.stats.teams[0].reserved==1 and value.stats.teams[1].capture_candidates==1 and value.stats.teams[1].wounded_total==1,"nonhuman entity excluded from source summary")
	check(value.loot_claims==[{"source_slot_id":1,"loadout_snapshot_id":"issued","claimant_team_key":0}] and value.reward_intents.is_empty(),"item sourcing creates candidate claim only")
	require(S.validate_settlement(spec,value),"v1 campaign receipt")
	mission.dispose()
	return value

func wounded_departure() -> void:
	if not await start_field(battle("custom",12),100):
		return
	var tick := 0
	while tick < 15:
		tick += 1
		if not require(mission.step_fixed(tick,strike(tick)),"pre-withdrawal combat"):
			return
		if had_hit:
			break
	check(had_hit,"actual non-lethal contact")
	require(rules.request_withdrawal("0",login),"first side requests withdrawal")
	require(mission.step_fixed(tick+1,[]),"publish first independent retirement")
	check(rules.view().outcome == null and mission.view().entities.size()==3,"remaining parties continue")
	require(rules.request_withdrawal(2,login),"second side requests withdrawal")
	require(mission.step_fixed(tick+2,[]),"publish second retirement")
	var result := finish_field()
	if not result.is_empty():
		check(result.slot_outcomes[1].end_status=="withdrawn" and result.slot_outcomes[1].wounded and result.slot_outcomes[1].captor_team_key==null,"injury survives independent successful evacuation")
		check(result.stats.teams[1].withdrawn==1 and result.stats.teams[1].wounded_total==1 and result.stats.teams[1].wounded==0,"exclusive end status plus orthogonal injury")
	mission.dispose()

func rehash(value: Dictionary) -> Dictionary:
	value.erase("integrity_hash")
	value["integrity_hash"] = C.hash_value(value).value
	return value

func airborne_generation() -> void:
	points[0] = [-8000,0,0]
	var ready := await start_field(battle("custom"),100)
	points[0] = [0,0,0]
	if not ready:
		return
	var shooter := {"index":0,"generation":1}
	require(combat.enlist(shooter,{"team":0,"role":"archer","ammo":1}),"ranged actor for generation test")
	for tick in range(1,5):
		var inputs := strike(tick)
		if not inputs.is_empty():
			inputs[0].weapon_slot = 1
		if tick == 4:
			require(rules.request_withdrawal(0,login),"shooter withdraws just after releasing")
		require(mission.step_fixed(tick,inputs),"live ranged fixed tick")
	check(combat.has_pending_projectiles() and not mission.resolve_entity(scope,shooter).ok,"physical missile outlives its binding")
	require(combat.remove_actor(shooter),"retire shooter COM handle")
	require(movement.despawn(shooter),"retire shooter MOV handle")
	var replacement: Dictionary = mission.allocate_entity(null,{"type":"mount","spawn_position_mm":[6000,0,0]})
	if not require(replacement,"reuse index with a nonhuman object"):
		return
	check(replacement.value.index==shooter.index and replacement.value.generation==2,"actual pool generation changes")
	var forged := {"tick":5,"events":[],"hits":[{"attacker":{"index":1,"generation":1},"target":shooter,"damage":1,"blocked":false}]}
	var stale: Dictionary = results.observe_combat(mission.view(),{"mission_id":scope,"source_tick":5},forged)
	check(not stale.ok and stale.error.field=="combat.target","retired target never resolves to new generation")
	results.rollback()
	var tick := 4
	while tick < 15 and not had_hit:
		tick += 1
		require(mission.step_fixed(tick,[]),"fly until collision")
	check(had_hit and combat.view({"index":1,"generation":1}).value.hp < 100,"real arrow reaches target after generation reuse")
	require(rules.request_withdrawal(2,login),"field ends after confirmed missile contact")
	require(mission.step_fixed(tick+1,[]),"publish posthumous contact")
	var value := finish_field()
	if not value.is_empty():
		check(value.slot_outcomes[0].end_status=="withdrawn" and value.slot_outcomes[0].xp==1 and value.slot_outcomes[1].wounded,"credit follows the original source generation")
	mission.dispose()

func invalid_cases(original: Dictionary) -> void:
	if original.is_empty():
		check(false,"missing baseline for coverage")
		return
	var spec := battle("campaign",1000)
	var tests := ["missing","duplicate","extra","revision","identity","digest","captor","winner","hero","hero_duplicate"]
	for key in tests:
		var altered := original.duplicate(true)
		match key:
			"missing": altered.slot_outcomes.pop_back()
			"duplicate": altered.slot_outcomes[1].source_slot_id=0
			"extra": altered.slot_outcomes[-1].source_slot_id=1001
			"revision": altered.reservation_revision+=1
			"identity": altered.encounter_id="encounter/00000000-0000-4000-8000-000000000001"
			"digest": altered.integrity_hash="0".repeat(64)
			"captor": altered.slot_outcomes[1].captor_team_key="0"
			"winner": altered.winner_team_keys=[88]
			"hero": altered.hero_outcomes[0].end_status="alive"
			"hero_duplicate": altered.hero_outcomes.append(altered.hero_outcomes[0])
		var error: Dictionary=Results.validate_source_coverage(spec,altered if key=="digest" else rehash(altered))
		check(not error.ok and not error.error.field.is_empty(),"diagnostic "+key)
	var dup := battle("campaign")
	dup.reserved_sources[2].hero_id=dup.reserved_sources[1].hero_id
	var rejected := Results.new().open({"phase":"Deployment","mission_id":"dup","tick":0,"encounter_spec":dup})
	check(not rejected.ok and rejected.error.field=="reserved_sources.hero_id","duplicate hero reservation")
	check(not results.observe_combat({"mission_id":scope,"tick":0},{"mission_id":scope,"source_tick":1},{"tick":1,"hits":[],"events":[]}).ok,"completed scope sealed against new facts")

func routed_modes() -> void:
	durable=Store.new(ProjectSettings.globalize_path("user://results-"+Crypto.new().generate_random_bytes(8).hex_encode()))
	var app := F.App.new(durable,func():return F.Camp.new(),fresh,F.authorize,
		func(_spec,_result):settlement_calls+=1;return R.ok([]),
		func(_value):network_receipts+=1;return R.ok())
	if not require(app.start_session("sandbox",F.options("routes")),"start real campaign"):
		return
	var before: Dictionary=durable.recover("routes").value.snapshot
	for mode in ["custom","multiplayer"]:
		if not await start_field(battle(mode),100,app):
			return
		require(app.step_fixed(1,[]),"App fixed tick")
		require(rules.request_withdrawal(0,login),"first side")
		require(rules.request_withdrawal(2,login),"second side")
		require(app.step_fixed(2,[]),"publish App result")
		var ended: Dictionary=app.finish_mission(rules.view().outcome)
		if not require(ended,"real App.finish_mission"):
			return
		var value: Dictionary=ended.value
		check(value.encounter_id==null and value.reservation_revision==null and value.loot_claims.is_empty() and value.reward_intents.is_empty(),"no campaign settlement data "+mode)
		require(Results.validate_source_coverage(battle(mode),value),"noncampaign coverage")
		var first: Dictionary=app.route_result(value)
		check(first.ok and app.route_result(value)==first,"idempotent App route "+mode)
		require(app.dispose_mission(),"release "+mode)
		check(app.query().value.state=="CampaignMap" and durable.recover("routes").value.snapshot==before,"unchanged durable campaign "+mode)
	check(network_receipts==1 and settlement_calls==0,"multiplayer sink once, campaign sink never called")
	app.close_session()

func run() -> void:
	core = Core.new("1234567890abcdef")
	engine = Adapter.new(root,true)
	var before := failed
	var sample := await phase_one()
	await wounded_departure()
	await airborne_generation()
	print("T-RESULTS-01 ", "PASS" if before==failed else "FAIL"," physical_contacts=",physics_hits)
	before = failed
	invalid_cases(sample)
	print("T-RESULTS-02 ", "PASS" if before==failed else "FAIL")
	before = failed
	await routed_modes()
	check(engine.counts().scopes==0,"all test scopes released")
	print("T-RESULTS-03 ", "PASS" if before==failed else "FAIL")
	print("P2-RESULTS-001 ", "PASS" if failed==0 else "FAIL"," assertions=",checks," failures=",failed)
	quit(0 if failed==0 else 1)
