extends RefCounted
## One MOV owner per Mission. Formation slots, headings and positions are in metres.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const Queue = preload("res://mission/movement/path_queue.gd")
const CELL := 1.2
const NEIGHBOURS := 48
const QUERIES_PER_TICK := 8

class Body:
	var generation: int
	var profile: String
	var position: Vector3
	var velocity := Vector3.ZERO
	var heading: Vector3
	var radius: float
	var group := ""
	var offset := Vector3.ZERO
	var revision := -1
	var cursor := 1
	var arrived := false
	var blocked := ""
	var wait := 0.0
	var path := PackedVector3Array()
	var ticket := {}
	var access_version := -1
	var join_index := 0
	var passages: Array = []
	var courtesy := Vector3.ZERO
	var courtesy_time := 0.0

class Corridor:
	var origin: Vector3
	var goal: Vector3
	var profile: String
	var ticket := {}
	var points := PackedVector3Array()
	var reachable := false
	var version := -1

var _engine: RefCounted
var _scope: String
var _queue: RefCounted
var _access: RefCounted
var _bodies := {}
var _retired := {}
var _routes := {}
var _zones: Array = []
var _cells := {}
var _tick := -1
var _revision := -1
var _serial := 0
var _checks := 0
var _yields := 0
var _blocker: Body

func _init(engine: RefCounted, mission_id: String) -> void:
	_engine = engine
	_scope = mission_id
	_queue = Queue.new(engine, mission_id)
	_access = Queue.new(engine, mission_id)

static func _valid_handle(handle: Dictionary) -> bool:
	return handle.size() == 2 and V.integer(handle.get("index"), 0, V.MAX_U32) and V.integer(handle.get("generation"), 1, V.MAX_U32)

func _body(handle: Dictionary) -> Body:
	if not _valid_handle(handle):
		return null
	var b: Body = _bodies.get(handle.index)
	return b if b != null and b.generation == handle.generation else null

static func _point_ok(p: Vector3) -> bool:
	return p.is_finite() and maxf(absf(p.x), maxf(absf(p.y),absf(p.z))) <= 2147483.0

static func _mm(p: Vector3) -> Array:
	return [roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000)]

func spawn(handle: Dictionary, position: Vector3, profile: String = "foot", heading: Vector3 = Vector3.FORWARD) -> Dictionary:
	var flat := Vector3(heading.x, 0, heading.z)
	if not _valid_handle(handle) or not _point_ok(position) or profile not in ["foot","mounted"] or not heading.is_finite() or flat.is_zero_approx():
		return R.fail("InvalidArgument", "movement_spawn")
	if _bodies.has(handle.index) or handle.generation <= _retired.get(handle.index, 0):
		return R.fail("Conflict", "movement_handle")
	var b := Body.new()
	b.generation = handle.generation
	b.profile = profile
	b.radius = 0.47 if profile == "mounted" else 0.28
	b.position = position
	b.heading = flat.normalized()
	_bodies[handle.index] = b
	return R.ok()

func despawn(handle: Dictionary) -> Dictionary:
	if _body(handle) == null:
		return R.fail("NotFound", "movement_handle")
	_retired[handle.index] = handle.generation
	_bodies.erase(handle.index)
	return R.ok()

## Authored bounds of a bottleneck. The short horizontal axis is its width.
func set_terrain(zones: Array) -> Dictionary:
	for zone in zones:
		if typeof(zone) != TYPE_DICTIONARY or typeof(zone.get("bounds")) != TYPE_AABB or typeof(zone.get("profiles")) != TYPE_ARRAY:
			return R.fail("InvalidArgument", "terrain")
		var bounds: AABB = zone.bounds
		if not _point_ok(bounds.position) or not _point_ok(bounds.end) or not bounds.has_volume():
			return R.fail("InvalidArgument", "terrain_bounds")
		for profile in zone.profiles:
			if profile not in ["foot", "mounted"]:
				return R.fail("InvalidArgument", "terrain_profile")
	_zones = zones.duplicate(true)
	for b: Body in _bodies.values():
		b.revision = -1
		b.access_version = -1
	return R.ok()

func set_corridor(group: String, origin: Vector3, goal: Vector3, profile: String = "foot") -> Dictionary:
	if group.is_empty() or not _point_ok(origin) or not _point_ok(goal) or profile not in ["foot","mounted"]:
		return R.fail("InvalidArgument", "corridor")
	var old: Corridor = _routes.get(group)
	if old != null:
		if old.profile != profile:
			return R.fail("Conflict", "corridor_profile")
		if old.origin.is_equal_approx(origin) and old.goal.is_equal_approx(goal):
			return R.ok()
	var route := Corridor.new()
	route.origin = origin
	route.goal = goal
	route.profile = profile
	_routes[group] = route
	return R.ok()

