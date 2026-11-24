extends "res://contracts/ports/mission_port.gd"

const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const S = preload("res://contracts/schema.gd")
const C = preload("res://contracts/canonical.gd")
const Entities = preload("res://mission/runtime/entities.gd")
const PHASES := ["input","ai","movement","action","damage","objectives","snapshot"]

var _core: RefCounted
var _engine: RefCounted
var _key: String
var _builder: Callable
var _phase := "New"
var _mission := ""
var _tick := 0
var _token := {}
var _spec := {}
var _systems := {}
var _entities := Entities.new()
var _busy := false
var _reports := []
var _outcome := {}
var _result := {}

func _init(core: RefCounted, engine: RefCounted, mission_key: String, result_builder: Callable = Callable(),
		instance_id: String = "") -> void:
	_core = core
	_engine = engine
	_key = mission_key
	_builder = result_builder
	_mission = instance_id
	if _mission.is_empty():
		# A fresh authority can start after every local service has been replaced.
		var bytes := Crypto.new().generate_random_bytes(16)
		if bytes.size() == 16:
			bytes[6] = (bytes[6] & 0x0f) | 0x40
			bytes[8] = (bytes[8] & 0x3f) | 0x80
			var raw := bytes.hex_encode()
			_mission = "mission/%s-%s-%s-%s-%s" % [raw.left(8),raw.substr(8,4),raw.substr(12,4),raw.substr(16,4),raw.right(12)]

func prepare(spec: Dictionary, scene: Dictionary, ruleset: Dictionary) -> Dictionary:
	if _phase != "New" or _busy or _key.is_empty():
		return R.fail("InvalidState","phase")
	if _mission.is_empty() or not C.encode(_mission).ok:
		return R.fail("InvalidArgument","instance_id")
	for index in _mission.length():
		if _mission.unicode_at(index) < 32 or (_mission.unicode_at(index) >= 127 and _mission.unicode_at(index) <= 159):
			return R.fail("InvalidArgument","instance_id")
	var checked := S.validate_shape("EncounterSpec",spec)
	if not checked.ok:
		return checked
	if scene.get("id") != spec.scene_def_id or ruleset.get("id") != spec.ruleset_id:
		return R.fail("InvalidArgument","definitions")
	var teams := {}
	for side in spec.sides:
		if teams.has(side.team_key):
			return R.fail("Conflict","team_key")
		teams[side.team_key] = true
	_phase = "Preparing"
	var opened: Dictionary = _core.open_scope(_mission)
	if not opened.ok:
		_phase = "New"
		return opened
	_token = opened.value
	var engine_token: Dictionary = _engine.open_scope(_mission)
	if not engine_token.ok:
		return _undo_prepare(engine_token)
	var loaded: Dictionary = _engine.load_scene(scene,engine_token.value)
	if not loaded.ok:
		_engine.release_scope(_mission)
		return _undo_prepare(loaded)
	_spec = checked.value
	_entities = Entities.new(_spec.reserved_sources)
	_phase = "Deployment"
	return R.ok(view())

func _undo_prepare(error: Dictionary) -> Dictionary:
	_core.cancel_scope(_mission)
	_token = {}
	_phase = "New"
	return error

func view() -> Dictionary:
	return Entities.freeze({"mission_id":_mission,"mission_key":_key,"phase":_phase,"tick":_tick,
		"scene_def_id":_spec.get("scene_def_id"),"ruleset_id":_spec.get("ruleset_id"),
		"encounter_spec":_spec,"entities":_entities.rows(),"spawned_slots":_entities.spawned_slots(),"system_reports":_reports})

func register_system(phase: String, system: Dictionary) -> Dictionary:
	if _busy or _phase != "Deployment":
		return R.fail("InvalidState","phase")
	var id: Variant = system.get("id")
	if phase not in PHASES or typeof(id) != TYPE_STRING or id.is_empty() or typeof(system.get("run")) != TYPE_CALLABLE or not system.run.is_valid():
		return R.fail("InvalidArgument","system")
	if _systems.has(id):
		return R.fail("Conflict","system.id")
	_systems[id] = {"phase":phase,"run":system.run}
	return R.ok()

func _active() -> bool:
	return not _busy and _phase in ["Deployment","Running"]

func allocate_entity(source_slot: Variant, components: Dictionary) -> Dictionary:
	if not _active():
		return R.fail("InvalidState","phase")
	return _entities.allocate(source_slot,components,_spec.battle_limit)

func apply_deployment(orders: Array) -> Dictionary:
	if _busy or _phase != "Deployment":
		return R.fail("InvalidState","phase")
	var staged: Entities = _entities.fork()
	var handles := []
	for order in orders:
		if typeof(order) != TYPE_DICTIONARY or not order.has("source_slot") or typeof(order.get("components")) != TYPE_DICTIONARY:
			return R.fail("InvalidArgument","deployment")
		var allocated := staged.allocate(order.source_slot,order.components,_spec.battle_limit)
		if not allocated.ok:
			return allocated
		handles.append(allocated.value)
	_entities = staged
	return R.ok(Entities.freeze(handles))

