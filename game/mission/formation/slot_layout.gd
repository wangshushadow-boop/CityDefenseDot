extends RefCounted
## One instance belongs to one formation in one Mission. Coordinates are metres, Y up.
## The supplied navigation projection accepts an entire batch and returns reachable
## world positions in candidate order, or a normal Result failure for the batch.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const KINDS := ["line", "shield_wall", "loose", "square", "circle", "wedge", "column"]

var _span := 0
var _slots: Array = []
var _projecting := false

func _init() -> void:
	_slots.make_read_only()

func fork() -> RefCounted:
	var next = get_script().new()
	next._span = _span
	next._slots = _slots
	return next

func slots() -> Array:
	return _slots

static func _grid(i: int, count: int, columns: int, dx: float, dz: float) -> Vector3:
	@warning_ignore("integer_division")
	var row := i / columns
	var rows := ceili(float(count) / columns)
	var occupied_columns := mini(columns, count - row * columns)
	return Vector3((i % columns - (occupied_columns - 1) * 0.5) * dx, 0,
			(row - (rows - 1) * 0.5) * dz)

static func _offsets(kind: String, count: int, spacing: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(count)
	if count < 2:
		return result
	var columns := ceili(sqrt(count * 4.0))
	if kind == "shield_wall":
		columns = ceili(sqrt(count * 2.0))
	var wedge_rows := ceili((sqrt(8.0 * count + 1.0) - 1.0) * 0.5)
	for i in count:
		match kind:
			"line":
				result[i] = _grid(i, count, columns, spacing, spacing)
			"shield_wall":
				result[i] = _grid(i, count, columns, spacing, spacing * 0.85)
			"loose":
				result[i] = _grid(i, count, columns, spacing * 1.75, spacing * 1.75)
			"column":
				result[i] = _grid(i, count, 1, spacing, spacing)
			"wedge":
				var row := floori((sqrt(8.0 * i + 1.0) - 1.0) * 0.5)
				@warning_ignore("integer_division")
				var first := row * (row + 1) / 2
				result[i] = Vector3((i - first - (mini(row + 1, count - first) - 1) * 0.5) * spacing,
						0, (row - (wedge_rows - 1) * 0.5) * spacing)
			"circle":
				var angle := TAU * i / count
				var radius := spacing / (2.0 * sin(PI / count))
				result[i] = Vector3(sin(angle), 0, -cos(angle)) * radius
			"square":
				# Evenly walk the four sides without duplicating the corners.
				var edge := 4.0 * i / count
				var half_side := spacing * count / 8.0
				var along := (2.0 * fmod(edge, 1.0) - 1.0) * half_side
				match floori(edge):
					0: result[i] = Vector3(along, 0, -half_side)
					1: result[i] = Vector3(half_side, 0, along)
					2: result[i] = Vector3(-along, 0, half_side)
					3: result[i] = Vector3(-half_side, 0, -along)
	return result

func rebuild(members: Array, kind: String, center: Vector3, yaw: float, spacing: float,
		clear_width: float, project: Callable) -> Dictionary:
	if _projecting:
		return R.fail("InvalidState", "slot_projection")
	if kind not in KINDS or not center.is_finite() or not is_finite(yaw):
		return R.fail("InvalidArgument", "formation_layout")
	if not is_finite(spacing) or spacing <= 0 or is_nan(clear_width) or clear_width < 0 or not project.is_valid():
		return R.fail("InvalidArgument", "formation_terrain")
	if not members.is_empty() and clear_width < spacing:
		return R.fail("Unavailable", "corridor_width")

	var roster := {}
	for handle in members:
		if typeof(handle) != TYPE_DICTIONARY or handle.size() != 2 or not V.integer(handle.get("index"), 0, V.MAX_U32) or not V.integer(handle.get("generation"), 1, V.MAX_U32):
			return R.fail("InvalidArgument", "member_handle")
		if roster.has(handle.index):
			return R.fail("Conflict", "member_handle")
		var copy: Dictionary = handle.duplicate()
		copy.make_read_only()
		roster[copy.index] = copy

	var count := roster.size()
	# Keep holes after small losses so even survivors on curved layouts stay put.
	# A badly depleted formation compacts instead of retaining an empty footprint.
	var span := _span if count <= _span and count * 4 >= _span * 3 else count
	var offsets := _offsets(kind, span, spacing)
	var extent := 0.0
	for offset in offsets:
		extent = maxf(extent, absf(offset.x))
	var compressed := not offsets.is_empty() and 2.0 * extent + spacing > clear_width
	if compressed:
		var columns := clampi(floori(clear_width / spacing), 1, span)
		for i in span:
			offsets[i] = _grid(i, span, columns, spacing, spacing)

	var assigned := {}
	for old in _slots:
		var current: Variant = roster.get(old.member.index)
		if current != null and current.generation == old.member.generation and old.slot_id < span:
			assigned[old.slot_id] = current
			roster.erase(current.index)
	var remaining := roster.keys()
	remaining.sort()
	var cursor := 0
	var ids := PackedInt32Array()
	var points := PackedVector3Array()
	for i in span:
		if not assigned.has(i):
			if cursor >= remaining.size():
				continue
			assigned[i] = roster[remaining[cursor]]
			cursor += 1
		ids.append(i)
		var point := center + offsets[i].rotated(Vector3.UP, yaw)
		if not point.is_finite():
			return R.fail("InvalidArgument", "slot_position")
		points.append(point)

	var positions := PackedVector3Array()
	if not points.is_empty():
		_projecting = true
		var reply: Variant = project.call(points)
		_projecting = false
		if typeof(reply) != TYPE_DICTIONARY or typeof(reply.get("ok")) != TYPE_BOOL:
			return R.fail("InvalidArgument", "slot_projection")
		if not reply.ok:
			return reply if typeof(reply.get("error")) == TYPE_DICTIONARY else R.fail("InvalidArgument", "slot_projection")
		if typeof(reply.get("value")) != TYPE_PACKED_VECTOR3_ARRAY or reply.value.size() != count:
			return R.fail("InvalidArgument", "slot_projection")
		positions = reply.value

	var staged := []
	var used := {}
	for j in ids.size():
		var id := ids[j]
		var position := positions[j]
		if not position.is_finite():
			return R.fail("InvalidArgument", "projected_position")
		var key := (position * 1000.0).round()
		if not key.is_finite() or used.has(key):
			return R.fail("Unavailable", "projected_position")
		used[key] = true
		var slot := {"slot_id": id, "local_offset": offsets[id], "position": position, "member": assigned[id]}
		slot.make_read_only()
		staged.append(slot)
	staged.make_read_only()
	_slots = staged
	_span = span
	return R.ok({"requested_layout": kind, "compressed": compressed, "slots": _slots})
