extends Control
## A thin local launcher. Buttons invoke GameSession or the composition entry points.
const PAPER := Color("#eee9d8")
const INK := Color("#24332e")
const ACCENT := Color("#79422d")
signal field_requested
var _root: RefCounted
var _status: Label
var _title: Label
var _slot: LineEdit
var _buttons := {}
var _area: VBoxContainer

func _label(caption: String, size: int, color: Color=INK) -> Label:
	var label:=Label.new()
	label.text=caption
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	return label

func _layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var paper:=ColorRect.new()
	paper.color=PAPER
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin:=MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,52 if side in ["left","right"] else 36)
	_area=VBoxContainer.new()
	_area.add_theme_constant_override("separation",14)
	margin.add_child(_area)
	_area.add_child(_label("Recollection",21,ACCENT))

func _button(row: HBoxContainer, id: String, caption: String, action: Callable) -> void:
	var button:=Button.new()
	button.text=caption
	button.custom_minimum_size=Vector2(130,40)
	button.pressed.connect(action)
	row.add_child(button)
	_buttons[id]=button

func _row() -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	_area.add_child(row)
	return row

func mount(context: RefCounted) -> void:
	_root=context
	_layout()
	_title=_label("",38)
	_area.add_child(_title)
	_area.add_child(_label("存档槽",16))
	_slot=LineEdit.new()
	_slot.text="campaign"
	_slot.placeholder_text="字母、数字、下划线或连字符"
	_slot.tooltip_text="使用字母、数字、下划线或连字符，最多 64 个字符。"
	_area.add_child(_slot)
	var files:=_row()
	_button(files,"new","新建沙盒",func(): _display(_root.new_world(_slot.text)))
	_button(files,"load","读取存档",func(): _display(_root.load_world(_slot.text)))
	_button(files,"save","保存进度",func(): _display(_root.session().save_session()))
	_button(files,"resume","继续待结算战果",func(): _display(_root.resume_result()))
	_area.add_child(HSeparator.new())
	_area.add_child(_label("河滩练兵场",24))
	var training:=_row()
	_button(training,"field","进入河原野战",func():field_requested.emit())
	_button(training,"train","进入训练",func(): _display(_root.start_training()))
	_button(training,"leave","结束训练",func(): _display(_root.session().dispose_mission()))
	_button(training,"close","关闭会话",func(): _display(_root.session().close_session("frontend")))
	_status=_label("",16,ACCENT)
	_area.add_child(_status)
	_refresh()

func _display(reply: Dictionary) -> void:
	_status.text="操作完成" if reply.ok else "%s · %s"%[reply.error.code,reply.error.field]
	_refresh()

func _refresh() -> void:
	var state: String=_root.session().query().value.state
	_title.text={"Frontend":"主菜单","CampaignMap":"沙盒世界","CustomSetup":"自定义训练","Mission":"训练中"}.get(state,state)
	_buttons.new.disabled=state!="Frontend"
	_buttons.load.disabled=state!="Frontend"
	_buttons.save.disabled=state!="CampaignMap"
	_buttons.resume.visible=state=="Results" and _root.pending_result().ok
	_buttons.field.disabled=state not in ["Frontend","CampaignMap","CustomSetup"]
	_buttons.train.disabled=state not in ["Frontend","CampaignMap","CustomSetup"]
	_buttons.leave.disabled=state!="Mission"
	_buttons.close.disabled=state=="Frontend"

func field_closed(reply: Dictionary) -> void:
	show()
	_display(reply)

func show_failure(error: Dictionary, retry: Callable) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_layout()
	_area.add_child(_label("启动失败",34))
	_area.add_child(_label("%s · %s"%[error.code,error.field],20))
	_button(_row(),"retry","重新启动",retry)
