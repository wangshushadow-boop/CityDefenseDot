extends SceneTree

var NAV := NavigationServer3D
const PEOPLE := 256
const START := Vector3(-400, 0, 0)
const EXIT := Vector3(1.6, 0, 0)
const GOAL := Vector3(24, 2.5, 0)
const BODY_GAP := 0.65
const SPEED := 3.0
const DT := 1.0 / 30.0
const QUERY_BATCH := 32

var nav_map: RID
var gate: RID
var regions: Array[RID] = []
var meshes: Array[NavigationMesh] = []
var positions := PackedVector3Array()
var arrived := 0
var ticks := 0
var waiting := 0
var peak_waiting := 0
var crossings := 0
var max_step := 0.0
var min_headway := INF
var peak_y := 0.0
var cached: Dictionary = {}
var stale_rejections := 0
var query_us: Array[int] = []
var engine_queries := 0
var transitions: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


# Each row specifies x, height and half-width of a walkable cross section.
# Polygon strips share indices; the gate spans two separate region islands.
func add_strip(rows: Array[Vector3]) -> void:
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	for row in rows:
		vertices.append(Vector3(row.x, row.y, -row.z))
		vertices.append(Vector3(row.x, row.y, row.z))
	mesh.vertices = vertices
	for i in range(rows.size() - 1):
		var k := 2 * i
		mesh.add_polygon(PackedInt32Array([k, k + 1, k + 3, k + 2]))
	var region := NAV.region_create()
	regions.append(region)
	meshes.append(mesh)
	NAV.region_set_navigation_mesh(region, mesh)
	NAV.region_set_map(region, nav_map)


func path_query(origin: Vector3) -> PackedVector3Array:
	var start_us := Time.get_ticks_usec()
	# Return portal centers, including the changes of slope on the ramp.
	var path := NAV.map_get_path(nav_map, origin, GOAL, false)
	query_us.append(Time.get_ticks_usec() - start_us)
	engine_queries += 1
	return path


func reaches_goal(path: PackedVector3Array) -> bool:
	return not path.is_empty() and path[-1].distance_to(GOAL) < 0.02


func install(candidate: Dictionary) -> bool:
	if candidate.revision != NAV.map_get_iteration_id(nav_map):
		stale_rejections += 1
		return false
	cached = candidate
	return true


func set_gate(open: bool) -> bool:
	var before := NAV.map_get_iteration_id(nav_map)
	NAV.link_set_enabled(gate, open)
	var frames := 0
	while NAV.map_get_iteration_id(nav_map) == before and frames < 120:
		await physics_frame
		frames += 1
	var revision := NAV.map_get_iteration_id(nav_map)
	check(revision != before, "map failed to publish a new iteration")
	if not cached.is_empty():
		check(not install(cached), "old corridor installed after gate changed")
	var route := path_query(START)
	var outside := path_query(EXIT)
	check(reaches_goal(route) == open, "gate reachability mismatch")
	check(not route.is_empty() and (open or absf(route[-1].x) < 0.03), "wrong closed gate frontier")
	check(reaches_goal(outside), "far side disconnected from goal")
	check(install({"revision": revision, "route": route, "outside": outside}), "fresh corridor rejected")
	# Time additional independent engine queries at several offsets in the courtyard.
	# They are diagnostic probes; crowd movement uses the two shared paths above.
	for i in QUERY_BATCH:
		var probe := path_query(Vector3(-10.0 - i, 0.0, (i % 3 - 1) * 0.25))
		check(reaches_goal(probe) == open, "independent probe disagreed with gate")
	transitions.append({"open": open, "revision": revision, "sync_physics_frames": frames,
		"map_region_count": NAV.map_get_regions(nav_map).size(),
		"projected_goal": str(NAV.map_get_closest_point(nav_map, GOAL)),
		"approach_end": str(route[-1]) if not route.is_empty() else "empty",
		"route_points": route.size(), "outside_points": outside.size()})
	return failures.is_empty()


func step_crowd() -> void:
	var ahead_x := INF
	waiting = 0
	for i in range(arrived, PEOPLE):
		var old := positions[i]
		# Agents past the near lip are committed to the short crossing. On closure
		# they finish to EXIT and follow the newly queried path on the far island.
		var path: PackedVector3Array = cached.outside if old.x > 0.001 else cached.route
		var next := old
		for target in path:
			if target.x > old.x + 0.00001:
				next = old.move_toward(target, SPEED * DT)
				break
		var headroom := maxf(0.0, ahead_x - old.x - BODY_GAP)
		if next.x - old.x > headroom:
			next = old.lerp(next, headroom / (next.x - old.x))
		positions[i] = next
		var distance := old.distance_to(next)
		max_step = maxf(max_step, distance)
		peak_y = maxf(peak_y, next.y)
		if old.x <= 0.001 and next.x > 0.001:
			crossings += 1
		if next.distance_to(GOAL) < 0.0001:
			arrived += 1
		else:
			min_headway = minf(min_headway, ahead_x - next.x)
			ahead_x = next.x
			if distance < 0.0001:
				waiting += 1
	ticks += 1
	peak_waiting = maxi(peak_waiting, waiting)