func assign(handle: Dictionary, group: String, slot_offset: Vector3 = Vector3.ZERO) -> Dictionary:
	var b := _body(handle)
	var route: Corridor = _routes.get(group)
	if b == null or route == null:
		return R.fail("NotFound", "movement_assignment")
	if b.profile != route.profile or not _point_ok(slot_offset) or not is_zero_approx(slot_offset.y):
		return R.fail("InvalidArgument", "movement_slot")
	if b.group != group or b.offset != slot_offset:
		b.group = group
		b.offset = slot_offset
		b.revision = -1
		b.access_version = -1
		b.arrived = false
	return R.ok()

func view(handle: Dictionary) -> Dictionary:
	var b := _body(handle)
	if b == null:
		return R.fail("NotFound", "movement_handle")
	return R.ok({"position":b.position, "velocity":b.velocity, "heading":b.heading,
		"profile":b.profile, "arrived":b.arrived, "blocked":b.blocked})

func _remaining_queries(tick: int) -> int:
	return QUERIES_PER_TICK - _queue.attempts_at(tick) - _access.attempts_at(tick)

func _prepare(tick: int) -> Dictionary:
	var sync: Dictionary = _engine.sync_navigation(_scope)
	if not sync.ok:
		return sync
	if sync.value.status != "applied":
		return R.fail("Unavailable", "navigation_sync")
	var revision: int = sync.value.applied_revision
	for route: Corridor in _routes.values():
		if _revision != revision:
			route.ticket = {}
			route.version = -1
		if route.version >= 0 or not route.ticket.is_empty():
			continue
		var q: Dictionary = _queue.request_path(_mm(route.origin), _mm(route.goal), route.profile)
		if q.ok:
			route.ticket = q.value
		elif q.error.code != "Unavailable":
			return q
	_revision = revision
	var spent: Dictionary = _queue.process_budget(tick, _remaining_queries(tick))
	if not spent.ok:
		return spent
	for route: Corridor in _routes.values():
		if route.version >= 0 or route.ticket.is_empty():
			continue
		var result: Dictionary = _queue.poll_path(route.ticket)
		if not result.ok:
			if result.error.code == "NotFound":
				route.ticket = {}
			elif result.error.code != "Unavailable":
				return result
			continue
		route.points.clear()
		for point in result.value.points:
			route.points.append(Vector3(point[0],point[1],point[2]) * 0.001)
		route.reachable = result.value.reachable and not route.points.is_empty()
		_serial += 1
		route.version = _serial
	return spent

# Admission to a shared corridor must start on the member's own island. Solve
# only at assignment/revision changes, with the remainder of the same tick budget.
func _members(tick: int, remaining: int) -> Dictionary:
	var pending: Array[Body] = []
	var full := false
	for b: Body in _bodies.values():
		var route: Corridor = _routes.get(b.group)
		if route == null or route.version < 0 or not route.reachable or b.revision == route.version:
			continue
		if b.access_version != route.version:
			b.ticket = {}
			b.access_version = route.version
			var nearest := INF
			b.join_index = 0
			for i in range(1, route.points.size()):
				var a := route.points[i-1]
				var end := route.points[i]
				var projection := Geometry3D.get_closest_point_to_segment(b.position,a,end) if a != end else end
				var dist := b.position.distance_squared_to(projection)
				if dist < nearest:
					nearest = dist
					b.join_index = i
			# A member already on this exact navigation segment can use its suffix.
			if nearest < 0.000001 and (b.join_index+1 < route.points.size() or b.offset.is_zero_approx()):
				_set_path(b,route,PackedVector3Array())
				continue
		if b.ticket.is_empty():
			if full:
				continue
			var join := route.points[b.join_index]
			if b.join_index+1 == route.points.size():
				join += b.offset
			var request: Dictionary = _access.request_path(_mm(b.position),_mm(join),b.profile)
			if not request.ok:
				if request.error.code == "Unavailable":
					full = true
					continue
				return request
			b.ticket = request.value
		pending.append(b)
	var spent: Dictionary = _access.process_budget(tick,remaining)
	if not spent.ok:
		return spent
	for b in pending:
		var result: Dictionary = _access.poll_path(b.ticket)
		if not result.ok:
			if result.error.code == "NotFound":
				b.ticket = {}
			elif result.error.code != "Unavailable":
				return result
			continue
		var route: Corridor = _routes[b.group]
		var points: Array = result.value.points
		b.path.clear()
		b.revision = route.version
		if not result.value.reachable or points.is_empty():
			continue
		var first: Array = points[0]
		if b.position.distance_to(Vector3(first[0],first[1],first[2])*0.001) > 0.015:
			continue
		var access_points := PackedVector3Array()
		for index in range(1,points.size()-1):
			var raw: Array = points[index]
			access_points.append(Vector3(raw[0],raw[1],raw[2])*0.001)
		_set_path(b,route,access_points)
	return spent

