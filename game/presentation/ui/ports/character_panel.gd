extends PanelContainer
## Character commands go through the active campaign authority. Controls only keep selection state.
signal closed
const INK := Color("#172d29")
const FIELD := Color("#263f38")
const PAPER := Color("#f2e5ce")
const MUTED := Color("#c9c9b3")
const GOLD := Color("#e5b974")
const GROUPS := {"culture":"文化","childhood":"童年","occupation":"早年行当","identity":"开局身份","appearance":"外观","banner":"家纹"}
const STATES := {"Healthy":"健康","Wounded":"受伤","Captive":"被俘","Dead":"已故","Retired":"隐退"}
const SCOPE := {"self":"自身","captain":"队长","party":"队伍","army":"军团","settlement":"领地","clan":"家族"}
const ERRORS := {"InvalidArgument":"所选内容不合法","InvalidState":"当前状态无法执行","InsufficientResource":"可用资源不足","Unauthorized":"当前人物没有操作权限","StaleVersion":"人物资料已更新，请重新选择","Conflict":"选择与现有状态冲突","NotFound":"未找到所选内容","Unavailable":"服务暂时不可用"}

var _read: Callable
var _write: Callable
var _model := {}
var _section := "growth"
var _skill := "one_handed"
var _profile := "combat"
var _slot := "main_hand"
var _head: Label
var _notice: Label
var _body: VBoxContainer
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _creation := {}
var _confirm: ConfirmationDialog
var _portrait: SubViewportContainer
var _portrait_id := ""
var _pending := {}

class AimRange extends Control:
	signal shot(point: Array)
	var target:=Vector2i.ZERO
	var radius:=0
	var cursor:=Vector2i(500,500)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("#3a5144"))
		var center:=Vector2(target)*size/1000.0
		# The board is square. Its painted outer edge is the authoritative hit radius.
		var outer:=radius*size.x/1000.0
		draw_circle(center,outer,Color("#e6cf9f"),true,-1.0,true)
		draw_circle(center,outer*.68,Color("#934d37"),true,-1.0,true)
		draw_circle(center,outer*.3,Color("#e7c072"),true,-1.0,true)
		if has_focus():
			draw_rect(Rect2(Vector2.ONE,size-2*Vector2.ONE),Color("#d4b06e"),false,2.0)
			var point:=Vector2(cursor)*size/1000.0
			draw_line(point-Vector2(6,0),point+Vector2(6,0),Color.WHITE,1.5)
			draw_line(point-Vector2(0,6),point+Vector2(0,6),Color.WHITE,1.5)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			grab_focus()
			var point:=Vector2i((event.position*1000.0/size).round()).clamp(Vector2i.ZERO,Vector2i(1000,1000))
			accept_event()
			shot.emit([point.x,point.y])
			return
		if not has_focus(): return
		if event.is_action_pressed("ui_accept"):
			accept_event()
			shot.emit([cursor.x,cursor.y])
			return
		var motions:={"ui_left":Vector2i.LEFT,"ui_right":Vector2i.RIGHT,"ui_up":Vector2i.UP,"ui_down":Vector2i.DOWN}
		for action in motions:
			if event.is_action_pressed(action,true):
				cursor=(cursor+25*Vector2i(motions[action])).clamp(Vector2i.ZERO,Vector2i(1000,1000))
				accept_event()
				queue_redraw()
				return

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=color
	return style

func _label(parent: Node, caption: String, size: int=17, color: Color=PAPER) -> Label:
	var label:=Label.new()
	label.text=caption
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _row(parent: Node) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	return row

func _field_label(form: GridContainer, title: String) -> void:
	var label:=_label(form,title)
	label.autowrap_mode=TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	label.custom_minimum_size.x=92

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var btn:=Button.new()
	btn.text=caption
	btn.custom_minimum_size.y=36
	btn.pressed.connect(action)
	parent.add_child(btn)
	return btn