func record_phase(label: String) -> void:
	phases.append({"phase": label, "tick": ticks, "arrived": arrived,
		"waiting": waiting, "crossings": crossings})


func run() -> void:
	var started := Time.get_ticks_usec()
	nav_map = NAV.map_create()
	NAV.map_set_active(nav_map, true)
	NAV.map_set_link_connection_radius(nav_map, 0.28)
	add_strip([Vector3(-410, 0, 3), Vector3(-5, 0, 3),
		Vector3(-2, 0, 0.5), Vector3(0, 0, 0.5)])
	add_strip([Vector3(1.6, 0, 0.5), Vector3(8, 0, 0.5),
		Vector3(14, 2.5, 0.5), Vector3(18, 2.5, 3), Vector3(26, 2.5, 3)])
	gate = NAV.link_create()
	NAV.link_set_start_position(gate, Vector3.ZERO)
	NAV.link_set_end_position(gate, EXIT)
	NAV.link_set_map(gate, nav_map)
	for i in PEOPLE:
		positions.append(Vector3(-1.0 - 1.45 * i, 0.0, 0.0))
	# The first map iteration may publish before the region mesh workers finish.
	var startup_frames := 0
	var ready_map := false
	while startup_frames < 120:
		await physics_frame
		startup_frames += 1
		if NAV.map_get_iteration_id(nav_map) > 0 and reaches_goal(NAV.map_get_path(nav_map, START, GOAL, false)):
			ready_map = true
			break
	check(ready_map, "initial open map never connected both islands")
	if failures.is_empty() and await set_gate(false):
		for i in 1250:
			step_crowd()
		record_phase("initially_closed")
		check(waiting >= PEOPLE / 2 and crossings == 0, "closed gate did not build a stationary queue")
	if failures.is_empty() and await set_gate(true):
		for i in 3000:
			step_crowd()
			if arrived >= 32:
				break
		record_phase("open_during_traffic")
		check(arrived >= 32 and crossings < PEOPLE, "crowd did not enter and traverse live bottleneck")
	var crossing_before_close := crossings
	if failures.is_empty() and await set_gate(false):
		for i in 350:
			step_crowd()
		record_phase("reclosed_during_traffic")
		check(crossings == crossing_before_close and waiting > 0, "closed gate admitted new traffic")
	if failures.is_empty() and await set_gate(true):
		for i in 5000:
			step_crowd()
			if arrived == PEOPLE:
				break
		record_phase("reopened_and_drained")
		check(arrived == PEOPLE and crossings == PEOPLE and waiting == 0, "crowd failed to drain")
	check(stale_rejections == 3, "not all stale corridors were rejected")
	check(min_headway >= BODY_GAP - 0.0001, "queue agents penetrated the lead agent")
	check(max_step <= SPEED * DT + 0.0001 and peak_y >= GOAL.y - 0.01, "invalid displacement or ramp bypass")
	query_us.sort()
	var result := {"passed": failures.is_empty(), "failures": failures,
		"engine": Engine.get_version_info().string, "people": PEOPLE, "physics_hz_simulated": 30,
		"transitions": transitions, "phases": phases, "stale_rejections": stale_rejections,
		"peak_waiting": peak_waiting, "duration_simulated_s": ticks * DT,
		"wall_ms": (Time.get_ticks_usec() - started) / 1000.0,
		"startup_frames": startup_frames, "max_step_m": max_step,
		"min_headway_m": min_headway if is_finite(min_headway) else -1,
		"highest_agent_y_m": peak_y, "crowd_route_queries": 2 * transitions.size(),
		"measured_queries": engine_queries,
		"query_p95_us": query_us[ceili(0.95 * query_us.size()) - 1] if query_us else 0,
		"query_max_us": query_us.max() if query_us else 0}
	print("NAV_RESULT ", JSON.stringify(result))
	NAV.free_rid(gate)
	for region in regions:
		NAV.free_rid(region)
	NAV.free_rid(nav_map)
	quit(0 if failures.is_empty() else 1)
