extends RefCounted

const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const C = preload("res://contracts/canonical.gd")
const Core = preload("res://core/runtime.gd")
const Inventory = preload("res://shared/inventory/inventory.gd")
const Characters = preload("res://campaign/character/ports/characters.gd")
const DAY := 1440
const PHASES := ["production", "ledger_validation", "market", "supply_payroll",
	"territory", "politics_ai", "day_end"]
const DAY_TXN := "@camp/day/"
const METADATA := ["schema_version","world_id","seed","game_minute","revision","last_committed_day",
	"rng_states","content_hash","content_packages","freeze"]

# The world contains committed metadata only. INV owns its live repository.
var _world := {}
var _characters := {}
var _resting_hero := ""
var _inventory_authority: Callable
var _inventory: Inventory
var _pending := {}
var _planning_core: Core
var _planners := {}
var _busy := false
var _disposed := false
var _day_failed := false


static func _packages_valid(packages: Variant) -> bool:
	if not C.is_json_array(packages):
		return false
	var seen := {}
	for pack in packages:
		if typeof(pack) != TYPE_DICTIONARY or pack.size() != 2 or not C.Reader.valid_key(pack.get("id")) or typeof(pack.get("version")) != TYPE_STRING or pack.version.is_empty() or seen.has(pack.id):
			return false
		seen[pack.id] = true
	return C.encode(packages).ok


func create_world(seed: String, start_def: Dictionary, content: Dictionary, authorize: Callable = Callable()) -> Dictionary:
	if _disposed or _busy or not _world.is_empty():
		return R.fail("InvalidState", "world")
	if not V.hex(seed, 16) or not V.hex(content.get("content_hash"), 64) or not _packages_valid(content.get("packages")):
		return R.fail("InvalidArgument", "content_or_seed")
	var minute: Variant = start_def.get("game_minute", 0)
	if not V.integer(minute) or not C.encode(start_def).ok:
		return R.fail("InvalidArgument", "start_def")
	for key in start_def:
		if key not in ["world_id","game_minute","locations","initial"]:
			return R.fail("InvalidArgument", "start_def.field")
	var initial: Variant = start_def.get("initial", [])
	if not C.is_json_array(initial) or (not initial.is_empty() and not start_def.has("locations")):
		return R.fail("InvalidArgument", "initial")
	# INV's genesis record order is observable in saves. Content iteration order must not choose it.
	var ordered: Array = initial.duplicate(true)
	ordered.sort_custom(func(a,b): return C.encode(a).value.get_string_from_utf8() < C.encode(b).value.get_string_from_utf8())
	var normalized := start_def.duplicate(true)
	normalized["initial"] = ordered
	var digest := C.hash_value([seed, normalized, content.content_hash])
	if not digest.ok:
		return digest
	var core := Core.new(seed, 0)
	core.open_scope("worldgen")
	var generator := core.derive_rng("worldgen", digest.value)
	var bits := "%08x%08x%08x%08x" % [generator.next_u32(), generator.next_u32(),
		generator.next_u32(), generator.next_u32()]
	var variant_nibble := "%x" % (8 | (bits.substr(16,1).hex_to_int() & 3))
	var generated := "world/%s-%s-4%s-%s%s-%s" % [bits.left(8), bits.substr(8,4),
		bits.substr(13,3), variant_nibble, bits.substr(17,3), bits.substr(20,12)]
	var streams := {"worldgen":generator.snapshot()}
	core.cancel_scope("worldgen")
	var world_id: Variant = start_def.get("world_id", generated)
	if not C.Reader.valid_key(world_id):
		return R.fail("InvalidArgument", "world_id")
	var inv: Inventory
	if start_def.has("locations"):
		if typeof(start_def.locations) != TYPE_DICTIONARY:
			return R.fail("InvalidArgument", "locations")
		inv = Inventory.new()
		var created := inv.initialize(start_def.locations, ordered, authorize)
		if not created.ok:
			return created
		var characters := Characters.validate({}, inv, world_id, minute)
		if not characters.ok:
			return characters
	_world = {"schema_version": 1, "world_id": world_id, "seed": seed, "game_minute": minute,
		"revision": 0, "last_committed_day": int(minute / DAY), "rng_states": streams,
		"content_hash": content.content_hash, "content_packages": content.packages.duplicate(true), "freeze": null}
	_inventory = inv
	_inventory_authority = authorize
	return save_snapshot()