func _choices(parent: Node, labels: Dictionary, chosen: String, on_select: Callable=Callable()) -> OptionButton:
	var widget:=OptionButton.new()
	widget.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for id in labels:
		widget.add_item(str(labels[id]))
		var index:=widget.item_count-1
		widget.set_item_metadata(index,id)
		if chosen==id: widget.select(index)
	parent.add_child(widget)
	if on_select.is_valid():
		widget.item_selected.connect(func(index): on_select.call(widget.get_item_metadata(index)))
	return widget

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func mount(model: Dictionary, read: Callable, write: Callable) -> void:
	_model=model
	_read=read
	_write=write
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel",_style(INK))
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,24 if side in ["left","right"] else 16)
	add_child(margin)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	margin.add_child(column)
	var header:=_row(column)
	_head=_label(header,"",28,GOLD)
	_button(header,"返回沙盒",func(): closed.emit())
	_tabs=_row(column)
	column.add_child(HSeparator.new())
	_scroll=ScrollContainer.new()
	_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_scroll.follow_focus=true
	column.add_child(_scroll)
	_body=VBoxContainer.new()
	_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation",8)
	_scroll.add_child(_body)
	_notice=_label(column,"",16,GOLD)
	_notice.visible=false
	_render()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel") and not is_instance_valid(_confirm):
		get_viewport().set_input_as_handled()
		closed.emit()

func _show_notice(message: String) -> void:
	_notice.text=message
	_notice.visible=not message.is_empty()

func _submit(op: String, args: Dictionary, success: String) -> void:
	if _pending.is_empty() or _pending.op!=op or _pending.args!=args or _pending.revision!=_model.revision:
		_pending={"op":op,"args":args.duplicate(true),"revision":_model.revision,
			"id":"character/"+Crypto.new().generate_random_bytes(16).hex_encode()}
	var reply: Dictionary=_write.call(op,args,_model.revision,_pending.id)
	if reply.ok or not reply.error.retryable: _pending.clear()
	if not reply.ok:
		var field: String=reply.error.field
		_show_notice("%s（%s）"%[ERRORS.get(reply.error.code,"操作失败"),field])
		if reply.error.code!="StaleVersion": return
	else:
		_show_notice(success)
	var fresh: Dictionary=_read.call()
	if not fresh.ok:
		_show_notice(ERRORS.get(fresh.error.code,"人物资料读取失败"))
		return
	if op=="practice" and reply.ok:
		var last: Dictionary=fresh.value.get("last_practice",{})
		if last.has("correct"):
			if last.correct:
				var lead: String="命中靶圈" if args.has("aim") else "研习成功"
				var advanced: bool=_model.hero.skills[args.skill]!=fresh.value.hero.skills[args.skill]
				_show_notice(lead+("，技能经验已增长。" if advanced else "，本次未再获得经验。"))
			else:
				_show_notice("未命中靶圈，已过去一刻。" if args.has("aim") else "本次研习答错，已过去一刻。")
	_model=fresh.value
	_render()

func _render() -> void:
	_clear(_tabs)
	_clear(_body)
	_portrait=null
	_portrait_id=""
	if _model.ended:
		_head.text="生涯已结束"
		_label(_body,"本次人物生涯已结束，仍可返回主菜单读取其他存档。")
		return
	if _model.hero==null:
		_head.text="创建人物"
		_create_form()
		return
	var hero: Dictionary=_model.hero
	_head.text="%s　·　人物志"%hero.name
	var titles := {"growth":"身世与成长","gear":"行装","family":"家人和继承"}
	if hero.life_status=="Dead": _section="family"
	for key in titles:
		var tab:=_button(_tabs,titles[key],_set_section.bind(key))
		tab.disabled=key==_section or (hero.life_status=="Dead" and key!="family")
	match _section:
		"growth": _growth(hero)
		"gear": _equipment()
		"family": _household(hero)

func _set_section(section: String) -> void:
	_section=section
	_scroll.scroll_vertical=0
	_show_notice("")
	_render()

