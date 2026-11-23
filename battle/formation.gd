class_name BattleFormation extends RefCounted
## 编队共有一条命令。岗位按存活成员顺序分配，减员后自动补位。
enum Order { FOLLOW, HOLD, CHARGE }
const LABELS := ["跟随", "坚守", "冲锋"]
var id: String
var title: String
var role: String
var members: Array[BattleAgent] = []
var order := Order.HOLD
var goal: Vector2
var anchor: Vector2
var escort: BattleFort
var notice := ""
var arrived := 0
var engaged := 0
var blocked := 0

func issue(next: Order, point: Vector2) -> void:
	order = next
	goal = point
	escort = null
	notice = ""
	# 改令后立刻丢弃上个目标，避免撤回中的士兵继续追敌。
	for unit in members:
		unit.target = null

func slot(index: int) -> Vector2:
	return anchor + Vector2((index % 4 - 1.5) * 0.8, (floori(index / 4.0) - 1) * 0.85)

func strength() -> int:
	var count := 0
	for unit in members:
		if unit.alive():
			count += 1
	return count
