class_name GeneralAI extends RefCounted
## 敌将只指挥本方，用与玩家相同的下令入口。守门队负责留守，外勤队比较任务收益。
static func decide(team: BattleTeam, field: BattleSpace, supply: BattleSupply, rules: BattleRules) -> void:
	var side := team.side
	var fort := field.forts[side]
	var enemy := field.forts[1 - side]
	var threats := field.near(fort.yard(), 5, 1 - side).size()
	# 侧门受威胁时关闭；安全后重开，外勤队仍能往返城内。
	fort.side_open = field.near(fort.gate + Vector2(0, BattleSpace.SIDE_Z), 4, 1 - side).is_empty()
	if fort.gate_hp < 65 and fort.gate_hp > 0:
		fort.repair(supply, rules, not field.near(fort.gate, 4, 1 - side).is_empty())
	if fort.ram_hp <= 0 and enemy.gate_hp > 0:
		fort.build(supply, rules)
	var destinations: Array[Vector2] = [BattleSpace.GRAIN, BattleSpace.WOOD, enemy.yard(), fort.yard()]
	var scores: Array[float] = [
		(8.0 if supply.food[side] < 6 else 4.0) if supply.points[0].owner != side else 0.0,
		6.0 if supply.points[1].owner != side and fort.ram_hp <= 0 else 0.0,
		7.0 if enemy.gate_hp <= 0 else 2.0,
		10.0 if threats > 3 else 0.0]
	var goal := destinations[scores.find(scores.max())]
	if fort.ram_hp > 0 and threats <= 3 and enemy.gate_hp > 0:
		goal = fort.ram_at
	for i in team.groups.size():
		var group := team.groups[i]
		var order := BattleFormation.Order.CHARGE
		var point := goal
		if group.role == "guard":
			order = BattleFormation.Order.HOLD
			point = fort.yard() if threats > 0 else fort.gate.move_toward(fort.yard(), 2)
		elif group.role == "bow":
			order = BattleFormation.Order.HOLD
			point = goal.move_toward(fort.yard(), 3.0)
		if group.order != order or point.distance_to(group.goal) > 1.0:
			team.command(i, order, point)
