extends SceneTree
const World = preload("res://tests/p2/formation_ai/world.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const FIELD := {"id":"test:scene/formation_ai","simulation_scene":"res://tests/p2/formation_ai/field.tscn"}
var errors := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var engine := Adapter.new(root,true)
	var opened := engine.open_scope(World.SCOPE)
	check(opened.ok and engine.load_scene(FIELD,opened.value).ok,"real field")
	var nav := -1
	for i in 120:
		await physics_frame
		var sync := engine.sync_navigation(World.SCOPE)
		if sync.ok and sync.value.status=="applied":
			nav = sync.value.applied_revision
			break
	if nav < 0:
		printerr("FAIL navigation")
		quit(1)
		return
	var w := World.new(engine,nav,check)
	w.deploy(0,[0],[Vector3(0,0,-8)],"infantry",0)
	var job: Dictionary = w.publish(1).formation
	var task := w.task("hold","infantry",Vector3(0,0,-8))
	var original: Dictionary = w.brain.stage(job,task,w.ground(),1).value
	var drained := w.collect(job,original)
	check(w.brain.begin_tick().ok and not w.brain.begin_tick().ok,"single transaction")
	check(w.brain.commit(original.token,drained).ok and w.brain.view(0).ok,"real authorized plan")
	w.brain.rollback_tick()
	check(not w.brain.view(0).ok,"later failure unpublishes decision")
	check(w.brain.validate(original.token,drained).ok,"original grant and accepted row identity restored")
	check(not w.brain.validate(original.token,drained.duplicate(true)).ok,"copied grant rejected")
	check(w.brain.begin_tick().ok and w.brain.commit(original.token,drained).ok,"retry same ticket")
	w.brain.commit_tick()
	w.brain.rollback_tick()
	check(w.brain.view(0).ok and not w.brain.validate(original.token,drained).ok,"one committed consumption")
	check(w.brain.begin_tick().ok,"begin closing")
	w.brain.close()
	w.brain.rollback_tick()
	check(not w.brain.view(0).ok and not w.brain.begin_tick().ok,"closed stays closed")
	engine.release_scope(World.SCOPE)
	print("Formation AI tick transaction ", "PASS" if errors==0 else "FAIL")
	quit(1 if errors else 0)
