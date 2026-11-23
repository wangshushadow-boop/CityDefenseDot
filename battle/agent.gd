class_name BattleAgent extends RefCounted
## 玩家、统领和士兵通过同一套受击、攻击和移动接口行动。
var side: int
var position: Vector2
var spec: TroopSpec
var hp: float
var guarding := false
var cooldown := 0.0
var target: BattleAgent
var hits := 0
var manual: CommanderCombat
var stagger := 0.0
var next_strike := CommanderCombat.Direction.RIGHT
var windup := -1.0
var detour := PackedVector2Array()
var detour_goal: Vector2

func _init(faction: int, origin: Vector2, data: TroopSpec) -> void:
	side = faction
	position = origin
	spec = data
	hp = data.health

func alive() -> bool:
	return hp > 0.0

func receive_hit(damage: float) -> void:
	hp = maxf(0.0, hp - damage)
	hits += 1

func strike(enemy: BattleAgent, field: BattleSpace) -> bool:
	if not alive() or guarding or stagger > 0 or cooldown > 0 or not enemy.alive() or enemy.side == side:
		return false
	if position.distance_to(enemy.position) > spec.reach or not field.clear_line(position, enemy.position):
		return false
	var damage := spec.damage
	if enemy.manual != null:
		# 与玩家交锋时先亮出近战来向，留出看招和格挡的窗口。
		if not spec.ranged:
			if windup < 0:
				windup = 0.35
			if windup > 0:
				return false
		damage = enemy.manual.absorb(enemy, damage, self, next_strike)
	if damage > 0:
		enemy.receive_hit(damage)
	next_strike = (int(next_strike) + 1) % 4 as CommanderCombat.Direction
	windup = -1
	cooldown = spec.interval
	return true