## Public map projection. Private inventory, seed, pending plans and RNG states belong to the authority.
func read_snapshot(visibility_context: Dictionary = {}) -> Dictionary:
	if _world.is_empty():
		return R.fail("InvalidState", "world")
	if not C.encode(visibility_context).ok:
		return R.fail("InvalidArgument", "visibility_context")
	return R.ok({"world_id": _world.world_id, "game_minute": _world.game_minute, "revision": _world.revision,
		"last_committed_day": _world.last_committed_day, "frozen": _world.freeze != null,
		"content_hash": _world.content_hash})


func _snapshot_with(metadata: Dictionary, inventory_snapshot: Variant) -> Dictionary:
	var saved := metadata.duplicate(true)
	saved["inventory"] = inventory_snapshot
	if not _characters.is_empty():
		saved["characters"] = _characters.duplicate(true)
	return saved


func save_snapshot() -> Dictionary:
	if _world.is_empty() or _busy or not _pending.is_empty():
		return R.fail("InvalidState", "safe_point")
	return R.ok(_snapshot_with(_world, null if _inventory == null else _inventory.snapshot()))


func _can_write() -> bool:
	return not _world.is_empty() and _world.freeze == null and not _busy and not _day_failed


## Planners only prepare pure resource lines. Stable keys order independent domains within a phase.
func register_phase(phase: String, key: String, planner: Callable) -> Dictionary:
	if _disposed or _busy or not _pending.is_empty():
		return R.fail("InvalidState", "phase_registry")
	if phase not in PHASES or not C.Reader.valid_key(key) or not planner.is_valid():
		return R.fail("InvalidArgument", "planner")
	if not _planners.has(phase):
		_planners[phase] = {}
	if _planners[phase].has(key):
		return R.fail("Conflict", "planner")
	_planners[phase][key] = planner
	return R.ok()


func _begin_day(day: int) -> Dictionary:
	if _world.revision >= V.MAX_INTEGER or day > int(V.MAX_INTEGER / DAY):
		return R.fail("InvalidState", "revision_or_minute")
	var work := []
	for phase: String in PHASES:
		var keys: Array = _planners.get(phase, {}).keys()
		keys.sort()
		for key in keys:
			work.append([phase, key])
		work.append([phase, null])
	_planning_core = Core.new(_world.seed, 0)
	_planning_core.open_scope(_world.world_id)
	var restored := _planning_core.restore_rng(_world.world_id, _world.rng_states)
	if not restored.ok:
		_clear_day()
		return restored
	_pending = {"day": day, "base": _world.revision, "work": work, "cursor": 0,
		"lines": [], "token": {}}
	return R.ok()


func _clear_day() -> void:
	if _planning_core != null:
		_planning_core.cancel_scope(_world.world_id)
	_planning_core = null
	_pending = {}


func _day_txn() -> String:
	return DAY_TXN + str(_pending.day)


func _day_plan() -> Dictionary:
	if _inventory == null:
		return R.fail("InvalidState", "inventory")
	var allowed := Characters.permit_exchange(_characters, _inventory, _pending.lines)
	if not allowed.ok:
		return allowed
	return _inventory.prepare_exchange(_day_txn(), _pending.lines)


func _work_one() -> Dictionary:
	var item: Array = _pending.work[_pending.cursor]
	var phase: String = item[0]
	if item[1] == null:
		if phase == "ledger_validation" and not _pending.lines.is_empty():
			var valid := _day_plan()
			if not valid.ok:
				return valid
	else:
		var key: String = item[1]
		var planner: Callable = _planners[phase][key]
		if not planner.is_valid():
			return R.fail("Unavailable", "planner")
		var stream := _planning_core.derive_rng(_world.world_id, "day/" + phase + "/" + key)
		var context := {"world_id": _world.world_id, "day_id": _pending.day,
			"base_revision": _pending.base, "game_minute": _pending.day * DAY,
			"phase": phase, "key": key, "random_u32": stream.next_u32()}
		var output: Variant = planner.call(context)
		if typeof(output) != TYPE_DICTIONARY or typeof(output.get("ok")) != TYPE_BOOL:
			return R.fail("InvalidArgument", "planner.result")
		if not output.ok:
			return output if typeof(output.get("error")) == TYPE_DICTIONARY else R.fail("InvalidArgument", "planner.error")
		if not C.is_json_array(output.get("value")) or not C.encode(output.value).ok or _pending.lines.size() + output.value.size() > C.MAX_ITEMS:
			return R.fail("InvalidArgument", "planner.lines")
		var allowed := Characters.permit_exchange(_characters, _inventory, output.value)
		if not allowed.ok:
			return allowed
		_pending.lines.append_array(output.value.duplicate(true))
	_pending.cursor += 1
	if _pending.cursor == _pending.work.size():
		var token := {"world_id":_world.world_id, "day_id":_pending.day, "expected_revision":_pending.base}
		token.make_read_only()
		_pending.token = token
	return R.ok()


