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

func key(code: Key, down := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	root.push_input(event, true)

func mouse(button: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	root.push_input(event, true)

func motion(delta: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = delta
	root.push_input(event, true)

func check_controls(app: Node) -> void:
	var m: BattleMission = app.mission
	var player := m.teams[0].leader
	var fighter := player.manual
	var front := m.teams[1].units[1]
	var rear := m.teams[1].units[2]
	# 在城内空地单独对练，避免友军先击倒目标或目标自行撤离。
	player.position = Vector2(-45, -17)
	front.stagger = 2
	rear.stagger = 2
	front.position = player.position + Vector2.RIGHT * 0.85
	rear.position = player.position - Vector2.RIGHT * 0.55
	m.field.rebuild(m.teams)
	for delta: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		motion(delta * 6)
		mouse(MOUSE_BUTTON_LEFT, true)
		check(fighter.winding and fighter.direction == CommanderCombat.mouse_direction(delta), "按下左键应锁定鼠标指示的来向")
		mouse(MOUSE_BUTTON_RIGHT, true)
		mouse(MOUSE_BUTTON_LEFT, false)
		check(player.guarding and fighter.swing_time == 0 and player.cooldown == 0, "右键应取消蓄力，松开左键不能补出一击")
		mouse(MOUSE_BUTTON_RIGHT, false)
	mouse(MOUSE_BUTTON_LEFT, true)
	fighter.tick(player, m.field, 1.4)
	check(front.hits == 0, "长按左键不能自动攻击")
	mouse(MOUSE_BUTTON_LEFT, false)
	m.tick(0.11)
	m.tick(0.01)
	check(front.hits == 1 and rear.hits == 0, "松开一次只命中身前目标一次")
	key(KEY_SPACE)
	app._physics_process(0.03)
	check(fighter.elevation > 0 and not fighter.winding, "空格应起跳")
	fighter.tick(player, m.field, 1.0)
	key(KEY_Z)
	check(fighter.crouching and fighter.movement_scale(Vector2.RIGHT) < 1, "下蹲降低移动速度")
	key(KEY_Z)
	key(KEY_CAPSLOCK)
	check(fighter.walking and fighter.movement_scale(Vector2.RIGHT) < 1, "步行应可切换")
	key(KEY_CAPSLOCK)
	key(KEY_SHIFT)
	app._physics_process(0.01)
	check(app.view.camera.fov < 50 and not player.guarding, "Shift 应收窄视野")
	key(KEY_SHIFT, false)
	key(KEY_QUOTELEFT)
	var facing := fighter.facing
	motion(Vector2(90, -15))
	check(fighter.facing.is_equal_approx(facing) and app.view.camera.free_yaw != 0, "自由观察须保持行进朝向")
	key(KEY_QUOTELEFT, false)
	check(app.view.camera.free_yaw == 0 and app.view.camera.free_pitch == 0, "松开观察应回到角色视角")
	key(KEY_R)
	app._physics_process(0.01)
	check(app.view.camera.first_person and not app.view.models[player].head_parts[0].visible, "第一人称应隐藏挡住视野的头盔")
	key(KEY_R)
	mouse(MOUSE_BUTTON_MIDDLE, true)
	check(app.view.camera.locked == front, "中键应锁定视线内的前方敌人")
	mouse(MOUSE_BUTTON_MIDDLE, true)
	player.cooldown = 0
	mouse(MOUSE_BUTTON_RIGHT, true)
	var hp := player.hp
	check(fighter.absorb(player, 10, front, CommanderCombat.Direction.LEFT) == 0 and fighter.shield_hp < 100, "盾牌应消耗耐久拦截正面伤害")
	check(fighter.absorb(player, 10, rear, CommanderCombat.Direction.LEFT) == 10, "举盾不能防住背后的攻击")
	key(KEY_E)
	check(fighter.bashing and front.stagger > 0 and not player.guarding and player.hp == hp, "举盾时 E 应盾击并打断近敌")
	mouse(MOUSE_BUTTON_RIGHT, false)
	fighter.tick(player, m.field, 0.9)
	mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
	motion(Vector2.LEFT * 4)
	mouse(MOUSE_BUTTON_RIGHT, true)
	check(not fighter.shield and fighter.absorb(player, 10, front, CommanderCombat.Direction.RIGHT) == 0 and fighter.absorb(player, 10, front, CommanderCombat.Direction.LEFT) == 10, "持剑格挡只拦截对向近战")
	mouse(MOUSE_BUTTON_RIGHT, false)
	player.cooldown = 0
	mouse(MOUSE_BUTTON_LEFT, true)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	mouse(MOUSE_BUTTON_LEFT, false)
	check(app.commanding and not fighter.winding and fighter.swing_time == 0, "失去焦点后应解除蓄力")
	key(KEY_ESCAPE)
	key(KEY_TAB)
	check(app.ui.score.visible and not app.commanding, "Tab 应显示战况并保留战斗控制")
	key(KEY_TAB, false)
	key(KEY_2)
	key(KEY_F1)
	key(KEY_F2)
	check(m.teams[0].groups[2].order == BattleFormation.Order.FOLLOW and m.teams[0].groups[0].order == BattleFormation.Order.HOLD, "2、F1、F2 应只让弓兵跟随")
	key(KEY_0)
	key(KEY_F1)
	key(KEY_F3)
	m.tick(0.03)
	check(m.teams[0].groups.all(func(g: BattleFormation): return g.pursue_enemies and g.order == BattleFormation.Order.CHARGE), "0、F1、F3 应令全军主动追敌")
	app.view.camera.pitch = 0.65
	app.view.refresh(app.aim, 0)
	key(KEY_3)
	key(KEY_F1)
	key(KEY_F1)
	check(not app.choosing_order and not m.teams[0].groups[0].pursue_enemies and m.teams[0].groups[0].goal == app.aim, "3、F1、F1 应令守门队停止追敌并到准星地面坚守")
	player.position = m.field.forts[0].gate + Vector2(0, BattleSpace.SIDE_Z)
	key(KEY_F)
	check(not m.field.forts[0].side_open, "靠近己方侧门时 F 应与城防交互")
	# 关闭的城墙挡住武器、锁敌和踢击；打开侧门后同一位置可交手。
	player.position.x -= 0.4
	front.position = player.position + Vector2.RIGHT * 0.8
	m.field.rebuild(m.teams)
	check(fighter.front_target(player, m.field, 1.3, 0.38) == null, "关门应阻止准星隔墙选敌")
	key(KEY_F)
	front.cooldown = 0
	front.stagger = 0
	front.windup = -1
	front.next_strike = CommanderCombat.Direction.RIGHT
	motion(Vector2.LEFT * 3)
	mouse(MOUSE_BUTTON_RIGHT, true)
	var hp_before := player.hp
	check(not front.strike(player, m.field) and front.windup > 0, "近敌应先亮出攻击方向")
	front.windup = 0
	check(front.strike(player, m.field) and player.hp == hp_before, "匹配方向的剑挡应在实际受击路径生效")
	mouse(MOUSE_BUTTON_RIGHT, false)
	player.position = Vector2(-45, -17)
	fighter.facing = Vector2.RIGHT
	front.position = player.position + Vector2(0.8, 0.6)
	rear.position = player.position + Vector2(0.8, -0.6)
	m.field.rebuild(m.teams)
	var front_hits := front.hits
	var rear_hits := rear.hits
	fighter.direction = CommanderCombat.Direction.LEFT
	fighter.hit(player, m.field)
	check(front.hits == front_hits and rear.hits == rear_hits + 1, "并列敌人中左斩应先扫到左敌")
	fighter.direction = CommanderCombat.Direction.RIGHT
	fighter.hit(player, m.field)
	check(front.hits == front_hits + 1 and rear.hits == rear_hits + 1, "右斩应先扫到右敌")
	key(KEY_BACKSLASH)
	mouse(MOUSE_BUTTON_LEFT, true)
	check(not fighter.drawn and not fighter.winding, "收剑后不能空手发出剑击")
	mouse(MOUSE_BUTTON_WHEEL_UP, true)
	check(fighter.drawn, "上滚应重新装备主手剑")

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
	check(app.view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and app.view.camera.position.distance_to(app.view.models[team.leader].position) < 5, "开局应为统领肩后透视镜头")
	check(app.view.models[team.leader].motion.get_animation("Walk").loop_mode == Animation.LOOP_LINEAR, "行军动画应可连续循环")
	app.view.camera.orbit(Vector2(200, 10))
	var forward: Vector2 = app.view.camera.movement(Vector2.UP)
	check(forward.y > 0.5 and forward.x > 0.7, "前进方向应随镜头转动")
	app.set_commanding(true)
	check(app.ui.commands.visible, "指挥模式应显示小队命令")
	app.view.camera.yaw = 0
	check(BattleSpace.LIMIT * 2 == Vector2(112, 56), "可玩区域应扩大为 112 × 56 米")
	var probe := BattleAgent.new(0, Vector2(-10, 0), CONFIG.infantry)
	var crossed := false
	for step in 650:
		m.field.move(probe, BattleSpace.GRAIN, 1.0 / 30.0)
		if absf(probe.position.y - FieldTerrain.river_z(probe.position.x)) < 0.5:
			crossed = true
			check(FieldTerrain.ford(probe.position.x) >= 0.75, "过河应经过浅滩")
			break
	check(crossed, "单兵应能找到浅滩")
	for step in 650:
		m.field.move(probe, BattleSpace.GRAIN, 1.0 / 30.0)
	check(probe.position.distance_to(BattleSpace.GRAIN) < 0.2, "绕行后应能抵达对岸粮仓")
	probe.position = Vector2(-30,-8)
	for step in 120:
		m.field.move(probe, Vector2(-26,-8), 1.0 / 30.0, false)
	check(not FieldTerrain.in_rock(probe.position), "统领和士兵移动应遵守同一岩石边界")
	probe.position = Vector2.ZERO
	probe.detour.clear()
	var woodland := Vector2(-32, 24)
	for step in 950:
		m.field.move(probe, woodland, 1.0 / 30.0)
	check(probe.position.distance_to(woodland) < 0.2, "穿过林缘的路段应绕开相邻网格之间的树干")
	app.ui.picker.select(1)
	app.aim = BattleSpace.WOOD
	app.ui.ordered.emit(BattleFormation.Order.HOLD)
	check(group.goal == BattleSpace.WOOD, "玩家命令应到达选中的小队")
	# 两城间距随地图翻倍，给出城编队走到伐木场的行军时间。
	for i in 600:
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
	check(app.view.camera.overview and app.view.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "统领阵亡应切到全图指挥")
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
	check_controls(app)
	await process_frame
	await process_frame
	# 多道按键军令在同一帧注入，等音频线程播完提示再销毁战场。
	await create_timer(0.2).timeout
	for unit in m.teams[1].units:
		unit.receive_hit(10000)
	m.tick(0.1)
	check(m.result.get("reason") == "全军覆没" and m.result.get("winner") == 0, "全灭应立即结束")
	app.queue_free()
	await process_frame
	await process_frame
	print("框架自检：%d 项，%d 项失败" % [checks, failures])
	quit(1 if failures else 0)
