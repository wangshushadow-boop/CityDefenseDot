extends Control
## 部署页、操作手册和终局战报。开局人数通过信号交给应用，战报只读终局快照。
const S := preload("res://presentation/ui/war_style.gd")
const Report := preload("res://presentation/ui/troop_report.gd")
const ART := preload("res://presentation/ui/river_pass.png")
signal deploy(guards: int)
signal return_requested
var garrison: SpinBox
var detail: Control
var main: Control

func backdrop() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var art := TextureRect.new()
	art.texture = ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := GradientTexture2D.new()
	shade.gradient = Gradient.new()
	shade.gradient.offsets = PackedFloat32Array([0, 0.33, 0.65, 1])
	shade.gradient.colors = PackedColorArray([Color("#101919f4"), Color("#141d1dbd"), Color("#16191424"), Color("#1919110a")])
	shade.fill_to = Vector2.RIGHT
	var veil := TextureRect.new()
	veil.texture = shade
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func deployment(setup: BattleSetup) -> void:
	backdrop()
	var body := S.stack(self, 15)
	main = body
	S.pin(body, Vector2(0, 0.5), 64, -263, 420, 526)
	var location := S.row(body, 11)
	S.banner(location, Vector2(32, 43))
	S.label(location, "双城关   /   河谷战场", 17, S.GOLD)
	S.label(body, "双城争夺战", 65, S.IVORY, true)
	S.label(body, "争夺粮木，迫降或全歼敌军。", 20)
	S.rule(body)
	S.label(body, "战前部署", 29, S.GOLD, true)
	var select := S.row(body)
	var label := S.label(select, "留守城门的步兵", 18)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garrison = SpinBox.new()
	var counts := {}
	for entry in setup.roster:
		if entry.side == 0:
			counts[entry.role] = entry.count
	var infantry: int = counts.guard + counts.field
	garrison.custom_minimum_size.x = 96
	garrison.min_value = 1
	garrison.max_value = infantry - 1
	garrison.value = counts.guard
	garrison.update_on_text_changed = true
	select.add_child(garrison)
	var count := S.label(body, "", 16, S.MUTED)
	var describe := func(value: float):
		count.text = "出城步兵 %d     弓兵 %d     统领 %d     合计 %d 人" % [infantry - int(value),
			counts.bow, counts.leader, infantry + counts.bow + counts.leader]
	describe.call(garrison.value)
	garrison.value_changed.connect(describe)
	var start := S.button(body, "领军出征", func(): deploy.emit(int(garrison.value)), true)
	start.name = "Deploy"
	start.custom_minimum_size.y = 52
	var links := S.row(body)
	for title in ["操作手册", "素材署名"]:
		var button := S.button(links, title, show_detail.bind(title))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func show_detail(title: String) -> void:
	if detail:
		return
	main.hide()
	var card := S.panel(self, true)
	detail = card
	S.pin(card, Vector2(0, 0.5), 64, -254, 556, 508)
	var body := S.stack(card, 12)
	S.label(body, title, 32, S.GOLD, true)
	S.rule(body)
	if title == "操作手册":
		for pair in [
			["移动", "WASD 移动　空格 跳跃　Z 蹲姿　Caps Lock 走跑"],
			["剑盾", "鼠标选方向，按住左键准备、松开挥击。右键格挡或取消出招。E 踢击，举盾时 E 盾击。"],
			["装备", "向上滚轮拔剑，向下滚轮切盾，反斜杠收拔剑。"],
			["观察", "R 切换视角　Shift 变焦　中键锁敌　反引号自由观察"],
			["军令", "0 全军，1 出城步兵，2 弓兵，3 守门步兵。按 F1 后，再按 F1 坚守、F2 跟随、F3 冲锋。"],
			["战场", "F 操作设施　Alt 显示据点　Tab 战况　Esc 指挥面板"]]:
			var line := S.row(body, 15)
			S.label(line, pair[0], 17, S.GOLD)
			var value := S.label(line, pair[1], 16)
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		S.label(body, "三国城池与角色模型", 22)
		S.label(body, "Polyfork · 已调整服色、比例与门轴。", 16, S.MUTED)
		for entry in [["Three Kingdoms Settlements", "https://polyfork.dev/kit/three-kingdoms-settlements-a-1e817b"], ["Creative Commons BY 4.0", "https://creativecommons.org/licenses/by/4.0/"]]:
			var link := LinkButton.new()
			link.text = entry[0]
			link.uri = entry[1]
			body.add_child(link)
		S.label(body, "河谷军阵背景使用 ImageGen 生成。", 16, S.MUTED)
		S.label(body, "野外网格来自 CityDefenseGodot 的河谷场景。", 16, S.MUTED)
	S.button(body, "返回部署", close_detail)

func close_detail() -> void:
	remove_child(detail)
	detail.queue_free()
	detail = null
	main.show()

func _unhandled_key_input(event: InputEvent) -> void:
	if detail and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_detail()
		get_viewport().set_input_as_handled()

func summary(result: Dictionary) -> void:
	backdrop()
	var card := S.panel(self, true)
	S.pin(card, Vector2(0.5, 0.5), -425, -249, 850, 498)
	var body := S.stack(card, 12)
	S.label(body, "%s   /   战报" % result.settlement_id, 16, S.GOLD)
	S.label(body, "战斗胜利" if result.winner == 0 else "战斗失利", 44, S.IVORY, true)
	S.label(body, "%s　 ·　历时 %s　 ·　%s取得%s" % [result.reason, S.clock(result.elapsed),
		"我方" if result.settlement_owner == 0 else "敌方", result.settlement_id], 17)
	S.rule(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var report := Report.new()
	scroll.add_child(report)
	report.build(result.roster, true)
	S.button(body, "返回战前部署", return_requested.emit, true)
