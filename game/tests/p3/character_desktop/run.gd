extends SceneTree
## Exercise real launcher controls, visible character actions, save/load, permissions and succession.
const Store = preload("res://infrastructure/persistence/save_service.gd")
var main: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func verify(condition: bool, label: String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		printerr("FAIL ",label)
	return condition

func button(caption: String) -> Button:
	for b: Button in main.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and b.text==caption and not b.disabled: return b
	return null

func press(caption: String) -> bool:
	var b:=button(caption)
	if not verify(b!=null,"visible and enabled button "+caption): return false
	b.pressed.emit()
	return true

func mouse_press(caption: String) -> bool:
	var b:=button(caption)
	if not verify(b!=null,"pointer target "+caption): return false
	var point:=b.get_global_rect().get_center()
	if not verify(root.get_visible_rect().has_point(point),"target inside viewport "+caption): return false
	click_at(point)
	return true

func click_at(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	root.push_input(motion,true)
	for down in [true,false]:
		var click:=InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.position=point
		click.global_position=point
		click.pressed=down
		root.push_input(click,true)

func key_press(code: Key) -> void:
	for down in [true,false]:
		var key:=InputEventKey.new()
		key.keycode=code
		key.physical_keycode=code
		key.pressed=down
		root.push_input(key,true)

func choose_skill(id: String) -> bool:
	var choose:=main.find_child("SkillChoice",true,false) as OptionButton
	for index in choose.item_count:
		if choose.get_item_metadata(index)==id:
			choose.select(index)
			choose.item_selected.emit(index)
			return true
	return verify(false,"skill option "+id)

func shoot() -> void:
	if not choose_skill("bow"):return
	await process_frame
	var board:=main.find_child("PracticeTarget",true,false) as Control
	if not verify(board!=null,"interactive ranged practice board"):return
	var scroll: ScrollContainer=main._desktop._character_panel._scroll
	scroll.ensure_control_visible(board)
	await process_frame
	var before:=view()
	var skill: Dictionary=before.hero.skills.bow
	click_at(board.global_position+Vector2.ONE*4)
	var missed:=view()
	if not verify(missed.last_practice.get("correct")==false and missed.game_minute==before.game_minute+15 and missed.hero.skills.bow==skill,"real pointer miss cost time without XP"):return
	await process_frame
	board=main.find_child("PracticeTarget",true,false)
	scroll.ensure_control_visible(board)
	await process_frame
	var target: Array=missed.practice.bow.target
	click_at(board.global_position+board.size*Vector2(target[0],target[1])/1000.0)
	var hit:=view()
	if not verify(hit.last_practice.correct and hit.hero.skills.bow!=skill and hit.game_minute==missed.game_minute+15,"real pointer target hit advanced bow skill"):return
	await process_frame
	board=main.find_child("PracticeTarget",true,false)
	board.grab_focus()
	scroll.ensure_control_visible(board)
	await process_frame
	var next_target: Array=hit.practice.bow.target
	var dx:=roundi((next_target[0]-500.0)/25.0)
	var dy:=roundi((next_target[1]-500.0)/25.0)
	for i in absi(dx): key_press(KEY_RIGHT if dx>0 else KEY_LEFT)
	for i in absi(dy): key_press(KEY_DOWN if dy>0 else KEY_UP)
	await picture("aim")
	key_press(KEY_ENTER)
	var key_hit:=view()
	verify(key_hit.last_practice.correct and key_hit.game_minute==hit.game_minute+15,"directional keyboard aim confirmed in actual viewport")
	for alternate in ["crossbow","throwing"]:
		if not choose_skill(alternate):return
		verify(main.find_child("PracticeTarget",true,false)!=null,"target practice shown for "+alternate)

func picture(name: String) -> void:
	var folder:=OS.get_environment("RECOLLECTION_CHARACTER_CAPTURES")
	if folder.is_empty(): return
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	verify(image!=null and not image.is_empty() and image.save_png(folder.path_join(name+".png"))==OK,"captured "+name)

func answer(challenge: Dictionary) -> String:
	var directions:=["左","右","上","下"]
	var text: String=challenge.prompt.get_slice("：",1).get_slice("。",0)
	var flags:=text.split(" · ")
	if flags.size()!=3: return ""
	var first:=directions.find(flags[0])
	var second:=directions.find(flags[1])
	var third:=directions.find(flags[2])
	return directions[posmod(third+second-first,4)]

func view() -> Dictionary:
	var result: Dictionary=main._root.character_view()
	verify(result.ok,"authorized view")
	return result.get("value",{})

func scenario() -> void:
	var panel: Control=main._desktop
	var slot: String="person-"+Crypto.new().generate_random_bytes(8).hex_encode()
	panel._slot.text=slot
	verify(main.find_children("*","LineEdit",true,false).size()==1,"clean launcher")
	if not press("新建沙盒"): return
	verify(Store.new().recover(slot).ok,"world committed")
	await process_frame
	if not mouse_press("人物"): return
	await process_frame
	await picture("create")
	var name_input:=main.find_child("HeroName",true,false) as LineEdit
	if not verify(name_input!=null,"character name field"): return
	name_input.text="陆衡"
	name_input.text_changed.emit(name_input.text)
	var appearance:=main.find_child("Appearance",true,false) as OptionButton
	appearance.select(1)
	appearance.item_selected.emit(1)
	if not mouse_press("确立身世"): return
	var first:=view()
	if not verify(first.get("hero") is Dictionary,"hero created"): return
	verify(first.hero.name=="陆衡" and first.hero.appearance=="pine","chosen original name and appearance")
	verify(first.family.size()==2,"household initialized")
	var old_session: RefCounted=main._root.session()
	verify(not old_session.query("character",{"context":RefCounted.new()}).ok,"forged query token rejected")
	var old_token: RefCounted=main._root._save_owner
	verify(not main._root.character_command("outcome",{"kind":"death"},first.revision,"spoofed-outcome").ok,"no player life outcome command")
	var focus: int=first.hero.skills.one_handed.focus
	if not press("投入专精点（余 %d）"%first.hero.focus_points):return
	verify(view().hero.skills.one_handed.focus==focus+1,"focus applied")
	var stale: Dictionary=main._root.character_command("rest",{},first.revision,"stale-rest")
	verify(not stale.ok and stale.error.code=="StaleVersion","stale rendered character revision rejected")
	var skill_key: String="one_handed"
	var best_perk: String=""
	for round_id in 6:
		var state:=view()
		for id in state.hero.available_perks:
			var perk: Dictionary=state.catalog.perks[id]
			if perk.skill==skill_key:
				best_perk=id
				break
		if best_perk!="":break
		if round_id==3 and not press("休养一日"):return
		var result:=answer(state.practice[skill_key])
		if not verify(result in state.practice[skill_key].options,"exercise has computable answer"):return
		if not press(result):return
		verify(view().last_practice.correct,"authoritative answer judged correct")
	if not verify(best_perk!="","perk becomes available through play"):return
	var perk_button: Button
	for b: Button in main.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and b.text.begins_with(view().catalog.perks[best_perk].label) and not b.disabled:
			perk_button=b
			break
	if not verify(perk_button!=null,"eligible perk control"):return
	perk_button.pressed.emit()
	verify(best_perk in view().hero.perks,"perk committed")
	var before_rest:=view()
	if not press("休养一日"):return
	verify(view().day==before_rest.day+1,"rest advanced real campaign day")
	await picture("growth")
	await shoot()
	if not press("行装"):return
	var before:=view()
	var held: String=before.gear.profiles.combat.main_hand
	if held!="":
		if not press("卸下装备"):return
		verify(view().gear.profiles.combat.main_hand=="","item returned to bag")
	if not press("穿戴"):return
	verify(view().gear.profiles.combat.main_hand!="","item equipped")
	await picture("equipment")
	if not press("家人和继承"):return
	if not press("安排退休"):return
	var dialogs:=main.find_children("*","ConfirmationDialog",true,false)
	if not verify(dialogs.size()==1,"retirement requires explicit confirmation"):return
	var dialog: ConfirmationDialog=dialogs[0]
	dialog.canceled.emit()
	dialog.hide()
	await process_frame
	await process_frame
	verify(view().player_id==first.player_id,"retirement cancellation leaves hero intact")
	var heir_id: String=view().heirs[0].id
	if not press("安排退休"):return
	dialog=main.find_children("*","ConfirmationDialog",true,false)[0]
	dialog.get_ok_button().pressed.emit()
	await process_frame
	if not verify(view().player_id==heir_id,"legal heir gained control"):return
	if not press("返回沙盒") or not press("保存进度") or not press("关闭会话") or not press("读取存档"):return
	verify(not old_session.query("character",{"context":old_token}).ok,"old session token revoked on reload")
	if not press("人物"):return
	verify(view().player_id==heir_id and view().family.size()==2,"succession survived cold world restore")
	if not press("家人和继承") or not press("安排退休"):return
	dialog=main.find_children("*","ConfirmationDialog",true,false)[0]
	dialog.get_ok_button().pressed.emit()
	await process_frame
	verify(view().ended and view().player_id==null,"explicit end with no successor")
	await picture("ended")

func run() -> void:
	if not verify(DisplayServer.get_name()!="headless","real desktop"):quit(1);return
	main=load("res://bootstrap/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await scenario()
	main.free()
	print("CHARACTER_DESKTOP checks=",checks," failures=",failures)
	quit(1 if failures else 0)
