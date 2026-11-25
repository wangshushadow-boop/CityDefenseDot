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
var _visit_page := "roster"
var _visit_person := ""
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
		if _section=="visit" and _visit_page!="roster":
			_open_visit("roster")
		elif _section=="visit":
			_set_section("governance")
		else:
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
		if op=="visit_report" and field=="visit.answer":
			_show_notice("总督摇了摇头：「数目不合。再看看起账和结账两栏。」")
		else:
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
	var focus:=get_viewport().gui_get_focus_owner()
	var previous_focus: StringName=focus.name if _section in ["governance","visit"] and focus!=null and is_ancestor_of(focus) else &""
	_clear(_tabs)
	_clear(_body)
	_portrait=null
	_portrait_id=""
	if _section=="visit":
		_head.text="柳溪庄　·　庄署"
		_render_visit(_model.visit)
		_restore_body_focus(previous_focus)
		return
	if _model.ended:
		_head.text="生涯已结束"
		_label(_body,"本次人物生涯已结束，仍可返回主菜单读取其他存档。")
		if _model.get("governance",{}).get("established",false):
			_governance(_model.governance)
		return
	if _model.hero==null:
		_head.text="创建人物"
		_create_form()
		return
	var hero: Dictionary=_model.hero
	_head.text="%s　·　人物志"%hero.name
	var titles := {"growth":"身世与成长","gear":"行装","family":"家人和继承","governance":"领地治理"}
	if hero.life_status=="Dead" and _section not in ["family","governance"]: _section="family"
	for key in titles:
		var tab:=_button(_tabs,titles[key],_set_section.bind(key))
		tab.disabled=key==_section or (hero.life_status=="Dead" and key not in ["family","governance"])
	match _section:
		"growth": _growth(hero)
		"gear": _equipment()
		"family": _household(hero)
		"governance":
			_governance(_model.governance)
			_restore_body_focus(previous_focus)

func _restore_body_focus(previous: StringName) -> void:
	if previous==&"": return
	var target:=_body.find_child(previous,true,false) as Button
	if _section=="visit" and (target==null or target.disabled):
		for name_hint in ["AcceptCommission","ReportAnswer0","WaitForLedger","ClaimCommission","ReturnCommission","MeetGovernor","AskCommission","VisitJournal","VisitRoster"]:
			target=_body.find_child(name_hint,true,false) as Button
			if target!=null and not target.disabled: break
	if target==null or target.disabled:
		for control: Button in _body.find_children("*","Button",true,false):
			if not control.disabled:
				target=control
				break
	if target!=null and not target.disabled: target.grab_focus()

func _set_section(section: String) -> void:
	_section=section
	_scroll.scroll_vertical=0
	_show_notice("")
	_render()

func _governance(fief: Dictionary) -> void:
	var by_id: Dictionary={}
	for member: Dictionary in fief.candidates:
		by_id[member.id]=member.name
	var title:=_row(_body)
	_label(title,fief.name,25,GOLD)
	if fief.established and _model.has("visit"):
		_button(title,"拜访庄署",_open_visit.bind("roster")).name="VisitEstate"
	if not fief.can_manage:
		_label(_body,"只有能够理事的家主可以任免总督。",16,MUTED)
	if not fief.established:
		_label(_body,"接管家族庄邑后，可从在家的成年族人中任命总督。庄邑从接管当日开始记账。")
		var open:=_button(_body,"接管"+str(fief.name),_submit.bind("governor_open",{},"家族已接管庄邑。"))
		open.name="GovernorOpen"
		open.disabled=not fief.can_manage
		return
	var summary:=_row(_body)
	_label(summary,"繁荣　%.1f　　 忠诚　%.1f"%[fief.prosperity/10.0,fief.loyalty/10.0],21)
	_label(summary,"现任总督　"+str(by_id.get(fief.governor_id,"空缺")),19,GOLD)
	_label(_body,"总督人选",19,GOLD)
	for member: Dictionary in fief.candidates:
		var row:=_row(_body)
		var details: String="%s　　管理 %d　·　统御 %d"%[member.name,member.stewardship,member.leadership]
		if not member.eligible: details+="　·　"+str(member.reason)
		_label(row,details)
		if member.id==fief.governor_id:
			var dismiss:=_button(row,"卸任总督",_submit.bind("governor_dismiss",{"settlement_id":fief.settlement_id},"总督现已卸任。"))
			dismiss.name="GovernorDismiss"
			dismiss.disabled=not fief.can_manage
		elif member.eligible:
			var assign:=_button(row,"任命"+str(member.name),_submit.bind("governor_assign",{"settlement_id":fief.settlement_id,"hero_id":member.id},"新任总督已到任。"))
			assign.name="GovernorAssign_"+str(member.id).get_file()
			assign.disabled=not fief.can_manage
	var heading:=_row(_body)
	_label(heading,"治理日结　·　每项 0–100 点",19,GOLD)
	if fief.can_manage:
		var wait_day:=_button(heading,"休养一日",_submit.bind("rest",{},"庄邑已结算一日。"))
		wait_day.name="GovernorDay"
	var reports:=_row(_body)
	_governance_day(reports,"下一日预计",fief.next_report,by_id)
	_governance_day(reports,"上次实结",fief.last_report,by_id)

