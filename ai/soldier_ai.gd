class_name SoldierAI extends RefCounted
## 单兵在岗位附近选敌，跟随/坚守受活动半径约束，改令由编队清除旧目标。
static func choose(unit: BattleAgent, field: BattleSpace, post: Vector2, leash: float) -> BattleAgent:
	var best: BattleAgent
	var distance := maxf(unit.spec.reach, 3.0) + 1.0
	for enemy in field.near(unit.position, distance, 1 - unit.side):
		var d := enemy.position.distance_to(unit.position)
		if d < distance and enemy.position.distance_to(post) <= leash and field.clear_line(unit.position, enemy.position):
			best = enemy
			distance = d
	return best

static func act(unit: BattleAgent, field: BattleSpace, post: Vector2, leash: float, scan: bool, dt: float, charging := false) -> bool:
	if unit.stagger > 0:
		return true
	var center := unit.position if charging else post
	if scan:
		unit.target = choose(unit, field, center, leash)
		if unit.target == null:
			unit.target = choose(unit, field, unit.position, 1.15)
	var enemy := unit.target
	if unit.windup >= 0 and (enemy == null or enemy.manual == null or not enemy.alive() or unit.position.distance_to(enemy.position) > unit.spec.reach or not field.clear_line(unit.position, enemy.position)):
		unit.windup = -1
	if enemy != null and enemy.alive() and field.clear_line(unit.position, enemy.position):
		if unit.position.distance_to(enemy.position) <= unit.spec.reach:
			if enemy.position.distance_to(center) <= leash or enemy.position.distance_to(unit.position) <= 1.15:
				unit.strike(enemy, field)
				return true
		if enemy.position.distance_to(center) <= leash:
			return field.move(unit, enemy.position, dt)
	unit.target = null
	var moved := field.move(unit, post, dt)
	if not moved:
		hit_gate(unit, field)
	return moved

static func hit_gate(unit: BattleAgent, field: BattleSpace) -> void:
	var enemy_gate := field.forts[1 - unit.side]
	if not unit.spec.ranged and not unit.guarding and unit.cooldown <= 0 and unit.position.distance_to(enemy_gate.gate) < 2 and enemy_gate.gate_hp > 0:
		enemy_gate.damage_gate(2)
		unit.cooldown = unit.spec.interval
