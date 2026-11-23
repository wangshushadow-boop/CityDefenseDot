class_name BattleUI extends CanvasLayer
## 游戏界面负责部署、战场信息、指挥和结算。按钮只提交意图，战况来自本局模拟。
const S := preload("res://presentation/ui/war_style.gd")
const Pages := preload("res://presentation/ui/campaign_pages.gd")
const Report := preload("res://presentation/ui/troop_report.gd")
const FieldMap := preload("res://presentation/ui/field_map.gd")
signal start_requested(guards: int)
signal menu_requested
signal ordered(order: BattleFormation.Order)
signal action_requested(action: String)
signal resume_requested
signal target_selected(at: Vector2)
var root := Control.new()
var hud: Control
var commands: PanelContainer
var score: ColorRect
var report: Report
var report_scroll: ScrollContainer
var picker: OptionButton
var feedback: Label
var stats: Label
var reticle: Label
var interaction: Label
var banner_counts: Array[Label] = []
var time_label: Label
var balance: ProgressBar
var health: ProgressBar
var shield: ProgressBar
var vitals: Label
var durability: Label
var resources: Label
var group_detail: Label
var points: Label
var fort_detail: Label
var compact: PanelContainer
var compact_points: Label
var supplies_brief: Label
var map_card: PanelContainer
var field_map: FieldMap
var resume: Button
var ram: Button
var repair: Button
var gate: Button
var quick: Label
var orders_hint: Label
var feedback_panel: PanelContainer
var feedback_until := 0
var pending_orders := false
var next_details := 0

func _ready() -> void:
	add_child(root)
	root.theme = S.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

func clear() -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	banner_counts.clear()

func menu(setup: BattleSetup) -> void:
	clear()
	var page := Pages.new()
	root.add_child(page)
	page.deploy.connect(start_requested.emit)
	page.deployment(setup)

func summary(result: Dictionary) -> void:
	clear()
	var page := Pages.new()
	root.add_child(page)
	page.return_requested.connect(menu_requested.emit)
	page.summary(result)

func battle(mission: BattleMission) -> void:
	clear()
	hud = Control.new()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_balance()
	compact = S.panel(hud)
	S.pin(compact, Vector2.ZERO, 22, 22, 206, 0)
	var brief := S.stack(compact, 5)
	S.label(brief, "战场据点", 19, S.GOLD, true)
	compact_points = S.label(brief, "", 15)
	S.rule(brief)
	supplies_brief = S.label(brief, "", 14, S.MUTED)
	build_personal()
	build_orders(mission)
	map_card = S.panel(hud, true)
	S.pin(map_card, Vector2(1, 0), -324, 22, 302, 0)
	var map_body := S.stack(map_card)
	S.label(map_body, "河谷沙盘", 21, S.GOLD, true)
	field_map = FieldMap.new()
	field_map.custom_minimum_size.y = 137
	field_map.mission = mission
	field_map.mouse_default_cursor_shape = Control.CURSOR_CROSS
	field_map.destination.connect(target_selected.emit)
	map_body.add_child(field_map)
	S.label(map_body, "点击沙盘选目标　·　金环为军令落点", 14, S.MUTED)
	build_score(mission)
	pending_orders = false
	next_details = 0
	command_mode(false)

func build_balance() -> void:
	var card := S.panel(hud)
	S.pin(card, Vector2(0.5, 0), -217, 16, 434, 0)
	card.add_theme_stylebox_override("panel", S.plate(Color("#1c211fe3"), S.EDGE, 7))
	var line := S.row(card, 10)
	S.banner(line, Vector2(31, 41))
	var center := S.stack(line, 4)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var numbers := S.row(center)
	banner_counts.append(S.label(numbers, "", 18, S.BLUE))
	time_label = S.label(numbers, "", 16, S.GOLD)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_counts.append(S.label(numbers, "", 18, S.RED))
	balance = S.meter(center, S.BLUE, S.RED)
	S.banner(line, Vector2(31, 41), true)

