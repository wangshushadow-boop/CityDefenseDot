extends SceneTree
## External driver can also open the project's packaged main scene through --main-pack.
var main: Node
var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
	return ok

func model() -> Dictionary:
	return main._root.character_view().value

func button(text: String) -> Button:
	for b: Button in main.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and not b.disabled and b.text==text: return b
	return null

func visible_text(fragment: String) -> bool:
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

func press(text: String, mouse:=false) -> bool:
	var b:=button(text)
	if not check(b!=null,"available: "+text): return false
	b.grab_focus()
	await process_frame
	var point:=b.get_global_rect().get_center()
	if not check(root.get_visible_rect().has_point(point),"on screen: "+text): return false
	if mouse:
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
	else: key(KEY_ENTER)
	await process_frame
	return true

func screenshot() -> void:
	var dest:=OS.get_environment("RECOLLECTION_VISIT_CAPTURES")
	if dest.is_empty(): return
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	check(image!=null and not image.is_empty() and image.save_png(dest.path_join("estate-audience.png"))==OK,"meeting screenshot written")

func reopen() -> bool:
	for title in ["返回沙盒","保存进度","关闭会话","读取存档","人物","领地治理","拜访庄署","委托簿"]:
		if not await press(title): return false
	return true

func scenario() -> void:
	main._desktop._slot.text="visit-"+Crypto.new().generate_random_bytes(8).hex_encode()
	for title in ["新建沙盒","人物","确立身世","领地治理","接管柳溪庄","拜访庄署"]:
		if not await press(title): return
	check(visible_text("席位空着") and model().visit.speaker==null,"vacant seat has no actor")
	if not await press("返回治理"): return
	var heir: Dictionary=model().heirs[0]
	var call_on: String="会见"+str(heir.name)
	if not await press("任命"+str(heir.name),true) or not await press("拜访庄署",true) or not await press(call_on): return
	check(model().visit.speaker.id==heir.id and visible_text("总督　"+str(heir.name)),"meeting bound to actual appointed member")
	if not await press("问庄中近况") or not await press("谈核对庄簿"): return
	check(main.find_child("AppearancePreview",true,false)!=null and not main.find_children("*","MeshInstance3D",true,false).is_empty(),"3D character at audience")
	await screenshot()
	# The authority changes after the offer is already displayed.
	var fief: Dictionary=model().governance
	var removed: Dictionary=main._root.character_command("governor_dismiss",{"settlement_id":fief.settlement_id},model().revision,"test/stale-visit")
	if not check(removed.ok,"dismiss previous speaker using the same bound game entry"): return
	if not await press("接下核账委托"): return
	check(model().visit.status=="none" and visible_text("这次会面已经结束") and button("接下核账委托")==null,"stale conversation cannot accept")
	if not await press("返回治理") or not await press("任命"+str(heir.name)): return
	for title in ["拜访庄署",call_on,"谈核对庄簿","接下核账委托","委托簿"]:
		if not await press(title): return
	var active: Dictionary=model().visit
	check(active.status=="active" and active.issuer_id==heir.id and visible_text("结束前回报"),"accepted journal gives deadline")
	if not await reopen(): return
	check(model().visit==active,"physical cold load with active journal")
	if not await press("休养一日") or not await press("向总督回报"): return
	var ready: Dictionary=model().visit
	if not check(ready.status=="ready" and ready.ledger.day==active.accepted_day+1 and ready.answers.size()==3,"real dated ledger with three replies"): return
	var correct: int=ready.ledger.prosperity_after-ready.ledger.prosperity_before
	for answer: int in ready.answers:
		if answer!=correct:
			if not await press("%+.1f 点"%(answer/10.0)): return
			break
	check(model().visit==ready and visible_text("数目不合"),"wrong reply keeps the original ledger and reward")
	if not await press("%+.1f 点"%(correct/10.0),true): return
	if not await reopen(): return
	check(model().visit.status=="completed" and model().visit.can_claim,"signed receipt survives close and reload")
	var old_skill: Dictionary=model().hero.skills.stewardship.duplicate(true)
	if not await press("领取管理经验",true): return
	var earned: Dictionary=model().hero.skills.stewardship
	check(earned!=old_skill and model().visit.rewarded and visible_text("已领取") and button("领取管理经验")==null,"claimed XP changes real skill and removes claim")
	if not await reopen(): return
	check(model().hero.skills.stewardship==earned and model().visit.rewarded and model().visit.ledger==ready.ledger,"cold reward and immutable journal")
	key(KEY_ESCAPE)
	await process_frame
	check(button(call_on)!=null,"Escape returns from journal to roster")

func run() -> void:
	if not check(DisplayServer.get_name()!="headless","native Windows client"):
		quit(1)
		return
	main=load("res://bootstrap/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await scenario()
	main.free()
	print("ESTATE_DESKTOP checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
