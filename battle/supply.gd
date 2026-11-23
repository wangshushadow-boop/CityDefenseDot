class_name BattleSupply extends RefCounted
## 据点决定下一批产出归属，库存按阵营独立保存。两个阵营同场时占领暂停。
class Point:
	var at: Vector2
	var title: String
	var owner: int
	var contender := -1
	var progress := 0.0
	var contested := false
	func _init(label: String, pos: Vector2, side: int = -1) -> void:
		title = label
		at = pos
		owner = side
	func occupy(blue: bool, red: bool, dt: float, duration: float) -> void:
		contested = blue and red
		if contested:
			return
		var side := 0 if blue else (1 if red else -1)
		if side < 0 or side == owner:
			contender = -1
			progress = 0
			return
		if contender != side:
			contender = side
			progress = 0
		progress += dt
		if progress >= duration:
			owner = side
			contender = -1
			progress = 0

var points: Array[Point] = []
var food: Array[int]
var wood: Array[int]
var clock := 0.0

func _init(setup: BattleSetup, field: BattleSpace) -> void:
	food = setup.food.duplicate()
	wood = setup.wood.duplicate()
	points = [Point.new("粮仓", BattleSpace.GRAIN), Point.new("伐木场", BattleSpace.WOOD)]
	for fort in field.forts:
		points.append(Point.new("广场", fort.yard(), fort.side))

func spend(side: int, amount: int) -> bool:
	if wood[side] < amount:
		return false
	wood[side] -= amount
	return true

func tick(dt: float, field: BattleSpace, rules: BattleRules) -> void:
	for point in points:
		point.occupy(not field.near(point.at, 2.8, 0).is_empty(),
			not field.near(point.at, 2.8, 1).is_empty(), dt, rules.capture_seconds)
	clock += dt
	while clock >= rules.supply_period:
		clock -= rules.supply_period
		for side in 2:
			var harvest := 3 if points[0].owner == side else 0
			food[side] = maxi(0, food[side] + harvest - 1)
			if points[1].owner == side:
				wood[side] += 2
