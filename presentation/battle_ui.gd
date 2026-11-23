class_name BattleUI extends CanvasLayer
## 菜单、HUD 和结算共用此视图；按钮发送意图，业务状态从 Mission 读取。
signal start_requested(guards: int)
signal menu_requested
signal ordered(order: BattleFormation.Order)
signal action_requested(action: String)
var root := Control.new()
var stats: Label
var feedback: Label
var picker: OptionButton
var garrison: SpinBox
var commands: Control
var facilities: Control
var hint: Label

func _ready() -> void:
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

func clear() -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()

func panel(offset: Vector2, centered := false) -> VBoxContainer:
	var box := PanelContainer.new()
	root.add_child(box)
	if centered:
		box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position += offset
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	box.add_child(margin)
	var stack := VBoxContainer.new()
	margin.add_child(stack)
	return stack

func label(parent: Control, value: String, size := 16) -> Label:
	var line := Label.new()
	line.text = value
	line.add_theme_font_size_override("font_size", size)
	parent.add_child(line)
	return line

func button(parent: Control, title: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	parent.add_child(b)

func menu() -> void:
	clear()
	var stack := panel(Vector2(-175, -110), true)
	label(stack, "双城争夺战", 32)
	label(stack, "守门步兵人数（共 18 名步兵）")
	garrison = SpinBox.new()
	garrison.min_value = 1
	garrison.max_value = 17
	garrison.value = 8
	stack.add_child(garrison)
	label(stack, "三国场景与角色 · Polyfork（已调整模型与服色）", 13)
	for item in [["Three Kingdoms Settlements", "https://polyfork.dev/kit/three-kingdoms-settlements-a-1e817b"],
			["CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"]]:
		var link := LinkButton.new()
		link.text = item[0]
		link.uri = item[1]
		link.add_theme_font_size_override("font_size", 13)
		stack.add_child(link)
	button(stack, "进入战场", func(): start_requested.emit(int(garrison.value)))

func battle(team: BattleTeam) -> void:
	clear()
	var top := panel(Vector2(10, 8))
	stats = label(top, "")
	var bottom := panel(Vector2(10, 0))
	var bg := bottom.get_parent().get_parent() as Control
	bg.anchor_top = 1
	bg.anchor_bottom = 1
	bg.offset_top = -177
	bg.offset_bottom = -8
	var orders := HBoxContainer.new()
	commands = orders
	bottom.add_child(orders)
	picker = OptionButton.new()
	orders.add_child(picker)
	for group in team.groups:
		picker.add_item(group.title)
	for code in BattleFormation.LABELS.size():
		button(orders, BattleFormation.LABELS[code], ordered.emit.bind(code))
	var tools := HBoxContainer.new()
	facilities = tools
	bottom.add_child(tools)
	for entry in [["建造攻城槌", "ram"], ["修正门", "repair"], ["开关侧门", "gate"], ["投降", "surrender"]]:
		button(tools, entry[0], action_requested.emit.bind(entry[1]))
	feedback = label(bottom, "点击地面选目标，然后下令")
	hint = label(bottom, "", 14)

func command_mode(active: bool) -> void:
	commands.visible = active
	facilities.visible = active
	feedback.visible = active
	var panel_root := hint.get_parent().get_parent().get_parent() as Control
	panel_root.offset_top = -177 if active else -54
	hint.text = "点击地面选目标 · 选择小队并下令 · Tab 切换操控" if active else "WASD 移动 · 鼠标环视 · 左键攻击 · 右键格挡 · Tab 小队指挥"

func refresh(mission: BattleMission) -> void:
	var team := mission.teams[0]
	var group := team.groups[picker.selected]
	var fort := mission.field.forts[0]
	var owner := ["中立", "我方", "敌方"]
	stats.text = "我方 %d 人　敌方 %d 人　粮 %d　木 %d　士气 %.0f（%s）　%s\n" % [
		team.last_strength, mission.teams[1].last_strength, mission.supply.food[0], mission.supply.wood[0],
		team.morale, team.pressure, "统领 HP %.0f" % team.leader.hp if team.leader.alive() else "指挥视角"]
	stats.text += "%s · %s　存活 %d　到位 %d　交战 %d　受阻 %d\n" % [
		group.title, BattleFormation.LABELS[group.order], group.strength(), group.arrived, group.engaged, group.blocked]
	stats.text += "粮仓 %s　伐木场 %s　正门 %.0f　侧门%s　攻城槌 HP %.0f" % [
		owner[mission.supply.points[0].owner + 1], owner[mission.supply.points[1].owner + 1],
		fort.gate_hp, "开" if fort.side_open else "闭", fort.ram_hp]
	if group.escort != null:
		stats.text += "　正在护槌"
	elif not group.notice.is_empty():
		stats.text += "　" + group.notice

func summary(result: Dictionary) -> void:
	clear()
	var stack := panel(Vector2(-175, -175), true)
	label(stack, "胜利" if result.winner == 0 else "战败", 32)
	label(stack, "%s　·　用时 %.0f 秒" % [result.reason, result.elapsed])
	for row in result.roster:
		label(stack, "%s %s　幸存 %d　阵亡 %d" % ["我方" if row.side == 0 else "敌方", row.title, row.survivors, row.losses], 14)
	button(stack, "返回主菜单", menu_requested.emit)