func resolve_entity(mission_id: String, handle: Dictionary) -> Dictionary:
	if _phase in ["New","Disposed"]:
		return R.fail("NotFound","mission_id")
	return _entities.resolve(mission_id,handle,_mission)

func remove_entity(mission_id: String, handle: Dictionary) -> Dictionary:
	if not _active():
		return R.fail("InvalidState","phase")
	return _entities.remove(mission_id,handle,_mission)

func step_fixed(tick: Variant, inputs: Array) -> Dictionary:
	if not _active():
		return R.fail("InvalidState","phase")
	if tick != _tick+1 or not V.integer(tick):
		return R.fail("StaleVersion","tick")
	var batch := S.validate_shape("IntentBatch",{"mission_id":_mission,"source_tick":tick,"control_revision":0,"inputs":inputs})
	if not batch.ok:
		return batch
	for intent in batch.value.inputs:
		if not resolve_entity(_mission,intent.actor_handle).ok:
			return R.fail("NotFound","actor_handle")
		if intent.get("target_hint") != null and not resolve_entity(_mission,intent.target_hint).ok:
			return R.fail("NotFound","target_hint")
	var ids := _systems.keys()
	ids.sort()
	var reports := []
	var context := view()
	_busy = true
	for phase: String in PHASES:
		for id in ids:
			var system: Dictionary = _systems[id]
			if system.phase != phase:
				continue
			var report: Variant = system.run.call(context,batch.value)
			if typeof(report) != TYPE_DICTIONARY or typeof(report.get("ok")) != TYPE_BOOL:
				_busy = false
				return R.fail("InvalidArgument","system.result")
			if not report.ok:
				_busy = false
				return report
			if not C.encode(report.get("value")).ok:
				_busy = false
				return R.fail("InvalidArgument","system.value")
			reports.append({"id":id,"phase":phase,"value":Entities.freeze(report.get("value"))})
	_busy = false
	_reports = reports
	_tick = tick
	_phase = "Running"
	return R.ok(view())

func submit_worker(stable_key: String, work: Callable) -> Dictionary:
	if not _active():
		return R.fail("InvalidState","phase")
	return _core.submit_worker({"scope_id":_mission,"revision":_tick,"tick":_tick,"mission_id":_mission},
		_token,{"stable_key":stable_key,"run":work})

func collect_workers() -> Array:
	if not _active():
		return []
	return _core.collect_ready(_mission,_tick,{"tick":_tick,"mission_id":_mission})

func request_end(outcome: Dictionary) -> Dictionary:
	if not _active():
		return R.fail("InvalidState","phase")
	if typeof(outcome.get("outcome")) != TYPE_STRING or outcome.outcome.is_empty() or not C.encode(outcome).ok:
		return R.fail("InvalidArgument","outcome")
	_core.cancel_scope(_mission)
	_token = {}
	_outcome = Entities.freeze(outcome)
	_phase = "Ending"
	return R.ok()

func finalize() -> Dictionary:
	if _busy or _phase not in ["Ending","Finalizing"]:
		return R.fail("InvalidState","phase")
	if not _result.is_empty():
		return R.ok(_result)
	if not _builder.is_valid():
		return R.fail("Unavailable","result_builder")
	var ending := view()
	_busy = true
	var built: Variant = _builder.call(ending,_outcome)
	_busy = false
	if typeof(built) != TYPE_DICTIONARY or typeof(built.get("ok")) != TYPE_BOOL:
		return R.fail("InvalidArgument","result_builder")
	if not built.ok:
		return built
	var checked := S.validate_shape("MissionResult",built.get("value"))
	if not checked.ok:
		return checked
	var result: Dictionary = checked.value
	if result.mission_id != _mission or result.duration_ticks != _tick or result.outcome != _outcome.outcome:
		return R.fail("Conflict","mission_result")
	if result.slot_outcomes.size() != _entities.reserved_count:
		return R.fail("Conflict","slot_outcomes")
	for row in result.slot_outcomes:
		if not _entities.has_reserved_slot(row.source_slot_id):
			return R.fail("Conflict","slot_outcomes.source_slot_id")
		if (row.end_status == "not_spawned") == _entities.spawned.has(row.source_slot_id):
			return R.fail("Conflict","slot_outcomes.end_status")
	if _spec.mode == "campaign":
		checked = S.validate_settlement(_spec,result)
		if not checked.ok:
			return checked
	elif result.encounter_id != null or result.reservation_revision != null:
		return R.fail("Unauthorized","campaign_settlement")
	_result = result
	_phase = "Finalizing"
	return R.ok(_result)

func dispose() -> Dictionary:
	if _busy or _phase == "Preparing":
		return R.fail("InvalidState","phase")
	var barrier := {"discarded":0,"removed_jobs":0}
	var released := {"released":0,"cancelled":0}
	if not _token.is_empty():
		barrier = _core.cancel_scope(_mission)
	if _phase in ["Deployment","Running","Ending","Finalizing"]:
		released = _engine.release_scope(_mission)
	_phase = "Disposed"
	_token = {}
	_systems.clear()
	_spec = {}
	_entities = Entities.new()
	_reports = []
	_result = {}
	_outcome = {}
	_builder = Callable()
	_core = null
	_engine = null
	return R.ok({"phase":_phase,"workers":barrier,"engine":released})
