extends RefCounted
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const C = preload("res://contracts/canonical.gd")

var occupied := {}
var generations := {}
var free_indices: Array[int] = []
var spawned := {}
var active_sources := 0
var next_index := 0
var reserved_count := 0
var _slot_boundaries := PackedInt64Array()

func _init(sources: Array = []) -> void:
	# EncounterSpec already guarantees disjoint half-open ranges.
	for source in sources:
		_slot_boundaries.append(source.source_slot_range[0])
		_slot_boundaries.append(source.source_slot_range[1])
		reserved_count += source.count
	_slot_boundaries.sort()

func has_reserved_slot(slot: int) -> bool:
	# An odd number of boundaries at or below the slot puts it inside a range.
	return _slot_boundaries.bsearch(slot, false) % 2 == 1

func fork():
	var copy = get_script().new()
	copy.occupied = occupied.duplicate()
	copy.generations = generations.duplicate()
	copy.free_indices = free_indices.duplicate()
	copy.spawned = spawned.duplicate()
	copy.active_sources = active_sources
	copy.next_index = next_index
	copy.reserved_count = reserved_count
	copy._slot_boundaries = _slot_boundaries
	return copy

static func freeze(value: Variant) -> Variant:
	if C.is_nul_text(value):
		return C.nul_text(value)
	if typeof(value)==TYPE_DICTIONARY:
		var data := {}
		for key in value:
			data[key] = freeze(value[key])
		data.make_read_only()
		return data
	if typeof(value)==TYPE_ARRAY:
		var data := []
		for item in value:
			data.append(freeze(item))
		data.make_read_only()
		return data
	return value

func allocate(slot: Variant, components: Dictionary, battle_limit: int) -> Dictionary:
	if slot != null:
		if not V.integer(slot,0,V.MAX_U32):
			return R.fail("InvalidArgument","source_slot")
		if components.get("type") in ["mount", "projectile", "siege_engine"]:
			return R.fail("InvalidArgument","source_slot")
		if not has_reserved_slot(slot):
			return R.fail("NotFound","source_slot")
		if spawned.has(slot):
			return R.fail("Conflict","source_slot")
		if active_sources >= battle_limit:
			return R.fail("Unavailable","battle_limit")
	if not C.encode(components).ok:
		return R.fail("InvalidArgument","components")
	var index: int
	if free_indices.is_empty():
		if next_index > V.MAX_U32:
			return R.fail("Unavailable","entity_slots")
		index = next_index
		next_index += 1
		generations[index] = 1
	else:
		index = free_indices.pop_back()
	var handle := {"index":index,"generation":generations[index]}
	handle.make_read_only()
	occupied[index] = freeze({"handle":handle,"source_slot":slot,"components":components})
	if slot != null:
		spawned[slot] = true
		active_sources += 1
	return R.ok(handle)

func resolve(scope: String, handle: Dictionary, current: String) -> Dictionary:
	var checked := V.resolve_handle(scope,handle,current,generations)
	if not checked.ok or not occupied.has(handle.get("index")):
		return R.fail("NotFound","actor_handle")
	return R.ok(occupied[handle.index])

func remove(scope: String, handle: Dictionary, current: String) -> Dictionary:
	var checked := resolve(scope,handle,current)
	if not checked.ok:
		return checked
	if checked.value.source_slot != null:
		active_sources -= 1
	occupied.erase(handle.index)
	if handle.generation < V.MAX_U32:
		generations[handle.index] += 1
		free_indices.append(handle.index)
	return R.ok()

func rows() -> Array:
	var result := []
	var keys := occupied.keys()
	keys.sort()
	for key in keys:
		result.append(occupied[key])
	return result

func spawned_slots() -> Array:
	var keys := spawned.keys()
	keys.sort()
	return keys
