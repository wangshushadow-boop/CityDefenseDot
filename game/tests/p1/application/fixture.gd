extends RefCounted
## The authority and reward rule belong to this fixture. All stores and runtimes are real.
const App = preload("res://application/game_session.gd")
const Camp = preload("res://campaign/runtime.gd")
const Mission = preload("res://mission/runtime/runtime.gd")
const Core = preload("res://core/runtime.gd")
const EngineAdapter = preload("res://infrastructure/engine/adapter.gd")
const C = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const COIN := {"kind":"currency","id":"base:currency/copper"}
const CONTENT := {"packages":[{"id":"base","version":"1.0.0"}],"content_hash":"3535353535353535353535353535353535353535353535353535353535353535"}
const SCENE := {"id":"base:scene/field","simulation_scene":EngineAdapter.DEFAULT_SCENE}
const RULE := {"id":"base:rule/field"}
const ENCOUNTER := "encounter/00000000-0000-4000-8000-000000000001"

static func options(slot: String) -> Dictionary:
	var account := {"kind":"account","currency":"base:currency/copper"}
	var start := {"locations":{"purse":account,"town":account,"pool":account},
		"initial":[{"holder":"purse","resource":COIN,"amount":100},{"holder":"pool","resource":COIN,"amount":1000}]}
	return {"slot":slot,"seed":"1234567890abcdef","start_def":start,"content":CONTENT}

static func spec(mode: String, revision: int) -> Dictionary:
	var source := {"source_party_id":"party/00000000-0000-4000-8000-000000000001","troop_def_id":"base:troop/guard",
		"hero_id":null,"count":1,"source_slot_range":[1,2],"loadout_snapshot_id":"gear"}
	return {"schema_version":1,"encounter_id":ENCOUNTER,"reservation_revision":revision,"mode":mode,
		"scene_def_id":SCENE.id,"ruleset_id":RULE.id,"environment":{},"rng_seed":"1234567890abcdef",
		"sides":[{"team_key":0,"faction_id":"base:faction/a","commander_hero_id":null,"roster_allocations":[]}],
		"reserved_sources":[source],"battle_limit":1,"deployment_constraints":{},"siege_snapshot":null}

static func line(src: String, dst: String, amount: int) -> Dictionary:
	return {"src":src,"dst":dst,"resource":COIN,"amount":amount,"reason":"fixture","source_ref":"fixture"}

static func command(world: Dictionary, id: String, amount: int = 2) -> Dictionary:
	return {"command_id":id,"scope_id":world.world_id,"actor_ref":"player","expected_revision":world.revision,
		"issued_tick":null,"sequence":null,"payload":{"type":"exchange","lines":[line("purse","town",amount)]}}

static func authorize(token: Variant, action: String, cmd: Dictionary) -> Dictionary:
	if token!="local-token" or action!="exchange" or not C.is_json_array(cmd.payload.get("lines")):
		return R.fail("Unauthorized","authority")
	for entry in cmd.payload.lines:
		if typeof(entry)!=TYPE_DICTIONARY or entry.get("src")!="purse" or entry.get("dst")!="town":
			return R.fail("Unauthorized","holder")
	return R.ok("player")

static func build(view: Dictionary, ending: Dictionary) -> Dictionary:
	var encounter: Dictionary=view.encounter_spec
	var slots := []
	for source in encounter.reserved_sources:
		for n in range(source.source_slot_range[0],source.source_slot_range[1]):
			slots.append({"source_slot_id":n,"end_status":"alive" if n in view.spawned_slots else "not_spawned",
				"wounded":false,"captor_team_key":null,"xp":0})
	var campaign: bool=encounter.mode=="campaign"
	var result := {"schema_version":1,"result_id":"result/"+view.mission_id,"mission_id":view.mission_id,
		"encounter_id":encounter.encounter_id if campaign else null,"reservation_revision":encounter.reservation_revision if campaign else null,
		"outcome":ending.outcome,"duration_ticks":view.tick,"winner_team_keys":[],"objective_results":[],"slot_outcomes":slots,
		"loot_claims":[],"hero_outcomes":[],"siege_changes":null,"reward_intents":[],"stats":{}}
	result["integrity_hash"]=C.hash_value(result).value
	return R.ok(result)

static func make_session(node: Node, persist: RefCounted, adapter: RefCounted = null, sink: Callable = Callable()) -> RefCounted:
	var engine_adapter: RefCounted=EngineAdapter.new(node,true) if adapter==null else adapter
	var core := Core.new("1234567890abcdef")
	var factory := func(mode: String): return Mission.new(core,engine_adapter,mode,build)
	var settlement := func(_spec: Dictionary,_result: Dictionary): return R.ok([line("pool","purse",7)])
	return App.new(persist,func(): return Camp.new(),factory,authorize,settlement,sink)
