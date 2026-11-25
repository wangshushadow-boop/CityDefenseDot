extends SceneTree
## Exercise the launcher and the same HUD actions a desktop player uses.
var main: Node
func _initialize() -> void:
	run.call_deferred()

func fail(message: String) -> void:
	printerr("FAIL ",message)
	quit(1)

func button(id: String) -> Button:
	return main.find_child(id,true,false) as Button

func caption(value: String) -> Button:
	for node in main.find_children("*","Button",true,false):
		if node.text==value and node.is_visible_in_tree(): return node
	return null

func run() -> void:
	if DisplayServer.get_name()=="headless":
		fail("desktop requires a window")
		return
	main=load("res://bootstrap/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var entry:=caption("进入河原野战")
	if entry==null:
		fail("field launcher missing")
		return
	entry.pressed.emit()
	await process_frame
	var start:=caption("开始野战")
	if start==null:
		fail("field did not mount")
		return
	var group := button("Group1")
	var zone := button("Zone") as OptionButton
	if group==null or zone==null or zone.item_count!=2:
		fail("player deployment controls missing")
		return
	group.pressed.emit()
	button("Group2").pressed.emit()
	zone.select(1)
	zone.item_selected.emit(1)
	button("Mark").pressed.emit()
	button("Deploy").pressed.emit()
	for i in 180:
		await process_frame
		if main._last_tick>=4: break
	if main._last_tick<4:
		fail("could not play through four ticks")
		return
	var h: Dictionary=main._root.field_view("input")
	if not h.ok or not h.value.actor_handle is Dictionary:
		fail("player has no actor")
		return
	if h.value.last_order_sequence!=2:
		fail("chosen formation was not deployed")
		return
	if not button("Group1").button_pressed: button("Group1").pressed.emit()
	button("Hold").pressed.emit()
	var held:=false
	for i in 60:
		await process_frame
		var hud: Dictionary = main._root.field_view("hud")
		var formation: Dictionary = hud.value.formations[0]
		if formation.get("active") is Dictionary and formation.active.issuer_id=="player" and formation.active.order_type=="hold":
			held=true
			break
	if not held:
		fail("first player order after deployment was not executed")
		return
	var withdraw:=button("Withdraw")
	if withdraw==null or not withdraw.is_visible_in_tree():
		fail("withdraw control missing")
		return
	var destination:=OS.get_environment("RECOLLECTION_FIELD_SCREENSHOT")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(destination)!=OK:
			fail("screenshot")
			return
	withdraw.pressed.emit()
	var confirm:=button("Confirm")
	if not confirm.is_visible_in_tree():
		fail("missing withdrawal confirmation")
		return
	confirm.pressed.emit()
	for i in 60:
		await process_frame
		if main._root.session().query().value.state=="Results": break
	var result: Dictionary=main._root.field_view("hud")
	if not result.ok or result.value.get("phase")!="ended" or result.value.result.slot_outcomes.is_empty():
		fail("missing confirmed result")
		return
	var leave:=button("Leave")
	if not leave.is_visible_in_tree():
		fail("missing return control")
		return
	leave.pressed.emit()
	await process_frame
	await process_frame
	if main._root.has_field() or caption("进入河原野战")==null:
		fail("launcher did not regain control")
		return
	print("FIELD_DESKTOP PASS result_slots=",result.value.result.slot_outcomes.size())
	main.queue_free()
	await process_frame
	quit(0)
