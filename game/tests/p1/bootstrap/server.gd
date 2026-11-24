extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var main: Node=load("res://bootstrap/main.tscn").instantiate()
	root.add_child(main)
	for i in 9:
		await physics_frame
	var app: RefCounted=main._root.session()
	var session: Dictionary=app.query()
	var mission: Dictionary=app.query("mission")
	var good: bool=session.ok and session.value.mode=="multiplayer" and session.value.state=="Mission" and mission.ok and mission.value.tick>=5
	good=good and Engine.physics_ticks_per_second==30 and not ResourceLoader.has_cached("res://bootstrap/desktop.gd") and main.find_children("*","Control",true,false).is_empty()
	print("BOOT_SERVER_LIVE tick=",mission.value.tick," hz=",Engine.physics_ticks_per_second," ","PASS" if good else "FAIL")
	main.free()
	quit(0 if good else 1)
