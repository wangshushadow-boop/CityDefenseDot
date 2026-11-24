extends RefCounted
const R = preload("res://contracts/result.gd")
const Mission = preload("res://mission/runtime/runtime.gd")
const Core = preload("res://core/runtime.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
var checks := 0
var failures := 0
var visible := {}
var reject := true
var retire := []
var staged_tick := 0
var published_tick := 0
var stalled := false
var external_orders := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL field-mission ",label)

func clear_sites(_scope: String, rows: Array) -> Dictionary:
	if not external_orders.is_empty():
		external_orders[0].source_slot = 999
		external_orders[0].components.detail.note = "changed"
		external_orders.clear()
	if stalled:
		return R.fail("Unavailable","world_sync")
	var reply := []
	for row in rows:
		reply.append(not visible.has(row.spawn_position_mm))
	return R.ok(reply)

func prepare_move(ctx: Dictionary, batch: Dictionary) -> Dictionary:
	staged_tick = batch.source_tick
	check(ctx.entities.is_read_only(),"published entity snapshot")
	return R.ok({"intent_count":batch.inputs.size()})

func downstream(ctx: Dictionary, _batch: Dictionary) -> Dictionary:
	check(ctx.phase_reports.size()==1 and ctx.phase_reports[0].phase=="movement","same-tick phase reports")
	if reject:
		return R.fail("Unavailable","injected")
	return R.ok({"retire_handles":retire.duplicate()})

func run(test: SceneTree) -> int:
	var core := Core.new("1234567890abcdef")
	var adapter := Adapter.new(test.root,true)
	var spec: Dictionary = test.spec("custom",[test.source(0,1000)])
	spec.ruleset_id = "base:ruleset/field_battle"
	spec.sides[0].roster_allocations = [{"source_slot_range":[0,500]}]
	spec.sides.append({"team_key":"0","faction_id":"base:faction/b","commander_hero_id":null,"roster_allocations":[{"source_slot_range":[500,1000]}]})
	var rule := {"id":spec.ruleset_id,"wave_size":200,"wave_cooldown_ticks":2}
	var scene := {"id":spec.scene_def_id,"simulation_scene":"res://tests/p2/mission/ground.tscn","field_zones":[]}
	for team in [0,"0"]:
		var points := []
		for i in 250:
			points.append([(-55000 if is_same(team,0) else 55000)+i%10*1200,0,-15000+floori(i/10.0)*1200])
		scene.field_zones.append({"team_key":team,"quota":250,"rally_mm":points[0],"points_mm":points})
	var mission := Mission.new(core,adapter,"field",test.result_for)
	var bad := spec.duplicate(true)
	bad.sides[0].roster_allocations[0].source_slot_range[1] = 501
	check(not mission.prepare(bad,scene,rule).ok and adapter.counts().scopes==0 and mission.view().phase=="New","ambiguous field rejected before scope")
	check(mission.bind_field_clearance(clear_sites).ok,"trusted query")
	var prepared := mission.prepare(spec,scene,rule)
	check(prepared.ok,"two typed teams")
	if not prepared.ok:
		return failures
	var id: String = prepared.value.mission_id
	for i in 120:
		await test.physics_frame
		var ready := adapter.sync_navigation(id)
		if ready.ok and ready.value.status=="applied":
			var probe := adapter.query_path_batch([{"from":[-55000,0,-15000],"to":[55000,0,10000]}],ready.value.applied_revision,id)
			if probe.ok and probe.value[0].reachable:
				break
	var east: Array = scene.field_zones[1].points_mm[0]
	var west: Array = scene.field_zones[0].points_mm[0]
	var explicit := [{"source_slot":0,"components":{"spawn_position_mm":west}},{"source_slot":500,"components":{"spawn_position_mm":west}}]
	var prev := mission.view()
	check(not mission.apply_deployment(explicit).ok and mission.view()==prev,"wrong-side second item leaves first unspawned")
	explicit[1].components.spawn_position_mm = east
	visible[east] = true
	check(not mission.apply_deployment(explicit).ok and mission.view()==prev,"enemy occupies second site")
	visible.clear()
	explicit[1].components["team_key"] = 0
	check(not mission.apply_deployment(explicit).ok and mission.view()==prev,"cannot alias typed team")
	check(not mission.allocate_entity(0,{}).ok and not mission.allocate_entity(null,{"type":"human"}).ok,"field cannot bypass spawn director")
	check(mission.register_system("movement",{"id":"units","run":prepare_move,"commit":func(): published_tick=staged_tick,"rollback":func(): staged_tick=published_tick}).ok,"register reversible calculation")
	check(mission.register_system("damage",{"id":"casualties","run":downstream,"can_retire":true}).ok,"trusted casualty collection")
	var attempt := mission.step_fixed(1,[])
	check(not attempt.ok and mission.view()==prev and staged_tick==0 and published_tick==0,"opening wave and earlier domain roll back")
	reject = false
	var first := mission.step_fixed(1,[])
	check(first.ok and first.value.entities.size()==500 and first.value.spawned_slots.size()==500 and published_tick==1,"retry same tick opens balanced front " + str(first.get("error",{})))
	if not first.ok:
		mission.dispose()
		return failures
	var teams := {}
	for row in first.value.entities:
		var team: Variant = row.components.team_key
		teams[team] = teams.get(team,0)+1
		check(is_same(team,0 if row.source_slot<500 else "0"),"source tag")
		check(row.components.is_read_only() and row.components.troop_def_id=="base:troop/guard","immutable actual troop loadout")
	check(teams=={0:250,"0":250},"balanced quota")
	# Fixed-step casualty commits release capacity. The next cool-down tick may reinforce.
	for i in 200:
		retire.append(first.value.entities[i].handle)
	var old: Dictionary = retire[0]
	var taken := mission.step_fixed(2,[])
	check(taken.ok and taken.value.entities.size()==500 and taken.value.spawned_slots.size()==700 and not mission.resolve_entity(id,old).ok,"wave includes current tick's 200 casualties")
	retire.clear()
	for i in 200:
		retire.append(taken.value.entities[i].handle)
	var before_wave := mission.step_fixed(3,[])
	check(before_wave.ok and before_wave.value.entities.size()==300,"cooldown leaves room for the second wave")
	retire.clear()
	var refill := mission.step_fixed(4,[])
	check(refill.ok and refill.value.entities.size()==500,"second scheduled reinforcement")
	var final_view := mission.view()
	check(final_view.entities.size()==500 and final_view.spawned_slots.size()==900 and first.value.spawned_slots.size()==500,"old snapshots survive two waves")
	check(mission.request_end({"outcome":"withdrawn"}).ok,"withdraw")
	var result := mission.finalize()
	check(result.ok and result.value.slot_outcomes.size()==1000,"complete sources at boundary")
	if result.ok:
		var never := 0
		for row in result.value.slot_outcomes:
			if row.end_status == "not_spawned":
				never += 1
		check(never==100,"one hundred never deployed")
	check(mission.dispose().ok and adapter.counts().scopes==0 and first.value.entities.size()==500,"dispose and retained snapshot")
	# A batched manual deployment authorizes the point and the slot before
	# exposing any generation. A physically unreachable declared point fails.
	var manual := Mission.new(core,adapter,"manual",test.result_for)
	var invalid_point := [950000,0,950000]
	scene.field_zones[0].points_mm.append(invalid_point)
	check(manual.bind_field_clearance(clear_sites).ok and manual.prepare(spec,scene,rule).ok,"manual deployment")
	var scope_id: String = manual.view().mission_id
	for i in 120:
		await test.physics_frame
		var receipt := adapter.sync_navigation(scope_id)
		if receipt.ok and receipt.value.status=="applied":
			var route := adapter.query_path_batch([{"from":west,"to":east}],receipt.value.applied_revision,scope_id)
			if route.ok and route.value[0].reachable:
				break
	var invalid := [{"source_slot":0,"components":{"spawn_position_mm":west}},{"source_slot":1,"components":{"spawn_position_mm":invalid_point}}]
	check(not manual.apply_deployment(invalid).ok and manual.view().entities.is_empty(),"real nav rejects unreachable spawn")
	explicit[1].components.erase("team_key")
	explicit[0].components["detail"] = {"note":"original"}
	external_orders = explicit
	var placed := manual.apply_deployment(explicit)
	check(placed.ok and placed.value[0].index==0 and placed.value[1].index==1,"successful exact positioning " + str(placed.get("error",{})))
	if not placed.ok:
		manual.dispose()
		return failures
	var committed: Dictionary = manual.resolve_entity(scope_id,placed.value[0]).value
	check(explicit.is_empty() and committed.source_slot==0 and committed.components.detail.note=="original","clearance callback cannot alter validated batch")
	check(manual.step_fixed(1,[]).ok,"manual front starts")
	stalled = true
	check(manual.step_fixed(2,[]).ok and manual.view().entities.size()==2,"temporary unavailable wave keeps current battle running")
	stalled = false
	visible[west] = true
	visible[east] = true
	var retry := manual.step_fixed(3,[])
	check(retry.ok and retry.value.entities.size()==202,"next tick retries safely outside occupied sites")
	visible.clear()
	check(manual.dispose().ok and adapter.counts().scopes==0,"manual scope release")
	print("P2-MISSION-FIELD ", "PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures)
	return failures