func _create_form() -> void:
	var catalog: Dictionary=_model.catalog
	if _creation.is_empty(): _creation=catalog.defaults.duplicate(true)
	var record:=_row(_body)
	var portrait_column:=VBoxContainer.new()
	portrait_column.custom_minimum_size.x=150
	record.add_child(portrait_column)
	_preview(portrait_column,_creation.appearance)
	var form:=GridContainer.new()
	form.columns=2
	form.add_theme_constant_override("h_separation",12)
	form.add_theme_constant_override("v_separation",5)
	form.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	record.add_child(form)
	_field_label(form,"姓名")
	var who:=LineEdit.new()
	who.name="HeroName"
	who.text=_creation.name
	who.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	who.text_changed.connect(func(value): _creation.name=value)
	form.add_child(who)
	_field_label(form,"年龄")
	var age:=SpinBox.new()
	age.min_value=catalog.age_min
	age.max_value=catalog.age_max
	age.value=_creation.age
	age.value_changed.connect(func(value): _creation.age=roundi(value))
	form.add_child(age)
	for key in GROUPS:
		_field_label(form,GROUPS[key])
		var selected:=_choices(form,catalog.options[key],_creation[key],_choose_background.bind(key,portrait_column))
		selected.name=key.capitalize()
	_button(_body,"确立身世",func(): _submit("create",_creation.duplicate(true),"人物已建立并存档。"))
	who.grab_focus()

func _choose_background(value: String, key: String, portrait_column: VBoxContainer) -> void:
	_creation[key]=value
	if key=="appearance": _preview(portrait_column,value)

func _preview(parent: Node, id: String) -> void:
	if _portrait_id==id and is_instance_valid(_portrait): return
	if is_instance_valid(_portrait):
		parent.remove_child(_portrait)
		_portrait.queue_free()
	_portrait_id=id
	_portrait=SubViewportContainer.new()
	_portrait.name="AppearancePreview"
	_portrait.custom_minimum_size=Vector2(148,164)
	_portrait.stretch=true
	_portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(_portrait)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(148,164)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	_portrait.add_child(viewport)
	var world:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=FIELD
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color.WHITE
	env.ambient_light_energy=0.85
	world.environment=env
	viewport.add_child(world)
	var filename: String={"reed":"spear_soldier","pine":"general","plum":"crossbowman"}.get(id,"spear_soldier")
	var resource:=load("res://content/base/field/models/%s.glb"%filename) as PackedScene
	if resource==null: return
	var figure:=resource.instantiate() as Node3D
	viewport.add_child(figure)
	var players:=figure.find_children("*","AnimationPlayer",true,false)
	if not players.is_empty() and players[0].has_animation("Idle"):
		var player:=players[0] as AnimationPlayer
		player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.play("Idle")
		player.advance(0.18)
	var material:=StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.vertex_color_is_srgb=true
	var bounds:=AABB()
	for mesh: MeshInstance3D in figure.find_children("*","MeshInstance3D",true,false):
		var part:=str(mesh.name)
		if part.begins_with("attach-") or part in ["garment-quiver","garment-armour"] or (id!="pine" and part in ["garment-helmet","garment-hat"]):
			mesh.hide()
			continue
		mesh.material_override=material
		if part=="garment-tunic":
			var dye:=StandardMaterial3D.new()
			dye.albedo_color={"reed":Color("#65948b"),"pine":Color("#475149"),"plum":Color("#a1494c")}.get(id,FIELD)
			mesh.material_override=dye
		var box: AABB=mesh.global_transform*mesh.get_aabb()
		bounds=box if not bounds.has_volume() else bounds.merge(box)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=maxf(bounds.size.y,bounds.size.x)*1.12
	var target:=bounds.get_center()
	viewport.add_child(camera)
	camera.position=target+Vector3(0.28,0.08,1.0).normalized()*maxf(3.0,bounds.size.length()*1.7)
	camera.look_at(target)
	var lamp:=DirectionalLight3D.new()
	lamp.rotation_degrees=Vector3(-42,-34,0)
	viewport.add_child(lamp)

