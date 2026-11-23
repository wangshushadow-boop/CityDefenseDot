class_name FieldTerrain extends RefCounted
## 模拟和画面共用高度、河床、浅滩、石群及树干布局，坐标使用世界 X/Z。
const LIMIT := Vector2(56, 28)
const FORD_X := 18.0
const WATER_Y := -0.16
# x/z/半径，避开主路、两处渡口和占领区。
const ROCKS := [Vector3(-26, -8, 2.3), Vector3(25, -8, 2.6), Vector3(-9, 20, 2.0),
	Vector3(10, 21, 2.6), Vector3(-29, 23, 3.0), Vector3(30, 23, 2.5),
	Vector3(-5, -25, 1.8), Vector3(7, -25, 2.1)]
var trees: PackedVector2Array
var trunks := {}

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4137
	for x in range(-86, 88, 4):
		for z in range(-55, 58, 4):
			var p := Vector2(x + rng.randf_range(-1.1, 1.1), z + rng.randf_range(-1.1, 1.1))
			var outer := absf(p.y) > LIMIT.y + 2 or absf(p.x) > LIMIT.x + 6
			var forest := absf(p.x) < 31 and p.y > 17 and p.distance_to(Vector2(0, 16)) > 3.6
			if not outer and not forest:
				continue
			if rng.randf() > 0.58 or absf(p.y - river_z(p.x)) < 3.8 or in_rock(p):
				continue
			trees.append(p)
			var cell := Vector2i((p / 4).floor())
			if not trunks.has(cell):
				trunks[cell] = []
			trunks[cell].append(p)

static func river_z(x: float) -> float:
	return -14.0 + 2.8 * cos(x * 0.085)

static func ford(x: float) -> float:
	return 1.0 - smoothstep(2.3, 3.4, absf(absf(x) - FORD_X))

static func height(p: Vector2) -> float:
	var bank := absf(p.y - river_z(p.x))
	var bed := lerpf(-1.4, -0.19, ford(p.x)) * (1.0 - smoothstep(1.4, 3.8, bank))
	# 可玩区边缘的山麓延伸到远景山脊，城内和主路保留平地。
	var ridge := smoothstep(19.0, 44.0, absf(p.y))
	var peaks := 7.0 + 5.0 * sin(p.x * 0.11 + p.y * 0.055) + 2.8 * cos(p.x * 0.23 - p.y * 0.13)
	var east_west := smoothstep(57.0, 82.0, absf(p.x))
	return bed + ridge * peaks + east_west * (10.0 + 6.0 * sin(p.y * 0.15 + p.x * 0.055))

static func in_rock(p: Vector2, clearance: float = 0.0) -> bool:
	for rock: Vector3 in ROCKS:
		if p.distance_squared_to(Vector2(rock.x, rock.y)) < (rock.z + clearance) ** 2:
			return true
	return false

func blocked(p: Vector2, clearance: float = 0.0) -> bool:
	if (absf(p.y - river_z(p.x)) < 1.9 + clearance and ford(p.x) < 0.75) or in_rock(p, clearance):
		return true
	var cell := Vector2i((p / 4).floor())
	for x in range(cell.x - 1, cell.x + 2):
		for z in range(cell.y - 1, cell.y + 2):
			var key := Vector2i(x, z)
			for tree: Vector2 in trunks.get(key, []):
				if p.distance_squared_to(tree) < (0.47 + clearance) ** 2:
					return true
	return false
