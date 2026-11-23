class_name BattleSpace extends RefCounted
## 河谷战场在 X/Z 平面计算移动，门洞、障碍和视线共用同一份地理数据。
const Terrain := preload("res://battle/terrain.gd")
const LIMIT := Terrain.LIMIT
const GRAIN := Vector2(0, -21)
const WOOD := Vector2(0, 16)
const SIDE_Z := 12.0
const HALF_GAP := 2.0
const CELL := 5.0
var forts: Array[BattleFort] = [BattleFort.new(0), BattleFort.new(1)]
var buckets := {}
var terrain := Terrain.new()
var paths := AStarGrid2D.new()

func _init() -> void:
	# 半米网格为斜向跨格预留树干间隙，避免角色在两格之间擦入障碍。
	paths.cell_size = Vector2(0.5, 0.5)
	var extent := Vector2i(LIMIT / paths.cell_size)
	paths.region = Rect2i(-extent, extent * 2 + Vector2i.ONE)
	paths.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	paths.update()
	for x in range(-extent.x, extent.x + 1):
		for z in range(-extent.y, extent.y + 1):
			var cell := Vector2i(x, z)
			paths.set_point_solid(cell, terrain.blocked(Vector2(cell) * paths.cell_size, 0.24))

func rebuild(teams: Array[BattleTeam]) -> void:
	buckets.clear()
	for team in teams:
		for unit in team.units:
			if unit.alive():
				var key := Vector2i((unit.position / CELL).floor())
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(unit)

func near(at: Vector2, radius: float, side: int) -> Array[BattleAgent]:
	var found: Array[BattleAgent] = []
	var lo := Vector2i(((at - Vector2.ONE * radius) / CELL).floor())
	var hi := Vector2i(((at + Vector2.ONE * radius) / CELL).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for unit: BattleAgent in buckets.get(Vector2i(x, y), []):
				if unit.side == side and unit.alive() and unit.position.distance_squared_to(at) <= radius * radius:
					found.append(unit)
	return found

func clear_line(a: Vector2, b: Vector2) -> bool:
	for rock: Vector3 in Terrain.ROCKS:
		var center := Vector2(rock.x, rock.y)
		if a != b and center.distance_squared_to(Geometry2D.get_closest_point_to_segment(center, a, b)) < rock.z * rock.z:
			return false
	for fort in forts:
		if (a.x < fort.gate.x) == (b.x < fort.gate.x):
			continue
		var z := lerpf(a.y, b.y, (fort.gate.x - a.x) / (b.x - a.x))
		if fort.front_open() and absf(z) < HALF_GAP:
			continue
		if fort.side_open and absf(z - SIDE_Z) < HALF_GAP:
			continue
		return false
	return true

func move(unit: BattleAgent, goal: Vector2, dt: float, route := true) -> bool:
	var from := unit.position
	var dest := goal.clamp(-LIMIT, LIMIT)
	if route:
		# 先处理最近的一堵墙，双方从各自城内出发时会依次经过两城。
		var walls := forts.duplicate()
		if dest.x < from.x:
			walls.reverse()
		for fort: BattleFort in walls:
			if (from.x < fort.gate.x) == (dest.x < fort.gate.x):
				continue
			var door := fort.gate
			if fort.side_open and (not fort.front_open() or absf(from.y - SIDE_Z) < absf(from.y)):
				door.y = SIDE_Z
			var ahead := signf(dest.x - from.x)
			# 在同侧对齐门洞，再穿过墙线，避免斜切墙体。
			if absf(from.y - door.y) > HALF_GAP * 0.55:
				dest = door - Vector2(ahead * 1.4, 0)
			else:
				dest = door + Vector2(ahead * 1.4, 0)
			break
	var next := from.move_toward(dest, unit.spec.speed * dt)
	if route and not unit.detour.is_empty() and unit.detour_goal.distance_to(dest) > 2:
		unit.detour.clear()
	if route and (not unit.detour.is_empty() or terrain.blocked(from.move_toward(dest, 1.5)) or terrain.blocked(next)):
		# 门楼仍由上面的门洞路点处理，局部网格只规划到当前一侧的路点。
		if unit.detour.is_empty():
			var start := Vector2i((from / paths.cell_size).round())
			var end := Vector2i((dest / paths.cell_size).round())
			if paths.is_point_solid(start):
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var candidate: Vector2i = start + offset
					if paths.is_in_boundsv(candidate) and not paths.is_point_solid(candidate):
						start = candidate
						break
			unit.detour = paths.get_point_path(start, end, true)
			unit.detour_goal = dest
		while not unit.detour.is_empty() and from.distance_to(unit.detour[0]) < 0.18:
			unit.detour.remove_at(0)
		if not unit.detour.is_empty():
			next = from.move_toward(unit.detour[0], unit.spec.speed * dt)
	if terrain.blocked(next):
		return false
	if not clear_line(from, next):
		return false
	unit.position = next
	return true
