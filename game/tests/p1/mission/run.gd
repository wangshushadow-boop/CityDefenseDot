extends SceneTree
const Mission = preload("res://mission/runtime/runtime.gd")
const Core = preload("res://core/runtime.gd")
const EngineAdapter = preload("res://infrastructure/engine/adapter.gd")
const Canon = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const S = preload("res://contracts/schema.gd")
const UUID := "b48883c0-79fb-4cd3-96fe-43bb44dfddbb"
const Scene := {"id":"base:scene/field","simulation_scene":EngineAdapter.DEFAULT_SCENE}
const Rule := {"id":"base:rule/field"}
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func encounter(count: int = 2) -> Dictionary:
	var sources := []
	if count > 0:
		sources.append({"source_party_id":"party/"+UUID,"troop_def_id":"base:troop/guard","hero_id":null,
			"count":count,"source_slot_range":[5,5+count],"loadout_snapshot_id":"gear"})
	return {"schema_version":1,"encounter_id":"encounter/"+UUID,"reservation_revision":2,"mode":"campaign",
		"scene_def_id":Scene.id,"ruleset_id":Rule.id,"environment":{},"rng_seed":"1234567890abcdef",
		"sides":[{"team_key":0,"faction_id":"base:faction/a","commander_hero_id":null,"roster_allocations":[]}],
		"reserved_sources":sources,"battle_limit":2,"deployment_constraints":{},"siege_snapshot":null}

# A result producer local to this test records only the exercised, non-combat facts.
func build(snapshot: Dictionary, outcome: Dictionary) -> Dictionary:
	check(snapshot.is_read_only() and outcome.is_read_only(),"result producer receives frozen values")
	var slots := []
	var spec: Dictionary = snapshot.encounter_spec
	for source in spec.reserved_sources:
		for slot in range(source.source_slot_range[0],source.source_slot_range[1]):
			slots.append({"source_slot_id":slot,"end_status":"alive" if slot in snapshot.spawned_slots else "not_spawned",
				"wounded":false,"captor_team_key":null,"xp":0})
	var result := {"schema_version":1,"result_id":"test-result","encounter_id":spec.encounter_id,
		"mission_id":snapshot.mission_id,"reservation_revision":spec.reservation_revision,"outcome":outcome.outcome,
		"duration_ticks":snapshot.tick,"winner_team_keys":[],"objective_results":[],"slot_outcomes":slots,"loot_claims":[],
		"hero_outcomes":[],"siege_changes":null,"reward_intents":[],"stats":{}}
	result["integrity_hash"] = Canon.hash_value(result).value
	return R.ok(result)

func replay(core: RefCounted, engine_adapter: RefCounted) -> String:
	var recorded_id := "mission/authoritative-session-41/7"
	var m := Mission.new(core,engine_adapter,"replay",build,recorded_id)
	var spec := encounter()
	var prepared := m.prepare(spec,Scene,Rule)
	check(prepared.ok and prepared.value.phase=="Deployment","prepare")
	var id: String = prepared.value.mission_id
	check(id == recorded_id,"replay restores its authority-issued MissionId")
	check(not m.apply_deployment([{"source_slot":5,"components":{}},{"source_slot":5,"components":{}}]).ok and m.view().entities.is_empty(),"atomic failed deployment")
	var deployed := m.apply_deployment([{"source_slot":5,"components":{"hero":false}}])
	check(deployed.ok,"deploy source")
	var handle: Dictionary = deployed.value[0]
	check(not m.allocate_entity(5,{}).ok and not m.allocate_entity(1,{}).ok,"source once and within reservation")
	var mount: Dictionary = m.allocate_entity(null,{"type":"mount"}).value
	check(m.remove_entity(id,mount).ok,"release non-source entity")
	var mount2: Dictionary = m.allocate_entity(null,{}).value
	check(mount2.index==mount.index and mount2.generation==mount.generation+1 and not m.resolve_entity(id,mount).ok,"generation invalidation")
	check(m.register_system("movement",{"id":"read","run":func(view,batch):
		return R.ok({"previous_tick":view.tick,"inputs":batch.inputs.size()})}).ok,"register movement sampling")
	check(not m.call("step_fixed",1.7,[]).ok and m.view().tick==0,"fractional tick rejected without mutation")
	check(not m.step_fixed(2,[]).ok,"gap rejected")
	var intent := {"actor_handle":handle,"desired_direction":[0,0,-1],"speed_fraction":0.5,"stance":null}
	check(m.step_fixed(1,[intent]).ok and m.step_fixed(2,[]).ok,"fixed steps with real contract check")
	check(m.request_end({"outcome":"withdrawn"}).ok,"end")
	check(not m.step_fixed(3,[]).ok and not m.allocate_entity(6,{}).ok,"end freezes writes")
	var result := m.finalize()
	check(result.ok and S.validate_settlement(spec,result.value).ok and result.value.slot_outcomes.size()==2,"actual result port validates all sources")
	check(m.finalize()==result,"finalize replay")
	var hash_value: String = Canon.hash_value([m.view(),result.value]).value
	check(m.dispose().ok and m.dispose().ok,"idempotent release")
	var zero := Mission.new(core,engine_adapter,"empty",build)
	check(zero.prepare(encounter(0),Scene,Rule).ok and zero.request_end({"outcome":"cancelled"}).ok and zero.finalize().ok,"zero source result")
	zero.dispose()
	return hash_value

