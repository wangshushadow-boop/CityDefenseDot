class_name BattleOutcome extends RefCounted
## 只由终局模块裁定胜负。士气原因同时供界面读取，断粮时长决定持续压力。
static func assess(dt: float, teams: Array[BattleTeam], economy: BattleSupply, rules: BattleRules) -> Dictionary:
	for team in teams:
		var count := team.strength()
		var lost := maxi(0, team.last_strength - count)
		team.last_strength = count
		var causes: Array[String] = []
		var pressure := 0.0
		if economy.food[team.side] <= 0:
			team.hungry_time += dt
			pressure += minf(0.55, 0.08 + team.hungry_time / 200.0)
			causes.append("断粮")
		else:
			team.hungry_time = 0
		if economy.points[2 + team.side].owner != team.side:
			pressure += 0.65
			causes.append("广场失守")
		team.pressure = "、".join(causes) if not causes.is_empty() else "无持续压力"
		team.morale = maxf(0, team.morale - lost * 2.0 - pressure * dt)
	for team in teams:
		if team.last_strength == 0:
			return {"winner": 1 - team.side, "reason": "全军覆没"}
	var enemy := teams[1]
	if enemy.morale < rules.surrender_morale and (enemy.last_strength <= rules.surrender_strength or economy.points[3].owner == 0):
		return {"winner": 0, "reason": "敌军投降"}
	return {}