func build_personal() -> void:
	reticle = S.label(hud, "", 19)
	S.pin(reticle, Vector2(0.5, 0.5), -70, -17, 140, 34)
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.add_theme_constant_override("outline_size", 5)
	interaction = S.label(hud, "", 16, S.IVORY)
	S.pin(interaction, Vector2(0.5, 0.5), -145, 39, 290, 28)
	interaction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction.add_theme_constant_override("outline_size", 5)
	var card := S.panel(hud)
	S.pin(card, Vector2.ONE, -294, -132, 272, 0)
	var box := S.stack(card, 3)
	stats = S.label(box, "", 22, S.GOLD, true)
	vitals = S.label(box, "", 14)
	health = S.meter(box, Color("#a75246"))
	durability = S.label(box, "", 14)
	shield = S.meter(box, Color("#97a9a7"))
	feedback_panel = S.panel(hud)
	S.pin(feedback_panel, Vector2(0, 1), 22, -112, 432, 0)
	var lower := S.stack(feedback_panel, 5)
	quick = S.label(lower, "", 18, S.GOLD, true)
	feedback = S.label(lower, "", 15)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	orders_hint = S.label(lower, "", 14, S.MUTED)

func build_orders(mission: BattleMission) -> void:
	commands = S.panel(hud, true)
	S.pin(commands, Vector2.ZERO, 22, 22, 340, 0)
	var box := S.stack(commands, 6)
	S.label(box, "战场指挥", 28, S.GOLD, true)
	picker = OptionButton.new()
	for group in mission.teams[0].groups:
		picker.add_item(group.title)
	picker.add_item("全军")
	picker.select(picker.item_count - 1)
	box.add_child(picker)
	var squads := ScrollContainer.new()
	squads.custom_minimum_size.y = 68
	squads.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(squads)
	group_detail = S.label(squads, "", 14, S.MUTED)
	group_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var orders := S.row(box, 5)
	for code in [BattleFormation.Order.HOLD, BattleFormation.Order.FOLLOW, BattleFormation.Order.CHARGE]:
		var button := S.button(orders, BattleFormation.LABELS[code], ordered.emit.bind(code))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	S.rule(box)
	S.label(box, "军需与据点", 20, S.GOLD, true)
	resources = S.label(box, "", 15)
	points = S.label(box, "", 15)
	S.rule(box)
	S.label(box, "城防工事", 20, S.GOLD, true)
	fort_detail = S.label(box, "", 15)
	var works := S.row(box, 5)
	ram = S.button(works, "造槌", action_requested.emit.bind("ram"))
	repair = S.button(works, "修门", action_requested.emit.bind("repair"))
	gate = S.button(works, "侧门", action_requested.emit.bind("gate"))
	for button in [ram, repair, gate]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var exits := S.row(box, 5)
	resume = S.button(exits, "返回操控", resume_requested.emit, true)
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	S.button(exits, "投降", action_requested.emit.bind("surrender"))

func build_score(mission: BattleMission) -> void:
	score = ColorRect.new()
	score.color = Color("#0c100ec4")
	root.add_child(score)
	score.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := S.panel(score, true)
	S.pin(card, Vector2(0.5, 0.5), -425, -205, 850, 410)
	var box := S.stack(card, 12)
	S.label(box, mission.setup.settlement_id + "   /   交战中", 15, S.GOLD)
	S.label(box, "战场军报", 34, S.IVORY, true)
	S.rule(box)
	report_scroll = ScrollContainer.new()
	report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(report_scroll)
	report = Report.new()
	report_scroll.add_child(report)
	report.build(mission.setup.roster, false)
	S.label(box, "松开 Tab 返回战场", 15, S.MUTED)
	score.hide()

func toggle_score(pressed: bool) -> void:
	score.visible = pressed
	hud.visible = not pressed

func command_mode(active: bool, overview := false) -> void:
	commands.visible = active
	compact.visible = not active
	map_card.visible = active
	resume.visible = not overview
	reticle.visible = not active
	interaction.visible = not active
	notify_order("")
	if not active:
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

func notify_order(message: String) -> void:
	feedback.text = message
	feedback.visible = not message.is_empty()
	feedback_until = Time.get_ticks_msec() + 4500

func update_reticle(unit: BattleAgent, gesture: CommanderCombat.Direction, orders: bool, commanding: bool) -> void:
	pending_orders = orders
	if orders:
		orders_hint.text = "F1 到此坚守　 F2 跟随我　 F3 冲锋"
	else:
		orders_hint.text = "地面或沙盘选目标　·　Tab 军报" if commanding else "0–3 选队　 F1 军令　 Tab 军报　 Esc 指挥"
	reticle.visible = unit.alive() and not commanding
	var combat := unit.manual
	var committed := combat.winding or unit.guarding or combat.swing_time > 0
	var arrow: String = ["←", "→", "↑", "↓"][combat.direction if committed else gesture]
	reticle.text = "⚑" if orders else ("格 " if unit.guarding else "蓄 " if combat.winding else "") + arrow

