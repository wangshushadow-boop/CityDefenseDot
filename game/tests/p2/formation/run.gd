extends SceneTree

const Layout = preload("res://mission/formation/slot_layout.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const R = preload("res://contracts/result.gd")
const FLOOR := {"id":"test:scene/formation_floor", "simulation_scene":"res://tests/p2/formation/floor.tscn"}
const SCOPE := "formation-layout-test"
const OPEN := Vector3(-500, 0, -800)
const NARROW := Vector3(0, 0, 600)
var failures := 0
var projected := 0
var adapter: Adapter
var nav_revision: int
var origin: Vector3

func check(good: bool, message: String) -> void:
	if not good:
		failures += 1
		printerr("FAIL ", message)

func _initialize() -> void:
	run.call_deferred()

func _mm(pos: Vector3) -> Array:
	return [roundi(pos.x * 1000), roundi(pos.y * 1000), roundi(pos.z * 1000)]

func _on_nav(points: PackedVector3Array) -> Dictionary:
	var requests := []
	var start := _mm(origin)
	for point in points:
		requests.append({"from":start, "to":_mm(point)})
	var reply := adapter.query_path_batch(requests, nav_revision, SCOPE)
	if not reply.ok:
		return reply
	var positions := PackedVector3Array()
	for path in reply.value:
		if not path.reachable:
			return R.fail("Unavailable", "unreachable_slot")
		var end: Array = path.points[-1]
		positions.append(Vector3(end[0], end[1], end[2]) * 0.001)
	projected += positions.size()
	return R.ok(positions)

func _roster(count: int) -> Array:
	var handles := []
	for i in count:
		handles.append({"index": i, "generation": 1})
	return handles

func _build(layout: Layout, roster: Array, kind: String, at: Vector3 = OPEN, width: float = INF) -> Dictionary:
	origin = at
	return layout.rebuild(roster, kind, at, 0, 1.0, width, _on_nav)

func _check_slots(slots: Array, roster: Array) -> void:
	var ids := {}
	var points := {}
	var handles := {}
	for row in slots:
		ids[row.slot_id] = true
		points[row.position] = true
		handles[row.member.index] = row.member.generation
	check(slots.size() == roster.size() and ids.size() == roster.size() and points.size() == roster.size(), "unique slots and reachable targets")
	var matches := handles.size() == roster.size()
	for handle in roster:
		matches = matches and handles.get(handle.index, 0) == handle.generation
	check(matches, "exact member coverage")

func _exercise(count: int) -> void:
	var roster := _roster(count)
	var shuffled := roster.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 241124
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap
	var layout := Layout.new()
	var replay := Layout.new()
	var shapes := []
	var started := Time.get_ticks_usec()
	for kind: String in Layout.KINDS:
		var wide := _build(layout, roster, kind)
		var repeated := _build(replay, shuffled, kind)
		check(wide.ok and repeated.ok, "navigation projection " + kind)
		if not wide.ok or not repeated.ok:
			continue
		var slots: Array = wide.value.slots
		_check_slots(slots, roster)
		check(not wide.value.compressed and slots == repeated.value.slots, "same formation after shuffled roster " + kind)
		var offsets := PackedVector3Array()
		for slot in slots:
			offsets.append(slot.local_offset)
		check(not offsets in shapes, "distinct geometry " + kind)
		shapes.append(offsets)
		# A survivor's physical offset and slot stay identical after a loss.
		var survivors := roster.duplicate()
		survivors.remove_at(2)
		var loss := _build(layout, survivors, kind)
		check(loss.ok, "loss projection")
		if not loss.ok:
			continue
		_check_slots(loss.value.slots, survivors)
		for slot in loss.value.slots:
			check(slots[slot.slot_id] == slot, "survivor target changed")
		var passage := _build(layout, survivors, kind, NARROW, 1)
		check(passage.ok and passage.value.compressed == (kind != "column"), "1 m corridor " + kind)
		if passage.ok:
			_check_slots(passage.value.slots, survivors)
			for slot in passage.value.slots:
				check(absf(slot.position.x) < 0.001, "slot outside corridor")
		var restored := _build(layout, roster, kind)
		check(restored.ok and restored.value.slots == slots, "regain footprint after corridor and reinforcement")
	print("P2-FORM-GEOMETRY count=", count, " kinds=", shapes.size(), " elapsed_us=", Time.get_ticks_usec() - started)

func _failures_and_rotation() -> void:
	var layout := Layout.new()
	var roster := _roster(15)
	var initial := _build(layout, roster, "line")
	check(initial.ok, "rollback seed")
	if not initial.ok:
		return
	var saved := layout.slots()
	var outside := _build(layout, roster, "line", Vector3(500, 0, 600))
	check(not outside.ok and outside.error.field == "unreachable_slot" and is_same(saved, layout.slots()), "off-mesh rollback")
	var collapsed := func(points: PackedVector3Array):
		points.fill(OPEN)
		return R.ok(points)
	var bad := layout.rebuild(roster, "line", OPEN, 0, 1, INF, collapsed)
	check(not bad.ok and bad.error.code == "Unavailable" and is_same(saved, layout.slots()), "duplicate projections")
	var malformed := func(_points): return R.ok([Vector3.ZERO])
	check(not layout.rebuild(roster, "square", OPEN, 0, 1, INF, malformed).ok and is_same(saved, layout.slots()), "bad projection")
	check(not _build(layout, roster, "line", NARROW, 0.1).ok and is_same(saved, layout.slots()), "body cannot fit")
	var duplicate := roster.duplicate()
	duplicate.append({"index": 1, "generation": 9})
	check(not _build(layout, duplicate, "line").ok and is_same(saved, layout.slots()), "duplicate entity index")
	check(not _build(layout, [{"index":0,"generation":0}], "line").ok, "invalid generation")
	var nested := func(points: PackedVector3Array):
		var inner := _build(layout, [], "column")
		check(not inner.ok and inner.error.code == "InvalidState" and is_same(saved, layout.slots()), "no nested publication")
		return R.ok(points)
	check(layout.rebuild(roster, "line", OPEN, 0, 1, INF, nested).ok, "authoritative projection returned normally")
	check(saved.is_read_only() and saved[0].is_read_only() and saved[0].member.is_read_only(), "immutable view")
	roster[0].generation = 2
	origin = OPEN
	var rotated := layout.rebuild(roster, "line", OPEN, PI / 2, 1, INF, _on_nav)
	check(rotated.ok and saved[0].member.generation == 1 and rotated.value.slots[0].member.generation == 2, "generation reuse and owning copy")
	if rotated.ok:
		var first: Dictionary = rotated.value.slots[0]
		check(first.position.distance_to(OPEN + first.local_offset.rotated(Vector3.UP, PI / 2)) < 0.01, "Y-up facing rotation")
	var depleted := _build(layout, roster.slice(11), "line")
	check(depleted.ok and depleted.value.slots.size() == 4 and depleted.value.slots[-1].slot_id == 3, "substantial losses compact the footprint")
	var empty := _build(layout, [], "line")
	check(empty.ok and empty.value.slots.is_empty(), "clear roster")
	print("P2-FORM-ROLLBACK exercised")

func run() -> void:
	adapter = Adapter.new(root, true)
	var token := adapter.open_scope(SCOPE)
	if not token.ok or not adapter.load_scene(FLOOR, token.value).ok:
		printerr("FAIL formation nav scene")
		quit(1)
		return
	var synced := false
	for i in 120:
		await physics_frame
		var result := adapter.sync_navigation(SCOPE)
		if result.ok and result.value.status == "applied":
			nav_revision = result.value.applied_revision
			var probe := adapter.query_path_batch([{"from":_mm(OPEN), "to":_mm(OPEN + Vector3.RIGHT)}], nav_revision, SCOPE)
			if probe.ok and probe.value[0].reachable:
				synced = true
				break
	if not synced:
		printerr("FAIL formation nav sync")
		adapter.release_scope(SCOPE)
		quit(1)
		return
	_exercise(500)
	_exercise(1000)
	_failures_and_rotation()
	check(adapter.release_scope(SCOPE).released == 1, "nav scope released")
	print("T-FORM-02-LAYOUT ", "PASS" if failures == 0 else "FAIL")
	print("P2-FORM-001 ", "PASS" if failures == 0 else "FAIL", " failures=", failures, " reachable_slots=", projected, " seed=241124")
	quit(0 if failures == 0 else 1)
