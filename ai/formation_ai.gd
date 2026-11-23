class_name FormationAI extends RefCounted
## 小队把军令转换为互异的局部岗位，反馈到位/交战/受阻人数。
static func refresh_charge_goal(group: BattleFormation, opponents: BattleTeam) -> void:
	# 全军冲锋时每队从自己的位置择敌，敌军转移后仍会继续追击。
	var center := Vector2.ZERO
	var count := 0
	for member in group.members:
		if member.alive():
			center += member.position
			count += 1
	if count == 0:
		return
	center /= count
	var nearest := INF
	for enemy in opponents.units:
		var distance := center.distance_squared_to(enemy.position)
		if enemy.alive() and distance < nearest:
			nearest = distance
			group.goal = enemy.position

static func tick(group: BattleFormation, team: BattleTeam, field: BattleSpace, scan: bool, dt: float) -> void:
	group.anchor = group.goal
	if group.escort != null:
		if group.escort.ram_hp <= 0:
			group.issue(BattleFormation.Order.HOLD, group.anchor)
			group.notice = "攻城槌已毁，就地待命"
		else:
			group.goal = group.escort.ram_at
			group.anchor = group.goal
	if group.order == BattleFormation.Order.FOLLOW:
		group.anchor = team.leader.position
	group.arrived = 0
	group.blocked = 0
	group.engaged = 0
	var index := 0
	for unit in group.members:
		if not unit.alive():
			continue
		var post := group.slot(index)
		index += 1
		var leash := 8.0 if unit.spec.ranged else 4.0
		if not SoldierAI.act(unit, field, post, leash, scan, dt, group.order == BattleFormation.Order.CHARGE):
			group.blocked += 1
		if unit.target != null:
			group.engaged += 1
		if unit.position.distance_to(group.slot(index - 1)) < 1.1:
			group.arrived += 1
