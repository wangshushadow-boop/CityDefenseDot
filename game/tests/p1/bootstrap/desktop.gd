extends SceneTree
const Store = preload("res://infrastructure/persistence/save_service.gd")
var errors := 0
var main: Node

func _initialize() -> void:
	run.call_deferred()

func click(caption: String) -> void:
	for button: Button in main.find_children("*","Button",true,false):
		if button.text==caption and not button.disabled:
			button.pressed.emit()
			return
	printerr("FAIL unavailable button ",caption)
	errors+=1

func verify(expected: bool, label: String) -> void:
	if not expected:
		printerr("FAIL ",label)
		errors+=1

func run() -> void:
	verify(DisplayServer.get_name()!="headless","actual desktop")
	main=load("res://bootstrap/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var inputs:=main.find_children("*","LineEdit",true,false)
	if inputs.size()!=1:
		printerr("FAIL desktop launcher")
		quit(1)
		return
	var slot: String="desktop-"+Crypto.new().generate_random_bytes(8).hex_encode()
	inputs[0].text=slot
	click("新建沙盒")
	var created:=Store.new().recover(slot)
	verify(created.ok and created.value.snapshot.session.mode=="sandbox","button created a durable world")
	click("保存进度")
	var saved:=Store.new().recover(slot)
	verify(saved.ok and saved.value.manifest.commit_id!=created.value.manifest.commit_id,"button committed a new marker")
	click("关闭会话")
	click("读取存档")
	click("进入训练")
	await physics_frame
	await physics_frame
	verify(main.find_children("Simulation","Node3D",true,false).size()==1,"world loaded and actual arena leased")
	click("结束训练")
	verify(main.find_children("Simulation","Node3D",true,false).is_empty(),"arena released")
	click("关闭会话")
	verify(Store.new().recover(slot).value.snapshot==saved.value.snapshot,"custom training left campaign snapshot untouched")
	main.free()
	print("BOOT_DESKTOP_BUTTONS errors=",errors)
	quit(1 if errors else 0)