func run() -> void:
	var desktop := "--client" in OS.get_cmdline_user_args()
	check((DisplayServer.get_name()!="headless")==desktop,"selected actual display profile")
	var core := Core.new("1234567890abcdef")
	var engine_adapter := EngineAdapter.new(root,not desktop)
	var digest := replay(core,engine_adapter)
	print("P1-MISSION-REPLAY profile=","client" if desktop else "headless"," display=",DisplayServer.get_name()," digest=",digest)
	var start := failures
	var baseline := root.get_child_count()
	var node_baseline := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var old_id := ""
	var old_handle := {}
	for i in 50:
		var m := Mission.new(core,engine_adapter,"switch")
		var prepared := m.prepare(encounter(0),Scene,Rule)
		check(prepared.ok,"open real scene")
		var handle: Dictionary = m.allocate_entity(null,{}).value
		if i > 0:
			check(not m.resolve_entity(old_id,old_handle).ok,"old MissionId cannot resolve even when handle fields coincide")
		old_id = prepared.value.mission_id
		old_handle = handle
		var started := Semaphore.new()
		var work := func(snapshot):
			started.post()
			OS.delay_msec(2)
			return snapshot.mission_id
		check(m.submit_worker("late",work).ok,"submit")
		started.wait()
		var closed := m.dispose()
		check(closed.ok and closed.value.workers.discarded==1 and closed.value.engine.released==1,"join in-flight job and release scene")
		check(m.collect_workers().is_empty() and root.get_child_count()==baseline and engine_adapter.counts()=={"scopes":0,"requests":0,"leases":0},"no stale result or live lease")
	check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))==node_baseline,"engine node count returns to baseline")
	print("T-MIS-RT-03 ","PASS" if start==failures else "FAIL"," switches=50 live_nodes=",node_baseline)
	var prior := Mission.new(Core.new(),engine_adapter,"reused")
	var prior_id: String = prior.prepare(encounter(0),Scene,Rule).value.mission_id
	var prior_handle: Dictionary = prior.allocate_entity(null,{}).value
	prior.dispose()
	var replacement := Mission.new(Core.new(),engine_adapter,"reused")
	var replacement_id: String = replacement.prepare(encounter(0),Scene,Rule).value.mission_id
	replacement.allocate_entity(null,{})
	check(prior_id != replacement_id and not replacement.resolve_entity(prior_id,prior_handle).ok,"recreated CORE cannot revive old namespaced handle")
	replacement.dispose()
	var next_engine := EngineAdapter.new(root,not desktop)
	var fresh := Mission.new(Core.new(),next_engine,"reused")
	var fresh_id: String = fresh.prepare(encounter(0),Scene,Rule).value.mission_id
	fresh.allocate_entity(null,{})
	check(fresh_id != prior_id and not fresh.resolve_entity(prior_id,prior_handle).ok,
		"fresh core and engine with repeated name cannot revive a retired MissionId")
	fresh.dispose()
	var failed := Mission.new(core,engine_adapter,"retry")
	check(not failed.prepare(encounter(),{"id":Scene.id,"simulation_scene":"res://missing.scene"},Rule).ok,"failed load")
	check(engine_adapter.counts().scopes==0 and failed.prepare(encounter(),Scene,Rule).ok,"prepare cleanup permits retry")
	check(failed.request_end({"outcome":"cancelled"}).ok and failed.finalize().error.code=="Unavailable","missing result producer is explicit")
	failed.dispose()
	print("MISSION failures=",failures)
	quit(1 if failures else 0)
