extends SceneTree
## 无窗口自检。通过真实主场景和业务入口验证一局的生命周期与跨模块规则。
const CONFIG: BattleRules = preload("res://data/default_rules.tres")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func run() -> void:
	var invalid := BattleSetup.standalone(CONFIG)
	invalid.roster[1].id = invalid.roster[0].id
	check(not invalid.validation_error().is_empty(), "重复来源编号应在部署前被拒绝")
	var app := preload("res://app/main.tscn").instantiate()
	root.add_child(app)
	var play: Button = app.ui.root.find_children("*", "Button", true, false).back()
	play.pressed.emit()
	var m: BattleMission = app.mission
	check(m.teams[0].strength() == 30 and m.teams[1].strength() == 30, "开局兵力应各含统领 30 人")
	check(app.view.models.size() == 60 and app.view.camera.current, "场景应准备角色模型与相机")
	var team := m.teams[0]
	var group := team.groups[1]
	app.ui.picker.select(1)
	app.aim = BattleSpace.WOOD
	app.ui.ordered.emit(BattleFormation.Order.HOLD)
	check(group.goal == BattleSpace.WOOD, "玩家命令应到达选中的小队")
	for i in 360:
		m.tick(1.0 / 30.0)
	check(group.members[0].position.distance_to(BattleSpace.WOOD) < 8, "出城队应通过门洞抵达伐木场附近")
	check(m.teams[1].groups[1].goal != m.field.forts[1].yard(), "敌将应为外勤队分配任务")

	var fort := m.field.forts[0]
	var entry := fort.gate + Vector2(0, BattleSpace.SIDE_Z)
	check(m.field.clear_line(entry - Vector2.RIGHT, entry + Vector2.RIGHT), "开启的侧门允许双方通过")
	fort.side_open = false
	check(not m.field.clear_line(entry - Vector2.RIGHT, entry + Vector2.RIGHT), "关闭侧门后应阻断入口")
	check(not m.field.clear_line(fort.gate - Vector2.RIGHT, fort.gate + Vector2.RIGHT), "关门后应阻挡通行和射线")
	fort.gate_hp = 0
	check(m.field.clear_line(fort.gate - Vector2.RIGHT, fort.gate + Vector2.RIGHT), "破门后应贯通缺口")
	m.supply.wood[0] = CONFIG.ram_cost
	fort.repair(m.supply, CONFIG, false)
	check(fort.gate_hp == 0 and m.supply.wood[0] == CONFIG.ram_cost, "已破城门不能维修或扣料")
	fort.build(m.supply, CONFIG)
	check(fort.ram_hp > 0 and m.supply.wood[0] == 0, "造槌应扣一次木料")
	m.command(1, BattleFormation.Order.CHARGE, fort.ram_at)
	check(group.escort == fort, "点选己方攻城槌应进入护送")
	fort.ram_hp = 0
	m.tick(0.03)
	check(group.escort == null and group.order == BattleFormation.Order.HOLD, "器械摧毁后应结束护送")

	var grain := m.supply.points[0]
	grain.owner = -1
	grain.occupy(true, false, 1, CONFIG.capture_seconds)
	var previous := grain.progress
	grain.occupy(true, true, 3, CONFIG.capture_seconds)
	check(grain.progress == previous, "争夺中的进度应暂停")
	grain.occupy(true, false, CONFIG.capture_seconds, CONFIG.capture_seconds)
	check(grain.owner == 0, "完成占领后应易主")
	var empty := BattleSpace.new()
	m.supply.clock = 0
	var stock := m.supply.food[0]
	m.supply.tick(CONFIG.supply_period, empty, CONFIG)
	check(m.supply.food[0] == stock + 2, "周期产出和消耗应入账")
	var enemy_fort := m.field.forts[1]
	enemy_fort.gate_hp = 40
	m.supply.wood[1] = CONFIG.repair_cost
	enemy_fort.repair(m.supply, CONFIG, true)
	check(enemy_fort.gate_hp == 40 and m.supply.wood[1] == CONFIG.repair_cost, "敌军在门边时修门失败且不扣料")
	enemy_fort.repair(m.supply, CONFIG, false)
	check(enemy_fort.gate_hp > 40 and m.supply.wood[1] == 0, "成功修门应增加耐久并扣料")
	m.supply.food[0] = 0
	BattleOutcome.assess(1, m.teams, m.supply, CONFIG)
	check(team.pressure.contains("断粮"), "界面应能说明士气原因")
	m.supply.food[0] = 4
	BattleOutcome.assess(1, m.teams, m.supply, CONFIG)
	check(team.hungry_time == 0 and not team.pressure.contains("断粮"), "恢复供粮应停止压力")

	team.leader.receive_hit(10000)
	m.command(1, BattleFormation.Order.CHARGE, BattleSpace.GRAIN)
	m.tick(0.1)
	app.view.refresh(app.aim, 0.1)
	app.ui.refresh(m)
	check(group.goal == BattleSpace.GRAIN and app.ui.stats.text.contains("指挥视角"), "统领阵亡后仍可指挥")
	app.ui.action_requested.emit("surrender")
	check(m.result.winner == 1 and m.result.roster[0].losses == 1, "结算应带回统领伤亡与胜负")
	var snapshot := m.result.duplicate(true)
	m.tick(10)
	m.finish(0, "重复")
	check(m.result == snapshot, "终局必须幂等")
	app.ui.menu_requested.emit()
	app.ui.start_requested.emit(5)
	m = app.mission
	check(m.teams[0].strength() == 30 and m.teams[0].groups[0].strength() == 5, "再次开局应重新分配守军")
	check(m.supply.wood[0] == 0 and m.field.forts[0].gate_hp == 100, "新局应重置库存与城门")

	m.teams[1].morale = 1
	m.tick(0.1)
	check(m.result.is_empty(), "仅低士气不能触发投降")
	m.supply.points[3].owner = 0
	m.tick(0.1)
	check(m.result.get("reason") == "敌军投降", "低士气并且广场失守应触发投降")
	app.ui.menu_requested.emit()
	app.ui.start_requested.emit(8)
	m = app.mission
	for unit in m.teams[1].units:
		unit.receive_hit(10000)
	m.tick(0.1)
	check(m.result.get("reason") == "全军覆没" and m.result.get("winner") == 0, "全灭应立即结束")
	app.queue_free()
	await process_frame
	await process_frame
	print("框架自检：%d 项，%d 项失败" % [checks, failures])
	quit(1 if failures else 0)