func _open_visit(page: String, person: String="") -> void:
	var fresh: Dictionary=_read.call()
	if not fresh.ok:
		_show_notice("庄署名册暂时无法读取。")
		return
	_model=fresh.value
	_section="visit"
	_visit_page=page
	_visit_person=person
	_scroll.scroll_vertical=0
	_show_notice("")
	_render()

func _render_visit(visit: Dictionary) -> void:
	var speaker: Variant=visit.speaker
	var nav:=_row(_body)
	_button(nav,"返回治理",_set_section.bind("governance")).name="LeaveEstate"
	var roster:=_button(nav,"在场名册",_open_visit.bind("roster"))
	roster.name="VisitRoster"
	roster.disabled=_visit_page=="roster"
	var journal:=_button(nav,"委托簿",_open_visit.bind("journal"))
	journal.name="VisitJournal"
	journal.disabled=_visit_page=="journal"
	if _visit_page=="journal":
		_visit_journal(visit)
		return
	if _visit_page=="roster":
		_label(_body,"庄署会客",25,GOLD)
		if speaker==null:
			_label(_body,"总督席位空着。",18)
		else:
			var row:=_row(_body)
			_label(row,"在任总督　"+str(speaker.name),20)
			var meet:=_button(row,"会见"+str(speaker.name),_open_visit.bind("talk",speaker.id))
			meet.name="MeetGovernor"
			meet.disabled=not visit.can_visit
		if not visit.can_visit:
			_label(_body,"家主在家且身体康健时可以会客。",16,MUTED)
		return
	if speaker==null or speaker.id!=_visit_person or not visit.can_visit:
		_label(_body,"这次会面已经结束。请查看在场名册。",20,GOLD)
		return
	var conversation:=_row(_body)
	var portrait_column:=VBoxContainer.new()
	conversation.add_child(portrait_column)
	_preview(portrait_column,speaker.appearance)
	_portrait.custom_minimum_size=Vector2(216,256)
	var lines:=VBoxContainer.new()
	lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation",10)
	conversation.add_child(lines)
	_label(lines,"总督　"+str(speaker.name),24,GOLD)
	var target:={"hero_id":_visit_person,"settlement_id":visit.settlement_id}
	if _visit_page=="news":
		var fief: Dictionary=_model.governance
		_label(lines,"「今日庄上繁荣 %.1f 点，忠诚 %.1f 点。若要查清盈亏，须看逐日账簿。」"%[fief.prosperity/10.0,fief.loyalty/10.0])
	elif _visit_page=="commission":
		if visit.can_accept:
			_label(lines,"「劳烦你替我核对明日庄簿，看看繁荣实增多少。三日之内来报，我教你些理账的本事。」")
			var accept:=_button(lines,"接下核账委托",_submit.bind("visit_accept",target,"已接下「核对庄簿」。"))
			accept.name="AcceptCommission"
			accept.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		elif visit.can_report:
			_label(lines,"「第 %d 日的簿册就在案上。你算算，这一日繁荣实增多少？」"%visit.ledger.day)
			_visit_ledger(lines,visit.ledger)
			var choices:=_row(lines)
			for answer: int in visit.answers:
				var args:=target.duplicate()
				args["answer"]=answer
				var choice:=_button(choices,"%+.1f 点"%(answer/10.0),_submit.bind("visit_report",args,"总督签结了这份庄簿。"))
				choice.name="ReportAnswer%d"%(choices.get_child_count()-1)
		elif visit.status=="active":
			_label(lines,"「首笔日账还没结。明日再来，你我对着庄簿核一遍。」")
			_button(lines,"休养一日",_submit.bind("rest",{},"次日的庄簿已经结算。")).name="WaitForLedger"
		elif visit.status=="completed":
			_label(lines,"「你核得仔细。此事已经签结，凭委托簿便可查阅。」")
		else:
			_label(lines,visit.reason if not str(visit.reason).is_empty() else "「眼下没有新的差事。」")
	else:
		_label(lines,"「家主来了。案上是柳溪庄的日簿，有什么事要商议？」")
	var options:=_row(lines)
	if _visit_page!="news":
		_button(options,"问庄中近况",_open_visit.bind("news",_visit_person)).name="AskNews"
	if _visit_page!="commission":
		_button(options,"谈核对庄簿",_open_visit.bind("commission",_visit_person)).name="AskCommission"
	_button(options,"告辞",_open_visit.bind("roster")).name="EndAudience"