func _set_path(b: Body, route: Corridor, approach: PackedVector3Array) -> void:
	b.path = approach
	for i in range(b.join_index,route.points.size()):
		var point := route.points[i]
		if i+1 == route.points.size():
			point += b.offset
		b.path.append(point)
	b.revision = route.version
	b.cursor = 0
	b.passages.clear()
	var start := b.position
	for zone in _zones:
		var bounds: AABB = zone.bounds
		var axis := 0 if bounds.size.x >= bounds.size.z else 2
		var side := 2-axis
		for point in b.path:
			if bounds.intersects_segment(start,point) != null or bounds.has_point(start):
				var sign_travel := signf(point[axis]-start[axis])
				if sign_travel == 0.0:
					start = point
					continue
				var two_lanes := bounds.size[side] >= b.radius*4.2
				var offset := sign_travel * bounds.size[side]*0.25 if two_lanes else 0.0
				b.passages.append({"bounds":bounds,"axis":axis,"side":side,"lane":bounds.get_center()[side]+offset,"direction":sign_travel,"two":two_lanes})
				break
			start = point
		start = b.position

static func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.z / CELL))

func _put(cell: Vector2i, b: Body) -> void:
	if not _cells.has(cell):
		_cells[cell] = []
	_cells[cell].append(b)

func _clear_step(b: Body, candidate: Vector3) -> bool:
	_blocker = null
	for zone in _zones:
		var bounds: AABB = zone.bounds
		if not zone.profiles.has(b.profile) and (bounds.has_point(b.position) or bounds.intersects_segment(b.position, candidate) != null):
			return false
		if bounds.has_point(candidate):
			var x_long := bounds.size.x >= bounds.size.z
			var side := candidate.z if x_long else candidate.x
			var lo := bounds.position.z if x_long else bounds.position.x
			var width := bounds.size.z if x_long else bounds.size.x
			if side < lo + b.radius or side > lo + width - b.radius:
				return false
	for passage in b.passages:
		var box: AABB = passage.bounds
		var axis: int = passage.axis
		var side: int = passage.side
		if candidate[axis] >= box.position[axis] and candidate[axis] <= box.end[axis] and candidate.y >= box.position.y and candidate.y <= box.end.y:
			if candidate[side] < box.position[side]+b.radius or candidate[side] > box.end[side]-b.radius:
				return false
			if passage.two and absf(candidate[side]-passage.lane) > box.size[side]*0.25-b.radius:
				return false
		elif passage.two and candidate[axis] > box.position[axis]-3.0 and candidate[axis] < box.end[axis]+3.0:
			# Keep the exit clear while the opposite queue aligns at the entrance.
			var center := box.get_center()[side]
			var facing: float = passage.direction
			var previous_side := (b.position[side]-center)*facing
			var proposed_side := (candidate[side]-center)*facing
			if proposed_side < b.radius and proposed_side <= previous_side:
				return false
	var reach := Vector3(b.radius+0.47,0,b.radius+0.47)
	var first := _cell(b.position.min(candidate)-reach)
	var last := _cell(b.position.max(candidate)+reach)
	var motion := candidate-b.position
	var length_sq := motion.length_squared()
	var inspected := 0
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			var group: Variant = _cells.get(Vector2i(x,z))
			if group == null:
				continue
			for other: Body in group:
				if other == b:
					continue
				inspected += 1
				_checks += 1
				var threshold := b.radius + other.radius
				var separation := b.position-other.position
				var approaching := -separation.dot(motion)
				if approaching > 0.0 and (separation + motion*minf(approaching/length_sq,1.0)).length_squared() < threshold*threshold:
					_blocker = other
					return false
				if inspected >= NEIGHBOURS:
					# Dense cells yield rather than advance into an unchecked neighbour.
					return false
	return true

func _waypoint(b: Body, p: Vector3, final: bool) -> Vector3:
	var target := p
	for passage in b.passages:
		var bounds: AABB = passage.bounds
		var axis: int = passage.axis
		var side: int = passage.side
		if not final and p[axis] >= bounds.position[axis]-3.5 and p[axis] <= bounds.end[axis]+3.5:
			var apron := maxf(0,maxf(bounds.position[axis]-p[axis],p[axis]-bounds.end[axis]))
			target[side] = passage.lane + passage.direction * minf(1.0,apron*0.36)
	for zone in _zones:
		var bounds: AABB = zone.bounds
		if bounds.grow(0.01).has_point(p):
			if bounds.size.x >= bounds.size.z:
				target.z = clampf(target.z, bounds.position.z+b.radius, bounds.end.z-b.radius)
				target.x = p.x
			else:
				target.x = clampf(target.x, bounds.position.x+b.radius, bounds.end.x-b.radius)
				target.z = p.z
	return target