func _commit_prepared() -> Dictionary:
	if _pending.cursor != _pending.work.size() or _pending.base != _world.revision:
		return R.fail("StaleVersion", "day_plan")
	var streams := _planning_core.snapshot_rng(_world.world_id)
	if not streams.ok:
		return streams
	var recovered := _characters
	if not _characters.is_empty():
		var daily: Dictionary = Characters.recover(_characters, _world.world_id, _pending.day, _resting_hero)
		if not daily.ok:
			return daily
		recovered = daily.value
	if not _pending.lines.is_empty():
		var plan := _day_plan()
		if not plan.ok:
			return plan
		var committed := _inventory.commit(plan.value)
		if not committed.ok:
			return committed
	_characters = recovered
	_world.game_minute = _pending.day * DAY
	_world.last_committed_day = _pending.day
	_world.revision += 1
	_world.rng_states = streams.value
	_clear_day()
	return R.ok(_world.revision)


func prepare_day(day_id: Variant) -> Dictionary:
	if not _can_write() or not _pending.is_empty():
		return R.fail("InvalidState", "day")
	if not V.integer(day_id, 1) or day_id != _world.last_committed_day + 1:
		return R.fail("InvalidArgument", "day_id")
	_busy = true
	var checked := _begin_day(day_id)
	while checked.ok and _pending.cursor < _pending.work.size():
		checked = _work_one()
	_busy = false
	if not checked.ok:
		_clear_day()
		_day_failed = true
		return checked
	return R.ok(_pending.token)


func commit_day(plan: Dictionary) -> Dictionary:
	if not _can_write() or _pending.is_empty() or not is_same(plan, _pending.token):
		return R.fail("InvalidState", "day_plan")
	_busy = true
	var committed := _commit_prepared()
	_busy = false
	if not committed.ok:
		_clear_day()
		_day_failed = true
	return committed


## One budget unit buys a registered planner, a phase boundary, or an intra-day clock advance.
func step_until(target_minute: Variant, budget: Variant) -> Dictionary:
	if not _can_write():
		return R.fail("InvalidState", "step")
	if not V.integer(target_minute, _world.game_minute) or not V.integer(budget):
		return R.fail("InvalidArgument", "target_or_budget")
	if not _pending.is_empty() and target_minute < _pending.day * DAY:
		return R.fail("InvalidState", "pending_day")
	var used := 0
	var days := []
	_busy = true
	var result := R.ok()
	while used < budget and _world.game_minute < target_minute:
		var next_day: int = _world.last_committed_day + 1
		if int(target_minute / DAY) < next_day:
			if _world.revision >= V.MAX_INTEGER:
				result = R.fail("InvalidState", "revision")
				break
			_world.game_minute = target_minute
			_world.revision += 1
			used += 1
			break
		if _pending.is_empty():
			result = _begin_day(next_day)
			if not result.ok:
				break
		used += 1
		if _pending.cursor < _pending.work.size():
			result = _work_one()
			if not result.ok:
				break
		if _pending.cursor == _pending.work.size():
			result = _commit_prepared()
			if not result.ok:
				break
			days.append(next_day)
	_busy = false
	if not result.ok:
		_clear_day()
		_day_failed = true
		return result
	return R.ok({"used":used, "game_minute":_world.game_minute, "revision":_world.revision,
		"days_committed":days, "reached":_world.game_minute == target_minute})


