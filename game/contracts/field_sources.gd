extends RefCounted

const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const S = preload("res://contracts/schema.gd")
const C = preload("res://contracts/canonical.gd")

class Index:
	extends RefCounted
	var _ranges: Array

	func _init(ranges: Array) -> void:
		_ranges = ranges
		_ranges.make_read_only()

	func team_for_slot(slot: Variant) -> Dictionary:
		if not V.integer(slot, 0, V.MAX_U32):
			return R.fail("InvalidArgument", "source_slot_id")
		var i := _ranges.bsearch_custom([slot], func(a, b): return a[0] < b[0], false) - 1
		if i < 0 or slot >= _ranges[i][1]:
			return R.fail("NotFound", "source_slot_id")
		return R.ok(_ranges[i][2])


# Equal changes at every interval endpoint imply equal coverage at every slot.
static func _mark(changes: Dictionary, position: int, delta: int) -> void:
	var total: int = changes.get(position, 0) + delta
	if total == 0:
		changes.erase(position)
	else:
		changes[position] = total


static func build(spec: Variant) -> Dictionary:
	var checked := S.validate_shape("EncounterSpec", spec)
	if not checked.ok:
		return checked
	var encounter: Dictionary = checked.value
	if encounter.sides.size() < 2:
		return R.fail("InvalidArgument", "sides")
	if encounter.reserved_sources.is_empty():
		return R.fail("InvalidArgument", "reserved_sources")
	var changes := {}
	for reservation in encounter.reserved_sources:
		var bounds: Array = reservation.source_slot_range
		_mark(changes, bounds[0], 1)
		_mark(changes, bounds[1], -1)

	var teams := {}
	var ranges := []
	for side_id in encounter.sides.size():
		var side: Dictionary = encounter.sides[side_id]
		var side_path := "sides[%d]" % side_id
		if teams.has(side.team_key):
			return R.fail("Conflict", side_path + ".team_key")
		teams[side.team_key] = true
		if side.roster_allocations.is_empty():
			return R.fail("InvalidArgument", side_path + ".roster_allocations")
		for allocation_id in side.roster_allocations.size():
			var allocation: Variant = side.roster_allocations[allocation_id]
			var path := "%s.roster_allocations[%d]" % [side_path, allocation_id]
			if typeof(allocation) != TYPE_DICTIONARY or allocation.size() != 1 or not allocation.has("source_slot_range"):
				return R.fail("InvalidArgument", path)
			var bounds: Variant = allocation.source_slot_range
			if not C.is_json_array(bounds) or bounds.size() != 2:
				return R.fail("InvalidArgument", path + ".source_slot_range")
			if not V.integer(bounds[0], 0, V.MAX_U32) or not V.integer(bounds[1], 1, V.MAX_U32 + 1) or bounds[1] <= bounds[0]:
				return R.fail("InvalidArgument", path + ".source_slot_range")
			_mark(changes, bounds[0], -1)
			_mark(changes, bounds[1], 1)
			var entry := [bounds[0], bounds[1], side.team_key]
			entry.make_read_only()
			ranges.append(entry)
	ranges.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(1, ranges.size()):
		if ranges[i][0] < ranges[i - 1][1]:
			return R.fail("Conflict", "sides.roster_allocations.source_slot_range")
	if not changes.is_empty():
		return R.fail("InvalidArgument", "sides.roster_allocations.source_slot_range")
	return R.ok(Index.new(ranges))
