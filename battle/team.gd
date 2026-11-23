class_name BattleTeam extends RefCounted
## 阵营持有军令入口；统领阵亡不影响该阵营对幸存小队的指挥权。
var side: int
var leader: BattleAgent
var groups: Array[BattleFormation] = []
var units: Array[BattleAgent] = []
var morale := 100.0
var pressure := ""
var hungry_time := 0.0
var last_strength := 0

func strength() -> int:
	var count := 0
	for unit in units:
		if unit.alive():
			count += 1
	return count

func command(index: int, order: BattleFormation.Order, goal: Vector2) -> void:
	if index >= 0 and index < groups.size():
		groups[index].issue(order, goal)
