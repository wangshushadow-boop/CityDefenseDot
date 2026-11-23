class_name BattleMission extends RefCounted
## 单局聚合根。持有场景与模块，按固定步长推进；只生成一次结算快照。
signal finished(result: Dictionary)
var rules: BattleRules
var setup: BattleSetup
var teams: Array[BattleTeam] = []
var field := BattleSpace.new()
var supply: BattleSupply
var result := {}
var elapsed := 0.0
var decision_clock := 0.0
var scan_clock := 0.0

func _init(input: BattleSetup, config: BattleRules) -> void:
	setup = input
	rules = config
	supply = BattleSupply.new(input, field)
	for side in 2:
		var team := BattleTeam.new()
		team.side = side
		teams.append(team)
	for entry in setup.roster:
		deploy(entry)
	for team in teams:
		team.last_strength = team.strength()
	teams[0].leader.manual = CommanderCombat.new()
	field.rebuild(teams)

func deploy(entry: Dictionary) -> void:
	var team := teams[int(entry.side)]
	var group := BattleFormation.new()
	group.id = entry.id
	group.title = entry.title
	group.role = entry.role
	var base := field.forts[team.side].yard()
	match group.role:
		"guard": base.y = -2.5
		"field": base.y = 6.0
		"bow": base.y = 2.0
	group.goal = base
	group.anchor = base
	for i in int(entry.count):
		var unit := BattleAgent.new(team.side, group.slot(i), entry.spec)
		group.members.append(unit)
		team.units.append(unit)
		if group.role == "leader":
			team.leader = unit
	if group.role != "leader":
		team.groups.append(group)

func tick(dt: float, movement: Vector2 = Vector2.ZERO) -> void:
	if not result.is_empty():
		return
	elapsed += dt
	decision_clock -= dt
	scan_clock -= dt
	var scan := scan_clock <= 0
	if scan:
		scan_clock = 0.3
	for team in teams:
		for unit in team.units:
			unit.cooldown = maxf(0, unit.cooldown - dt)
			unit.stagger = maxf(0, unit.stagger - dt)
			if unit.windup >= 0:
				unit.windup = maxf(0, unit.windup - dt)
	field.rebuild(teams)
	if decision_clock <= 0:
		GeneralAI.decide(teams[1], field, supply, rules)
		decision_clock = 1.0
	var player := teams[0].leader
	if player.alive():
		field.move(player, player.position + movement.limit_length() * dt * player.spec.speed * player.manual.movement_scale(movement), dt, false)
		player.manual.tick(player, field, dt)
	var enemy_leader := teams[1].leader
	if enemy_leader.alive():
		var rally := field.forts[1].yard()
		for group in teams[1].groups:
			if group.role == "field":
				rally = group.goal
		SoldierAI.act(enemy_leader, field, rally, 8, scan, dt)
	for team in teams:
		for group in team.groups:
			if scan and group.pursue_enemies:
				FormationAI.refresh_charge_goal(group, teams[1 - team.side])
			FormationAI.tick(group, team, field, scan, dt)
	field.rebuild(teams)
	for fort in field.forts:
		fort.tick_ram(dt, field.forts[1 - fort.side], field)
	supply.tick(dt, field, rules)
	var end := BattleOutcome.assess(dt, teams, supply, rules)
	if not end.is_empty():
		finish(end.winner, end.reason)

func command(group: int, order: BattleFormation.Order, at: Vector2, pursue := false) -> void:
	if not result.is_empty() or group < 0 or group >= teams[0].groups.size():
		return
	teams[0].command(group, order, at.clamp(-BattleSpace.LIMIT, BattleSpace.LIMIT))
	var fort := field.forts[0]
	if pursue and order == BattleFormation.Order.CHARGE:
		teams[0].groups[group].pursue_enemies = true
		scan_clock = 0
	elif order == BattleFormation.Order.CHARGE and fort.ram_hp > 0 and at.distance_to(fort.ram_at) < 2:
		teams[0].groups[group].escort = fort

func nearby_facility() -> String:
	var fort := field.forts[0]
	var at := teams[0].leader.position
	if at.distance_to(fort.gate + Vector2(0, BattleSpace.SIDE_Z)) < 3:
		return "gate"
	if at.distance_to(fort.gate) < 3:
		return "repair"
	if at.distance_to(fort.yard()) < 3:
		return "ram"
	return ""

func player_action(key: String) -> String:
	if not result.is_empty():
		return "战斗已结束"
	var fort := field.forts[0]
	match key:
		"ram": return fort.build(supply, rules)
		"repair": return fort.repair(supply, rules, not field.near(fort.gate, 4, 1).is_empty())
		"gate":
			fort.side_open = not fort.side_open
			return "侧门已开启" if fort.side_open else "侧门已关闭"
		"surrender": finish(1, "玩家投降")
	return ""

func finish(winner: int, reason: String) -> void:
	if not result.is_empty():
		return
	var roster: Array[Dictionary] = []
	for entry in setup.roster:
		var team := teams[int(entry.side)]
		var alive_count := int(team.leader.alive()) if entry.role == "leader" else 0
		for group in team.groups:
			if group.id == entry.id:
				alive_count = group.strength()
		roster.append({"id": entry.id, "side": entry.side, "title": entry.title,
			"survivors": alive_count, "losses": int(entry.count) - alive_count})
	result = {"winner": winner, "reason": reason, "elapsed": elapsed, "roster": roster,
		"settlement_id": setup.settlement_id, "settlement_owner": winner}
	release_targets()
	finished.emit(result)

func release_targets() -> void:
	# 角色可能互相选为目标；离开战场时解除引用，确保整局对象可以释放。
	for team in teams:
		for unit in team.units:
			unit.target = null