func exchange(txn_id: String, lines: Array, expected_inventory_revision: Variant = -1, durable: Callable = Callable()) -> Dictionary:
	if not _can_write() or not _pending.is_empty() or _inventory == null:
		return R.fail("InvalidState", "inventory")
	if txn_id.begins_with(DAY_TXN):
		return R.fail("InvalidArgument", "txn_id")
	_busy = true
	var plan := _inventory.prepare_exchange(txn_id, lines, expected_inventory_revision)
	if not plan.ok:
		_busy = false
		return plan
	var new_txn: bool = not _inventory.ledger_for(txn_id).ok
	if new_txn:
		var allowed := Characters.permit_exchange(_characters, _inventory, lines)
		if not allowed.ok:
			_busy = false
			return allowed
	if new_txn and _world.revision >= V.MAX_INTEGER:
		_busy = false
		return R.fail("InvalidState", "revision")
	var checkpoint := func(inv_candidate: Dictionary, receipt: Dictionary):
		if not durable.is_valid():
			return R.fail("Unavailable", "durable")
		var snapshot := _snapshot_with(_world, inv_candidate)
		snapshot.revision += 1
		return durable.call(snapshot, receipt)
	var committed := _inventory.commit(plan.value, checkpoint if durable != Callable() else Callable())
	if committed.ok and new_txn:
		_world.revision += 1
	_busy = false
	return committed


func character_view() -> Dictionary:
	if _world.is_empty() or _busy:
		return R.fail("InvalidState", "character.view")
	var reply: Dictionary = Characters.view(_characters, _inventory, _world.world_id, _world.game_minute)
	if reply.ok:
		reply.value["world_id"] = _world.world_id
		reply.value["revision"] = _world.revision
		reply.value["game_minute"] = _world.game_minute
	return reply


func character_command(op: String, args: Dictionary, txn: String, durable: Callable) -> Dictionary:
	if not _can_write() or not _pending.is_empty() or _world.revision >= V.MAX_INTEGER:
		return R.fail("InvalidState", "character.command")
	if not durable.is_valid():
		return R.fail("Unavailable", "durable")
	if not C.Reader.valid_key(txn) or txn.is_empty():
		return R.fail("InvalidArgument", "transaction_id")
	_busy = true
	var result := _commit_character(op, args, txn, durable)
	_busy = false
	return result


func _commit_character(op: String, args: Dictionary, txn: String, durable: Callable) -> Dictionary:
	var result: Dictionary = Characters.plan(_characters, _inventory, op, args, _world.world_id, _world.game_minute, txn)
	if not result.ok:
		return result
	var plan: Dictionary = result.value
	if not V.integer(plan.minute, _world.game_minute):
		return R.fail("InvalidArgument", "character.minute")
	# Run normal phase planners on the proposal; disk failure must not expose a partial day or inventory.
	var candidate = get_script().new()
	candidate._world = _world.duplicate(true)
	candidate._characters = plan.repo
	candidate._resting_hero = plan.get("resting_id", "")
	candidate._inventory = plan.inventory
	candidate._inventory_authority = _inventory_authority
	candidate._planners = _planners
	if plan.minute / DAY > _world.last_committed_day and plan.inventory != null and is_same(plan.inventory, _inventory):
		var fork := Inventory.new()
		var cloned := fork.restore(_inventory.snapshot(), _inventory_authority)
		if not cloned.ok:
			return cloned
		candidate._inventory = fork
	if plan.minute > _world.game_minute:
		var elapsed: Dictionary = candidate.step_until(plan.minute, V.MAX_INTEGER)
		if not elapsed.ok:
			return elapsed
	candidate._world.revision = maxi(_world.revision + 1, candidate._world.revision)
	var saved: Dictionary = candidate.save_snapshot()
	if not saved.ok:
		return saved
	var written: Variant = durable.call(saved.value, {"committed_revision":candidate._world.revision})
	if not written is Dictionary or not written.get("ok") is bool:
		return R.fail("Unavailable", "durable")
	if not written.ok:
		return written if written.get("error") is Dictionary else R.fail("Unavailable", "durable")
	_world = candidate._world
	_characters = candidate._characters
	_inventory = candidate._inventory
	return R.ok(_world.revision)


func check_character_sources(sources: Array) -> Dictionary:
	if _characters.is_empty():
		return R.ok()
	var reserved := {}
	for source in sources:
		if not source is Dictionary or not source.has("hero_id"):
			return R.fail("InvalidArgument", "reserved_sources")
		if source.hero_id == null:
			continue
		if not V.typed_id(source.hero_id, "hero") or not V.integer(source.get("count"), 1, 1):
			return R.fail("InvalidArgument", "reserved_sources.hero")
		if reserved.has(source.hero_id):
			return R.fail("Conflict", "reserved_sources.hero_id")
		var checked: Dictionary = Characters.can_deploy(_characters, source.hero_id)
		if not checked.ok:
			return checked
		reserved[source.hero_id] = true
	return R.ok()