func _visit_ledger(parent: Node, ledger: Dictionary) -> void:
	_label(parent,"第 %d 日　繁荣起账 %.1f　结账 %.1f"%[ledger.day,ledger.prosperity_before/10.0,ledger.prosperity_after/10.0],17,GOLD)

func _visit_journal(visit: Dictionary) -> void:
	if visit.status=="none":
		_label(_body,"尚未接取庄署委托。",20)
		return
	var statuses:={"active":"待日结","ready":"待回报","completed":"已签结","expired":"已逾期","failed":"已中止"}
	_label(_body,"核对庄簿　·　"+str(statuses.get(visit.status,visit.status)),24,GOLD)
	_label(_body,"第 %d 日受托　·　第 %d 日结束前回报"%[visit.accepted_day,visit.deadline_day])
	if not visit.ledger.is_empty(): _visit_ledger(_body,visit.ledger)
	if not str(visit.reason).is_empty(): _label(_body,visit.reason,16,MUTED)
	if visit.can_claim:
		_button(_body,"领取管理经验",_submit.bind("visit_claim",{},"经验已计入承办人的管理技能。")).name="ClaimCommission"
	elif visit.rewarded:
		_label(_body,"管理经验已领取。",16)
	elif visit.status=="completed":
		_label(_body,"签结待领。由原承办人康健归家后领取。",16)
	elif visit.status=="active" and visit.can_visit:
		_button(_body,"休养一日",_submit.bind("rest",{},"次日的庄簿已经结算。")).name="WaitForLedger"
	if visit.can_report and visit.speaker!=null:
		_button(_body,"向总督回报",_open_visit.bind("commission",visit.issuer_id)).name="ReturnCommission"

func _governance_day(parent: Node, title: String, report: Dictionary, names: Dictionary) -> void:
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	if report.is_empty():
		_label(column,title+"　·　尚无记录",16,MUTED)
		return
	_label(column,"%s　第 %d 日　·　%s"%[title,report.day,names.get(report.governor_id,"空缺")],17,GOLD)
	for key in ["prosperity","loyalty"]:
		var before: int=report[key+"_before"]
		var after: int=report[key+"_after"]
		var label: String="繁荣" if key=="prosperity" else "忠诚"
		_label(column,"%s　%.1f → %.1f（%+.1f）"%[label,before/10.0,after/10.0,(after-before)/10.0],17)
		_label(column,"基础 %+.1f　总督 %+.1f"%[report[key+"_base"]/10.0,report[key+"_bonus"]/10.0],15,MUTED)

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