func _growth(hero: Dictionary) -> void:
	var row:=_row(_body)
	var art:=VBoxContainer.new()
	row.add_child(art)
	_preview(art,hero.appearance)
	var bio:=VBoxContainer.new()
	bio.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(bio)
	var info: Dictionary=_model.catalog.options
	_label(bio,"%s　·　%s岁　·　等级 %s"%[info.culture[hero.culture],hero.age,hero.level],23,GOLD)
	_label(bio,"%s　/　%s　/　%s"%[info.childhood[hero.childhood],info.occupation[hero.occupation],info.identity[hero.identity]])
	_label(bio,"%s家纹　·　%s　·　伤势 %d　·　第 %d 天"%[info.banner[hero.banner],STATES.get(hero.life_status,hero.life_status),hero.wounds,_model.day])
	if hero.wounds>0 and hero.get("cause","")!="":
		_label(bio,"伤势来源　"+str(hero.cause),15,MUTED)
	var attributes:=PackedStringArray()
	for key in _model.catalog.attributes:
		attributes.append("%s %s"%[_model.catalog.attributes[key],hero.attributes[key]])
	_label(bio,"　".join(attributes),15,MUTED)
	_label(_body,"研习与专精",21,GOLD)
	var row_skills:=_row(_body)
	var choices: Dictionary={}
	for key in _model.catalog.skills: choices[key]=_model.catalog.skills[key].label
	_choices(row_skills,choices,_skill,func(value): _skill=value; _render()).name="SkillChoice"
	var skill: Dictionary=hero.skills[_skill]
	_label(row_skills,"等级 %s　经验 %s/%s　专精 %s　学习软限 %s"%[skill.level,skill.xp,skill.next_xp,skill.focus,skill.soft_cap],15)
	if hero.get("focus_points",0)>0:
		_button(_body,"投入专精点（余 %d）"%hero.focus_points,func(): _submit("focus",{"skill":_skill},"专精已提升。"))
	if hero.life_status=="Healthy" and _model.practice.has(_skill):
		var drill: Dictionary=_model.practice[_skill]
		_label(_body,drill.prompt)
		if drill.get("kind")=="aim":
			_aim_field(drill)
		else:
			var answers:=_row(_body)
			for index in drill.options.size():
				var choice:=_button(answers,drill.options[index],_submit.bind("practice",{"skill":_skill,"answer":index},"研习已结算。"))
				choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(_body,"天赋",21,GOLD)
	var available: Array=hero.available_perks
	for id in _model.catalog.perks:
		var perk: Dictionary=_model.catalog.perks[id]
		if perk.skill!=_skill: continue
		var picked: bool=id in hero.perks
		var desc: String="%s　·　%s　+%s　·　须达 %s 级"%[perk.label,SCOPE.get(perk.scope,perk.scope),perk.bonus,perk.level]
		if picked: desc+="　已习得"
		else:
			for selected in hero.perks:
				if _model.catalog.perks[selected].group==perk.group:
					desc+="　与「%s」互斥"%_model.catalog.perks[selected].label
					break
		var item:=_button(_body,desc,_submit.bind("perk",{"perk":id},"天赋已习得。"))
		item.disabled=picked or id not in available
	for scope in hero.effects:
		for effect_skill in hero.effects[scope]:
			var effect: Dictionary=hero.effects[scope][effect_skill]
			if effect.get("bonus",0)==0: continue
			var sources:=PackedStringArray()
			for source in effect.sources:
				sources.append(_model.catalog.perks[source].label)
			var title: String=_model.catalog.skills.get(effect_skill,{}).get("label",effect_skill)
			_label(_body,"%s　%s +%d　·　%s"%[SCOPE.get(scope,scope),title,effect.bonus,"、".join(sources)],15,MUTED)
	_button(_body,"休养一日",_submit.bind("rest",{},"休养一日，人物状态已更新。"))

