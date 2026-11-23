class_name BattleSpace extends RefCounted
## 灰盒地图在 X/Z 平面模拟。墙、门洞、视线和移动共享一份几何数据。
const LIMIT := Vector2(28, 14)
const GRAIN := Vector2(0, -5)
const WOOD := Vector2(0, 8)
const SIDE_Z := 8.0
const HALF_GAP := 2.0
const CELL := 5.0
var forts: Array[BattleFort] = [BattleFort.new(0), BattleFort.new(1)]
var buckets := {}

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
	if not clear_line(from, next):
		return false
	unit.position = next
	return true
