class_name BattleFort extends RefCounted
## 城防状态与操作。攻城槌出城时打开本方正门，开口对两军均有效。
var side: int
var gate: Vector2
var gate_hp := 100.0
var side_open := true
var ram_hp := 0.0
var ram_at: Vector2

func _init(faction: int) -> void:
	side = faction
	gate = Vector2(-18 if side == 0 else 18, 0)
	ram_at = yard()

func yard() -> Vector2:
	return gate * 1.25

func front_open() -> bool:
	return gate_hp <= 0 or (ram_hp > 0 and absf(ram_at.x - gate.x) < 6)

func build(supply: BattleSupply, rules: BattleRules) -> String:
	if ram_hp > 0:
		return "已有攻城槌"
	if not supply.spend(side, rules.ram_cost):
		return "造槌木料不足"
	ram_hp = 70
	ram_at = yard()
	return "攻城槌已造好，调步兵沿主路护送"

func repair(supply: BattleSupply, rules: BattleRules, threatened: bool) -> String:
	if threatened or gate_hp <= 0 or gate_hp >= 100:
		return "无法维修：门已完好、已破或附近有敌军"
	if not supply.spend(side, rules.repair_cost):
		return "修门木料不足"
	gate_hp = minf(100, gate_hp + 35)
	return "城门已维修"

func tick_ram(dt: float, enemy: BattleFort, field: BattleSpace) -> void:
	if ram_hp <= 0:
		return
	var guards := field.near(ram_at, 4, side)
	var escorted := false
	for unit in guards:
		if not unit.spec.ranged:
			escorted = true
			break
	for unit in field.near(ram_at, 1.6, 1 - side):
		if not unit.spec.ranged and unit.cooldown <= 0:
			ram_hp = maxf(0, ram_hp - unit.spec.damage)
			unit.cooldown = unit.spec.interval
	if escorted and ram_hp > 0 and enemy.gate_hp > 0:
		var stop := enemy.gate.move_toward(Vector2.ZERO, 1)
		ram_at = ram_at.move_toward(stop, dt * 2.3)
		if ram_at.distance_to(stop) < 0.1:
			enemy.gate_hp = maxf(0, enemy.gate_hp - dt * 12)