func freeze_for_encounter(id: String) -> Dictionary:
	if _world.is_empty() or _busy or _day_failed or not _pending.is_empty():
		return R.fail("InvalidState", "freeze")
	if not V.typed_id(id, "encounter"):
		return R.fail("InvalidArgument", "encounter_id")
	if _world.freeze != null:
		if _world.freeze.encounter_id == id:
			return R.ok(_world.freeze.duplicate())
		return R.fail("Conflict", "encounter_id")
	if _world.revision >= V.MAX_INTEGER - 1:
		return R.fail("InvalidState", "revision")
	_world.revision += 1
	_world.freeze = {"world_id":_world.world_id, "encounter_id":id, "revision":_world.revision}
	return R.ok(_world.freeze.duplicate())


func release_freeze(token: Dictionary) -> Dictionary:
	if _world.is_empty() or _busy or _world.freeze == null:
		return R.fail("InvalidState", "freeze")
	if not V.integer(token.get("revision"), 1) or _world.freeze != token:
		return R.fail("StaleVersion", "freeze")
	_world.freeze = null
	_world.revision += 1
	return R.ok()


func restore(saved: Dictionary, authorize: Callable = Callable()) -> Dictionary:
	if _busy or _disposed or not _pending.is_empty():
		return R.fail("InvalidState", "restore")
	if not V.integer(saved.get("schema_version"), 1, 1):
		return R.fail("StaleVersion", "schema_version")
	for key in saved:
		if key not in ["inventory", "characters"] and key not in METADATA:
			return R.fail("InvalidArgument", "snapshot.field")
	if not C.encode(saved).ok or not C.Reader.valid_key(saved.get("world_id")) or not V.hex(saved.get("seed"),16) or not V.hex(saved.get("content_hash"),64) or not _packages_valid(saved.get("content_packages")):
		return R.fail("InvalidArgument", "world")
	if not V.integer(saved.get("game_minute")) or not V.integer(saved.get("revision")) or not V.integer(saved.get("last_committed_day")) or saved.last_committed_day != int(saved.game_minute / DAY):
		return R.fail("InvalidArgument", "clock")
	if not saved.has_all(["freeze","inventory"]) or typeof(saved.get("rng_states")) != TYPE_DICTIONARY or not saved.rng_states.has("worldgen"):
		return R.fail("InvalidArgument", "repositories")
	if saved.freeze != null:
		var token: Variant = saved.freeze
		if typeof(token) != TYPE_DICTIONARY or token.size() != 3 or not V.typed_id(token.get("encounter_id"), "encounter") or token.get("world_id") != saved.world_id or not V.integer(token.get("revision"), 1, V.MAX_INTEGER - 1) or token.revision != saved.revision:
			return R.fail("InvalidArgument", "freeze")
	var core := Core.new(saved.seed, 0)
	core.open_scope(saved.world_id)
	var rng := core.restore_rng(saved.world_id, saved.rng_states)
	if rng.ok and core.snapshot_rng(saved.world_id).value != saved.rng_states:
		rng = R.fail("InvalidArgument", "rng_states")
	core.cancel_scope(saved.world_id)
	if not rng.ok:
		return rng
	var inv: Inventory
	if saved.inventory != null:
		if typeof(saved.inventory) != TYPE_DICTIONARY:
			return R.fail("InvalidArgument", "inventory")
		inv = Inventory.new()
		var checked := inv.restore(saved.inventory, authorize)
		if not checked.ok:
			return checked
	var characters: Variant = saved.get("characters", {})
	if not characters is Dictionary or (saved.has("characters") and characters.is_empty()):
		return R.fail("InvalidArgument", "characters")
	var checked_characters := Characters.validate(characters, inv, saved.world_id, saved.game_minute)
	if not checked_characters.ok:
		return checked_characters
	var metadata := {}
	for key: String in METADATA:
		metadata[key] = saved[key]
	_world = metadata.duplicate(true)
	_characters = characters.duplicate(true)
	_inventory = inv
	_inventory_authority = authorize
	_day_failed = false
	return R.ok()


func dispose() -> Dictionary:
	if _busy:
		return R.fail("InvalidState", "dispose")
	_clear_day()
	_world = {}
	_characters = {}
	_inventory = null
	_inventory_authority = Callable()
	_planners = {}
	_disposed = true
	return R.ok()
