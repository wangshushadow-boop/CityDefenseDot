class_name BattleSetup extends RefCounted
## 独立开局与未来战役共用输入。每支队伍有稳定来源编号，战果据此回写。
var map_id := "twin_forts"
var settlement_id := "双城关"
var roster: Array[Dictionary] = []
var food: Array[int] = [0, 0]
var wood: Array[int] = [0, 0]

static func standalone(rules: BattleRules, guards: int = 8) -> BattleSetup:
	var setup := BattleSetup.new()
	for side in 2:
		var g := clampi(guards, 1, 17) if side == 0 else 8
		setup.food[side] = rules.initial_food
		setup.add_group(side, "leader", "统领", rules.commander, 1)
		setup.add_group(side, "guard", "守门步兵", rules.infantry, g)
		setup.add_group(side, "field", "出城步兵", rules.infantry, 18 - g)
		setup.add_group(side, "bow", "弓兵", rules.archer, 11)
	return setup

func add_group(side: int, key: String, title: String, spec: TroopSpec, count: int) -> void:
	roster.append({"side": side, "id": "%d/%s" % [side, key], "role": key,
		"title": title, "spec": spec, "count": count})

func validation_error() -> String:
	# 战役传入的名单也要能安全展开，避免重复编号在结算时覆盖不同部队。
	if map_id != "twin_forts" or settlement_id.is_empty():
		return "地图或争夺据点无效"
	if food.size() != 2 or wood.size() != 2 or food.min() < 0 or wood.min() < 0:
		return "双方初始补给无效"
	var leaders := [0, 0]
	var squads := [0, 0]
	var ids := {}
	for row in roster:
		if not row.has_all(["side", "id", "role", "title", "spec", "count"]):
			return "参战名单缺少字段"
		if row.side not in [0, 1] or typeof(row.side) != TYPE_INT or typeof(row.count) != TYPE_INT or row.count <= 0:
			return "参战方或人数无效"
		if row.id is not String or row.id.is_empty() or ids.has(row.id) or row.spec is not TroopSpec:
			return "来源编号或兵种无效"
		ids[row.id] = true
		if row.role == "leader":
			leaders[row.side] += row.count
		else:
			squads[row.side] += 1
	if leaders != [1, 1] or squads.min() == 0:
		return "每方需要一名统领和可指挥的小队"
	return ""
