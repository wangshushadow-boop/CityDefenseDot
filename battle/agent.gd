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

func _init(faction: int, origin: Vector2, data: TroopSpec) -> void:
	side = faction
	position = origin
	spec = data
	hp = data.health

func alive() -> bool:
	return hp > 0.0

func receive_hit(damage: float) -> void:
	hp = maxf(0.0, hp - damage * (0.3 if guarding else 1.0))
	hits += 1

func strike(enemy: BattleAgent, field: BattleSpace) -> bool:
	if not alive() or guarding or cooldown > 0 or not enemy.alive() or enemy.side == side:
		return false
	if position.distance_to(enemy.position) > spec.reach or not field.clear_line(position, enemy.position):
		return false
	enemy.receive_hit(spec.damage)
	cooldown = spec.interval
	return true