func _aim_field(drill: Dictionary) -> void:
	var row:=_row(_body)
	var board:=AimRange.new()
	board.name="PracticeTarget"
	board.custom_minimum_size=Vector2(196,196)
	board.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	board.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	board.focus_mode=Control.FOCUS_ALL
	board.mouse_default_cursor_shape=Control.CURSOR_CROSS
	board.target=Vector2i(drill.target[0],drill.target[1])
	board.radius=drill.radius
	board.focus_entered.connect(board.queue_redraw)
	board.focus_exited.connect(board.queue_redraw)
	board.shot.connect(func(point):
		_submit("practice",{"skill":_skill,"aim":point},"投射已结算。")
		var next:=_body.find_child("PracticeTarget",true,false) as Control
		if next!=null: next.grab_focus())
	row.add_child(board)
	_label(row,"点击靶圈投射。使用键盘或手柄时，先选中靶场，再用方向键移动准星，按确认键投射。",16,MUTED)

func _equipment() -> void:
	var gear: Dictionary=_model.gear
	var row:=_row(_body)
	_choices(row,{"combat":"战斗装束","civil":"便装"},_profile,func(value): _profile=value; _slot="main_hand"; _render())
	var slots: Dictionary=gear.profiles[_profile]
	var labels: Dictionary={}
	for key in slots: labels[key]=gear.slot_labels[key]
	_choices(row,labels,_slot,func(value): _slot=value; _render())
	var worn: String=slots[_slot]
	_label(_body,"已穿戴　%s"%("无" if worn=="" else gear.items[worn].label),22,GOLD)
	if worn!="" and _model.hero.life_status not in ["Captive","Retired","Dead"]:
		var worn_item: Dictionary=gear.items[worn]
		if worn_item.get("removable",true):
			_button(_body,"卸下装备",_submit.bind("equip",{"profile":_profile,"slot":_slot,"item_id":""},"装备已退回行囊。"))
		else:
			_label(_body,str(worn_item.remove_reason),16,MUTED)
	_label(_body,"行囊",20,GOLD)
	var found:=false
	for item in gear.bag:
		for choice in item.options:
			if choice.profile!=_profile or choice.slot!=_slot: continue
			found=true
			var line:=_row(_body)
			var requirements: String=item.requirements
			var caption: String=item.label+"（家产）" if item.ownership=="family" else item.label
			if requirements!="": caption+="　·　"+requirements
			if not choice.allowed and choice.reason!="": caption+="　·　"+str(choice.reason)
			_label(line,caption)
			var equip:=_button(line,"穿戴",_submit.bind("equip",{"profile":_profile,"slot":_slot,"item_id":item.item_id},"装束已更新。"))
			equip.disabled=not choice.allowed
	if not found: _label(_body,"行囊中没有此栏位的装备。",16,MUTED)

func _household(hero: Dictionary) -> void:
	_label(_body,"家人",22,GOLD)
	for member in _model.family:
		_label(_body,"%s　·　%s"%[member.name,STATES.get(member.life_status,member.life_status)])
	if hero.life_status=="Captive":
		_label(_body,"解除囚禁后才能安排退休。",16,MUTED)
		return
	_label(_body,"继任人",22,GOLD)
	var labels: Dictionary={}
	for heir in _model.heirs: labels[heir.id]=heir.name
	labels[""]="结束本次生涯"
	var choose:=_choices(_body,labels,labels.keys()[0])
	_button(_body,"选择继任人" if hero.life_status=="Dead" else "安排退休",func():
		var id: String=choose.get_item_metadata(choose.selected)
		var decision: String="由%s接任并接收家产装备。"%labels[id] if id!="" else "结束本次生涯。"
		var dialog:=ConfirmationDialog.new()
		_confirm=dialog
		dialog.title="确认生涯交接"
		dialog.dialog_text=decision+" 此操作将写入当前存档。"
		dialog.ok_button_text="确认交接"
		dialog.cancel_button_text="再考虑"
		add_child(dialog)
		dialog.confirmed.connect(func(): _submit("retire",{"heir_id":id},"生涯交接已记录。"))
		dialog.visibility_changed.connect(func():
			if not dialog.visible: dialog.queue_free())
		dialog.popup_centered())