func _move(b: Body, route: Corridor, dt: float) -> void:
	b.blocked = ""
	if route == null or route.version < 0 or not route.reachable or route.version != b.revision or b.path.is_empty():
		b.velocity = Vector3.ZERO
		b.arrived = false
		b.blocked = "no_route"
		return
	b.arrived = false
	var target := _waypoint(b,b.path[b.cursor],b.cursor+1 == b.path.size())
	while b.position.distance_to(target) < 0.36 and b.cursor+1 < b.path.size():
		b.cursor += 1
		target = _waypoint(b,b.path[b.cursor],b.cursor+1 == b.path.size())
	var delta := target - b.position
	if b.courtesy_time > 0.0:
		b.courtesy_time -= dt
		delta = b.courtesy
		b.arrived = false
	var distance := delta.length()
	if distance < 0.06 and b.cursor+1 == b.path.size():
		b.arrived = true
		b.velocity = Vector3.ZERO
		return
	var direction := delta.normalized()
	var flat := Vector3(direction.x,0,direction.z).normalized()
	var speed := 3.4
	if b.profile == "mounted":
		var previous_speed := b.velocity.length()
		var angle := b.heading.signed_angle_to(flat, Vector3.UP) if not flat.is_zero_approx() else 0.0
		var limit := 3.0 * dt / (1.0 + 0.22 * previous_speed)
		b.heading = b.heading.rotated(Vector3.UP,clampf(angle,-limit,limit)).normalized()
		var desired_speed := minf(9.0, sqrt(2.0 * 8.0 * distance))
		desired_speed *= maxf(0.0, b.heading.dot(flat))
		speed = move_toward(previous_speed, desired_speed, (8.0 if previous_speed > desired_speed else 4.0) * dt)
		direction = (b.heading * Vector2(direction.x,direction.z).length() + Vector3.UP * direction.y).normalized()
	elif not flat.is_zero_approx():
		b.heading = flat
	var travel := minf(distance, speed*dt)
	var candidate := b.position + direction * travel
	for passage in b.passages:
		var box: AABB = passage.bounds
		var axis: int = passage.axis
		var side: int = passage.side
		var entered := candidate[axis] >= box.position[axis] and candidate[axis] <= box.end[axis]
		var outside := b.position[axis] < box.position[axis] or b.position[axis] > box.end[axis]
		if outside and entered and absf(candidate[side]-passage.lane) > 0.03:
			candidate = b.position
			candidate[side] = move_toward(candidate[side],passage.lane,travel)
	if not _clear_step(b,candidate):
		b.wait += dt
		b.blocked = "yield"
		_yields += 1
		candidate = b.position
		var obstruction := _blocker
		if b.profile == "foot" and b.wait > 0.20:
			var right := direction.cross(Vector3.UP).normalized()
			if obstruction != null and obstruction.profile == "foot" and obstruction.courtesy_time <= 0.0 and (b.cursor+1 == b.path.size() or b.heading.dot(obstruction.heading) < -0.5):
				# Settled ranks also yield. The recipient moves on its own bounded step.
				var away := obstruction.position-b.position
				var lateral := right if away.dot(right) >= 0.0 else -right
				obstruction.courtesy = (lateral + direction*0.2).normalized()
				obstruction.courtesy_time = 0.38
			for sign_value: float in [1.0,-1.0]:
				var aside := b.position + (right*sign_value + direction*0.2).normalized()*travel*0.5
				if _clear_step(b,aside):
					candidate = aside
					break
	else:
		b.wait = 0.0
	var old_cell := _cell(b.position)
	b.velocity = (candidate-b.position) / dt
	b.position = candidate
	var new_cell := _cell(b.position)
	if old_cell != new_cell:
		_cells[old_cell].erase(b)
		_put(new_cell,b)

func step(tick: int, dt: float) -> Dictionary:
	if _engine == null or tick < 0 or not is_finite(dt) or dt <= 0 or dt > 0.1:
		return R.fail("InvalidArgument", "movement_step")
	if tick <= _tick:
		return R.fail("StaleVersion", "tick")
	var ready := _prepare(tick)
	if not ready.ok:
		return ready
	var joins := _members(tick, _remaining_queries(tick))
	if not joins.ok:
		return joins
	_tick = tick
	_checks = 0
	_yields = 0
	_cells.clear()
	for b: Body in _bodies.values():
		_put(_cell(b.position),b)
	for b: Body in _bodies.values():
		_move(b, _routes.get(b.group), dt)
	var shared: int = _queue.attempts_at(tick)
	var members: int = _access.attempts_at(tick)
	return R.ok({"queried":shared,"member_queried":members,
		"total_queried":shared+members,"nav_revision":_revision,
		"neighbour_checks":_checks,"yielding":_yields})
