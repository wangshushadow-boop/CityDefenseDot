extends SceneTree
## Uses real controls, the live CampaignMap session and the current save slot on disk.
var main: Node
var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
	return ok

func find_button(caption: String) -> Button:
	for b: Button in main.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and not b.disabled and b.text==caption: return b
	return null

func has_text(fragment: String) -> bool:
	for label: Label in main.find_children("*","Label",true,false):
		if label.is_visible_in_tree() and label.text.contains(fragment): return true
	return false

func key(code: Key) -> void:
	for down in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=down
		root.push_input(event,true)

func activate(caption: String, pointer: bool=false) -> bool:
	var b:=find_button(caption)
	if not verify(b!=null,"enabled "+caption): return false
	b.grab_focus()
	await process_frame
	var point:=b.get_global_rect().get_center()
	if not verify(root.get_visible_rect().has_point(point),"on screen "+caption): return false
	if pointer:
		var motion:=InputEventMouseMotion.new()
		motion.position=point
		motion.global_position=point
		root.push_input(motion,true)
		for down in [true,false]:
			var event:=InputEventMouseButton.new()
			event.button_index=MOUSE_BUTTON_LEFT
			event.position=point
			event.global_position=point
			event.pressed=down
			root.push_input(event,true)
	else:
		key(KEY_ENTER)
	await process_frame
	return true

func view() -> Dictionary:
	var reply: Dictionary=main._root.character_view()
	verify(reply.ok,"authorized character view")
	return reply.get("value",{})

func capture() -> void:
	var folder:=OS.get_environment("RECOLLECTION_GOVERNOR_CAPTURES")
	if folder.is_empty(): return
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	verify(image!=null and not image.is_empty() and image.save_png(folder.path_join("governor.png"))==OK,"PNG written")

func scenario() -> void:
	main._desktop._slot.text="gov-"+Crypto.new().generate_random_bytes(8).hex_encode()
	if not await activate("新建沙盒") or not await activate("人物"): return
	if not await activate("确立身世") or not await activate("领地治理",true): return
	var unclaimed:=view()
	if not verify(unclaimed.has("governance") and not unclaimed.governance.established,"optional estate before takeover"): return
	if not await activate("接管柳溪庄"): return
	var fief: Dictionary=view().governance
	if not verify(fief.established and fief.governor_id==null and fief.last_report.is_empty(),"new holding is vacant with no prior day"): return
	var person: Dictionary={}
	for member: Dictionary in fief.candidates:
		if member.eligible:
			person=member
		else:
			verify(has_text(member.reason),"ineligible household member has visible reason")
	if not verify(not person.is_empty() and unclaimed.family.any(func(m): return m.id==person.id),"existing family member offered"): return
	var vacant: Dictionary=fief.next_report
	if not await activate("休养一日"): return
	verify(view().governance.last_report==vacant,"vacant forecast matches real next day")
	if not await activate("任命"+str(person.name),true): return
	var chosen: Dictionary=view().governance
	if not verify(chosen.governor_id==person.id,"pointer appointed chosen hero"): return
	verify(chosen.next_report.prosperity_bonus==1+person.stewardship and chosen.next_report.loyalty_bonus==1+person.leadership,"actual effective skills used in preview")
	verify(chosen.last_report==vacant and has_text("上次实结"),"appointment retains previous term in report")
	var appointment_focus:=root.gui_get_focus_owner()
	verify(appointment_focus!=null and appointment_focus.is_visible_in_tree(),"focus retained after rebuilding panel")
	var day_button:=find_button("休养一日")
	var release_button:=find_button("卸任总督")
	if not verify(day_button!=null and release_button!=null,"occupied office controls present"): return
	release_button.grab_focus()
	key(KEY_TAB)
	await process_frame
	if not verify(root.gui_get_focus_owner()==day_button,"Tab moves from dismissal to next day"): return
	key(KEY_ENTER)
	await process_frame
	var next: Dictionary=view().governance
	if not verify(next.last_report==chosen.next_report,"keyboard advances exactly the previewed day"): return
	verify(next.prosperity==next.last_report.prosperity_after and next.loyalty==next.last_report.loyalty_after,"visible metrics backed by the committed calculation")
	verify(has_text("下一日预计") and has_text("基础") and has_text("0–100 点"),"daily components and bounds shown")
	await capture()
	if not await activate("返回沙盒") or not await activate("保存进度") or not await activate("关闭会话"): return
	if not await activate("读取存档") or not await activate("人物") or not await activate("领地治理"): return
	verify(view().governance==next,"cold session restores office, figures, history and next forecast")
	if not await activate("卸任总督"): return
	var dismissed: Dictionary=view().governance
	verify(dismissed.governor_id==null and dismissed.last_report.governor_id==person.id,"past administrator kept after dismissal")
	verify(dismissed.next_report.prosperity_bonus==0 and dismissed.next_report.loyalty_bonus==0,"vacancy removes future benefit")
	if not await activate("任命"+str(person.name)) or not await activate("家人和继承") or not await activate("安排退休"): return
	var dialog: ConfirmationDialog
	for window: ConfirmationDialog in main.find_children("*","ConfirmationDialog",true,false):
		if window.visible: dialog=window
	if not verify(dialog!=null and dialog.visible,"real retirement confirmation"): return
	dialog.get_ok_button().pressed.emit()
	await process_frame
	if not await activate("领地治理"): return
	var inherited:=view()
	verify(inherited.player_id==person.id and inherited.governance.governor_id==null,"governor who succeeds as clan head vacates office")
	verify(find_button("卸任总督")==null and has_text("空缺"),"succession vacancy rendered")
	if not await activate("家人和继承") or not await activate("安排退休"): return
	for window: ConfirmationDialog in main.find_children("*","ConfirmationDialog",true,false):
		if window.visible: dialog=window
	if not verify(is_instance_valid(dialog) and dialog.visible,"last family head can confirm retirement"): return
	dialog.get_ok_button().pressed.emit()
	await process_frame
	verify(view().ended and has_text("生涯已结束") and has_text("上次实结") and find_button("休养一日")==null,"end of career preserves read-only estate history")

func run() -> void:
	if not verify(DisplayServer.get_name()!="headless","real Windows renderer"):
		quit(1)
		return
	main=load("res://bootstrap/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await scenario()
	main.free()
	print("GOVERNOR_DESKTOP checks=",checks," failures=",failures)
	quit(1 if failures else 0)