func point_text(point: BattleSupply.Point, title: String, duration: float) -> String:
	var owner: String = ["中立", "我方", "敌方"][point.owner + 1]
	var progress := ""
	if point.contender >= 0:
		progress = " · %s占领 %d%%" % ["我方" if point.contender == 0 else "敌方", floori(100 * point.progress / duration)]
	if point.contested:
		progress += " · 争夺中"
	return "%s　%s%s" % [title, owner, progress]

func refresh(mission: BattleMission) -> void:
	var team := mission.teams[0]
	var unit := team.leader
	time_label.text = S.clock(mission.elapsed)
	banner_counts[0].text = "我方  %d" % team.last_strength
	banner_counts[1].text = "%d  敌方" % mission.teams[1].last_strength
	balance.max_value = maxi(1, team.last_strength + mission.teams[1].last_strength)
	balance.value = team.last_strength
	stats.text = "统领阵亡　·　指挥视角"
	if unit.alive():
		var gear := "单手剑" if unit.manual.drawn else "收剑"
		if unit.manual.shield:
			gear = "剑盾" if unit.manual.drawn else "持盾"
		stats.text = "统领　·　" + gear
	vitals.text = "生命　%d / %d" % [ceili(unit.hp), ceili(unit.spec.health)]
	durability.text = "盾耐久　%d / 100" % ceili(unit.manual.shield_hp)
	health.max_value = unit.spec.health
	health.value = unit.hp
	shield.value = unit.manual.shield_hp
	quick.text = ("移动军令" if pending_orders else "指挥") + "　·　" + picker.get_item_text(picker.selected)
	if not pending_orders and not commands.visible and picker.selected < team.groups.size():
		quick.text += "　/　" + BattleFormation.LABELS[team.groups[picker.selected].order]
	if not pending_orders and feedback.visible and Time.get_ticks_msec() > feedback_until:
		feedback.hide()
	if score.visible:
		report.refresh(mission)
	var key := mission.nearby_facility() if unit.alive() and not commands.visible else ""
	interaction.text = {"gate": "[ F ]  开关侧门", "repair": "[ F ]  维修正门", "ram": "[ F ]  建造攻城槌"}.get(key, "")
	var now := Time.get_ticks_msec()
	if now < next_details:
		return
	next_details = now + 100
	if map_card.is_visible_in_tree():
		field_map.queue_redraw()
	var lines := PackedStringArray()
	for i in mission.supply.points.size():
		var point := mission.supply.points[i]
		var title := point.title if i < 2 else ("我方广场" if i == 2 else "敌方广场")
		lines.append(point_text(point, title, mission.rules.capture_seconds))
	compact_points.text = lines[0] + "\n" + lines[1]
	supplies_brief.text = "粮 %d　木 %d　士气 %.0f" % [mission.supply.food[0], mission.supply.wood[0], team.morale]
	if team.pressure != "无持续压力":
		supplies_brief.text += "\n" + team.pressure
	points.text = "\n".join(lines)
	resources.text = "粮食 %d　木料 %d　·　%d 秒后补给\n士气 %.0f　·　%s" % [mission.supply.food[0], mission.supply.wood[0],
		ceili(mission.rules.supply_period - mission.supply.clock), team.morale, team.pressure]
	var fort := mission.field.forts[0]
	fort_detail.text = "正门 %.0f　·　侧门%s　·　%s" % [fort.gate_hp, "已开" if fort.side_open else "已闭", "槌耐久 %.0f" % fort.ram_hp if fort.ram_hp > 0 else "未部署槌"]
	fort_detail.text += "\n敌方正门耐久　%.0f" % mission.field.forts[1].gate_hp
	ram.text = "造槌 · %d木" % mission.rules.ram_cost
	repair.text = "修门 · %d木" % mission.rules.repair_cost
	gate.text = "关闭侧门" if fort.side_open else "打开侧门"
	var detail := PackedStringArray()
	for i in team.groups.size():
		if picker.selected != team.groups.size() and picker.selected != i:
			continue
		var squad := team.groups[i]
		var order_name: String = "护槌" if squad.escort else BattleFormation.LABELS[squad.order]
		var state := "%s %d　%s　到位%d 交战%d 受阻%d" % [squad.title, squad.strength(), order_name, squad.arrived, squad.engaged, squad.blocked]
		if not squad.notice.is_empty():
			state += "　" + squad.notice
		detail.append(state)
	group_detail.text = "\n".join(detail)
