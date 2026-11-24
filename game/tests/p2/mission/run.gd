extends SceneTree
const Mission = preload("res://mission/runtime/runtime.gd")
const Core = preload("res://core/runtime.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const Canon = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const UUID := "b48883c0-79fb-4cd3-96fe-43bb44dfddbb"
const LAST_SLOT := 4294967295
const SCENE := {"id":"base:scene/field", "simulation_scene":Adapter.DEFAULT_SCENE}
const RULE := {"id":"base:rule/field"}
var failures := 0
var fault := ""

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		printerr("FAIL ", label)
		failures += 1

func source(first: int, count: int) -> Dictionary:
	return {"source_party_id":"party/"+UUID, "troop_def_id":"base:troop/guard", "hero_id":null,
		"count":count, "source_slot_range":[first, first+count], "loadout_snapshot_id":"gear"}

func spec(mode: String, sources: Array) -> Dictionary:
	return {"schema_version":1, "encounter_id":"encounter/"+UUID, "reservation_revision":2, "mode":mode,
		"scene_def_id":SCENE.id, "ruleset_id":RULE.id, "environment":{}, "rng_seed":"1234567890abcdef",
		"sides":[{"team_key":0, "faction_id":"base:faction/a", "commander_hero_id":null, "roster_allocations":[]}],
		"reserved_sources":sources, "battle_limit":500, "deployment_constraints":{}, "siege_snapshot":null}

# This fixture supplies only a result. Source coverage, deployment and finalization run in Mission.
func result_for(snapshot: Dictionary, outcome: Dictionary) -> Dictionary:
	var encounter: Dictionary = snapshot.encounter_spec
	var spawned := {}
	for slot in snapshot.spawned_slots:
		spawned[slot] = true
	var rows := []
	for reservation in encounter.reserved_sources:
		for slot in range(reservation.source_slot_range[0], reservation.source_slot_range[1]):
			rows.append({"source_slot_id":slot, "end_status":"withdrawn" if spawned.has(slot) else "not_spawned",
				"wounded":false, "captor_team_key":null, "xp":0})
	match fault:
		"omit": rows.pop_back()
		"foreign": rows.back().source_slot_id = 999
		"wrong_status": rows.front().end_status = "alive"
	var campaign: bool = encounter.mode == "campaign"
	var result := {"schema_version":1, "result_id":"withdrawal", "encounter_id":encounter.encounter_id if campaign else null,
		"mission_id":snapshot.mission_id, "reservation_revision":encounter.reservation_revision if campaign else null,
		"outcome":outcome.outcome, "duration_ticks":snapshot.tick, "winner_team_keys":[], "objective_results":[],
		"slot_outcomes":rows, "loot_claims":[], "hero_outcomes":[], "siege_changes":null, "reward_intents":[], "stats":{}}
	result["integrity_hash"] = Canon.hash_value(result).value
	return R.ok(result)

func slot_at(index: int) -> int:
	if index == 999:
		return LAST_SLOT
	return index if index < 2 else index*3

func waves(core: RefCounted, adapter: RefCounted) -> void:
	var sources := []
	for i in range(999, -1, -1):
		sources.append(source(slot_at(i), 1))
	var mission := Mission.new(core, adapter, "waves", result_for)
	var prepared := mission.prepare(spec("campaign", sources), SCENE, RULE)
	check(prepared.ok, "sparse unordered reservations")
	if not prepared.ok:
		return
	var id: String = prepared.value.mission_id
	var orders := []
	for i in 500:
		orders.append({"source_slot":slot_at(i), "components":{}})
	var bad_orders := orders.duplicate()
	bad_orders.append({"source_slot":slot_at(500), "components":{}})
	check(mission.apply_deployment(bad_orders).error.field == "battle_limit", "over-capacity batch")
	check(mission.view().spawned_slots.is_empty() and mission.view().entities.is_empty(), "batch rollback")
	for illegal in [-1, LAST_SLOT+1, 0.5, "0", true]:
		check(mission.allocate_entity(illegal, {}).error.code == "InvalidArgument", "reject invalid slot")
	check(mission.allocate_entity(2, {}).error.code == "NotFound", "gap after adjacent reservations")
	for kind in ["mount", "projectile", "siege_engine"]:
		check(mission.allocate_entity(0, {"type":kind}).error.code == "InvalidArgument", "auxiliary must have no source")
	var deployed := mission.apply_deployment(orders)
	check(deployed.ok and deployed.value.size() == 500, "first wave")
	if not deployed.ok:
		mission.dispose()
		return
	var handles: Array = deployed.value.duplicate()
	check(handles[0] == {"index":0, "generation":1}, "failed batch kept first handle unissued")
	var extra := mission.allocate_entity(null, {"type":"mount"})
	check(extra.ok and mission.remove_entity(id, extra.value).ok, "auxiliary does not consume army capacity")
	check(mission.allocate_entity(slot_at(500), {}).error.field == "battle_limit", "auxiliary removal freed no human slot")
	for wave in 2:
		check(mission.step_fixed(wave+1, []).ok, "mission fixed step")
		for i in 200:
			var index: int = wave*200+i
			var retired: Dictionary = handles[index]
			check(mission.remove_entity(id, retired).ok, "release human capacity")
			check(mission.allocate_entity(slot_at(index), {}).error.code == "Conflict", "retired slot never respawns")
			var newcomer := mission.allocate_entity(slot_at(500+index), {})
			check(newcomer.ok and newcomer.value.index == retired.index and newcomer.value.generation == retired.generation+1, "generation on reinforcement")
			check(mission.resolve_entity(id, retired).error.code == "NotFound", "retired handle invalid")
		check(mission.view().entities.size() == 500, "active wave limit")
	check(mission.request_end({"outcome":"withdrawn"}).ok, "withdraw before all reservations enter")
	check(mission.allocate_entity(LAST_SLOT, {}).error.code == "InvalidState", "late spawn after withdrawal")
	var final := mission.finalize()
	check(final.ok, "finish withdrawal "+str(final.get("error", {})))
	if final.ok:
		var seen := {}
		var entered := 0
		for row in final.value.slot_outcomes:
			seen[row.source_slot_id] = row.end_status
			if row.end_status == "withdrawn":
				entered += 1
		check(entered == 900 and seen.size() == 1000 and seen[LAST_SLOT] == "not_spawned", "900 unique spawned, 100 never entered")
		check(mission.finalize() == final, "repeated finalization")
		print("WAVES reserved=1000 initial=500 added=200+200 active=500 entered=",entered," never_entered=",seen.size()-entered)
	mission.dispose()

func result_boundaries(mode: String, core: RefCounted, adapter: RefCounted) -> void:
	var mission := Mission.new(core, adapter, mode, result_for)
	var ready := mission.prepare(spec(mode, [source(LAST_SLOT-1, 2)]), SCENE, RULE)
	check(ready.ok and mission.allocate_entity(LAST_SLOT, {}).ok, "UINT32 upper bound")
	check(mission.request_end({"outcome":"withdrawn"}).ok, "small result")
	for variant in ["omit", "foreign", "wrong_status"]:
		fault = variant
		var rejected := mission.finalize()
		check(not rejected.ok and rejected.error.code == "Conflict", mode+" rejects "+variant+" "+str(rejected.get("error", {})))
	fault = ""
	var final := mission.finalize()
	check(final.ok, "retry with exact coverage "+str(final.get("error", {})))
	mission.dispose()

func run() -> void:
	var core := Core.new("1234567890abcdef")
	var adapter := Adapter.new(root, true)
	waves(core, adapter)
	for mode in ["custom", "multiplayer"]:
		result_boundaries(mode, core, adapter)
	var visit := Mission.new(core, adapter, "visit", result_for)
	check(visit.prepare(spec("custom", []), SCENE, RULE).ok, "non-army mission")
	check(visit.allocate_entity(null, {"type":"human"}).ok and visit.view().spawned_slots.is_empty(), "civilian with no army source")
	check(visit.request_end({"outcome":"completed"}).ok and visit.finalize().ok, "civilian supplies no slot outcome")
	visit.dispose()
	check(adapter.counts() == {"scopes":0,"requests":0,"leases":0}, "all mission scopes released")
	failures += await preload("res://tests/p2/mission/field_cases.gd").new().run(self)
	print("P2-MISSION-SOURCE ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
