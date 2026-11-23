extends RefCounted
## 双城界面的军旗色、铜边面板与文字层级。所有控件都使用 Godot 原生布局和焦点。
const INK := Color("#191b1af3")
const EDGE := Color("#766448")
const GOLD := Color("#e4c28a")
const IVORY := Color("#f4edda")
const MUTED := Color("#cdc5ae")
const BLUE := Color("#68b5b7")
const RED := Color("#d38973")
const Banner := preload("res://presentation/ui/war_banner.gd")

static func banner(parent: Control, extent: Vector2, enemy := false) -> void:
	var flag := Banner.new()
	flag.custom_minimum_size = extent
	if enemy:
		flag.cloth = Color("#783f34")
	parent.add_child(flag)

static func plate(fill: Color, edge: Color, pad := 9) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		box.set_content_margin(side, pad)
	return box

static func theme() -> Theme:
	var skin := Theme.new()
	skin.default_font_size = 16
	var body_font := SystemFont.new()
	body_font.font_names = PackedStringArray(["Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC"])
	skin.default_font = body_font
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["KaiTi", "STKaiti", "Noto Serif CJK SC", "SimSun"])
	skin.set_type_variation(&"WarTitle", &"Label")
	skin.set_font(&"font", &"WarTitle", title_font)
	skin.set_color(&"font_color", &"Label", IVORY)
	skin.set_stylebox(&"panel", &"PanelContainer", plate(INK, EDGE, 14))
	for type: StringName in [&"Button", &"OptionButton", &"LineEdit"]:
		skin.set_stylebox(&"normal", type, plate(Color("#33342e"), EDGE, 8))
		skin.set_stylebox(&"hover", type, plate(Color("#505040"), GOLD, 8))
		skin.set_stylebox(&"pressed", type, plate(Color("#5c4d32"), GOLD, 8))
		var focus := plate(Color.TRANSPARENT, GOLD, 8)
		focus.draw_center = false
		focus.set_border_width_all(2)
		skin.set_stylebox(&"focus", type, focus)
		skin.set_color(&"font_color", type, IVORY)
	skin.set_stylebox(&"panel", &"PopupMenu", plate(INK, EDGE))
	skin.set_stylebox(&"hover", &"PopupMenu", plate(Color("#504734"), GOLD, 4))
	return skin

static func pin(node: Control, anchor: Vector2, x: float, y: float, w: float, h: float) -> void:
	node.anchor_left = anchor.x
	node.anchor_right = anchor.x
	node.anchor_top = anchor.y
	node.anchor_bottom = anchor.y
	node.offset_left = x
	node.offset_top = y
	node.offset_right = x + w
	node.offset_bottom = y + h

static func label(parent: Control, value: String, px := 16, tint := IVORY, title := false) -> Label:
	var out := Label.new()
	if title:
		out.theme_type_variation = &"WarTitle"
	out.text = value
	out.add_theme_font_size_override("font_size", px)
	out.add_theme_color_override("font_color", tint)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(out)
	return out

static func stack(parent: Control, gap := 6) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

static func row(parent: Control, gap := 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

static func rule(parent: Control) -> void:
	var line := ColorRect.new()
	line.color = Color("#847050")
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

static func panel(parent: Control, interactive := false) -> PanelContainer:
	var out := PanelContainer.new()
	out.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	parent.add_child(out)
	return out

static func button(parent: Control, title: String, pressed: Callable, primary := false) -> Button:
	var out := Button.new()
	out.text = title
	if primary:
		out.add_theme_stylebox_override("normal", plate(Color("#a68049"), Color("#edcf8c"), 10))
		out.add_theme_color_override("font_color", Color("#191b19"))
	out.pressed.connect(pressed)
	parent.add_child(out)
	return out

static func meter(parent: Control, tint: Color, track := Color("#3e3a32")) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 7
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", plate(track, track, 0))
	bar.add_theme_stylebox_override("fill", plate(tint, tint, 0))
	parent.add_child(bar)
	return bar

static func clock(seconds: float) -> String:
	var total := floori(seconds)
	return "%02d:%02d" % [floori(total / 60.0), total % 60]
