extends SceneTree

const Fixture = preload("res://tests/p2/move_intents/run.gd")
const Field = preload("res://mission/movement/ports/field_movement.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const SCOPE := "path-retention"
const DT := 1.0/60
var meter := Fixture.Meter.new()
var ai := RefCounted.new()
var checks := 0
var failures := 0

func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		printerr("FAIL ",label)

func handle(i: int) -> Dictionary:
	return {"index":i,"generation":1}

func move(i: int) -> Dictionary:
	return {"actor_handle":handle(i),"desired_direction":[1000000,0,0],"speed_fraction":1.0,"stance":"walk"}

func authorize(scope, _actor, context, _tick) -> bool:
	return scope==SCOPE and is_same(context,ai)

func retention() -> void:
	var field := Field.new(meter,SCOPE,authorize)
	var queue: RefCounted = field._direct
	var oldest: Dictionary
	for i in 128:
		var origin := [-25000,0,8000+i]
		var dest := [-7000,0,8000+i]
		var requested: Dictionary = queue.request_path(origin,dest,"foot")
		check(requested.ok,"admit distinct path "+str(i))
		if not requested.ok:return
		if i==0:oldest=requested.value
		if i%8==7:
			var filled: Dictionary = queue.process_budget(i/8)
			check(filled.ok and filled.value.queried==8,"fill one budget")
	var warmed: Dictionary = queue.poll_path(oldest)
	check(meter.queries==128 and warmed.ok and warmed.value.reachable,"oldest reachable path retained after filling 128 entries")
	var forged: Dictionary = queue.poll_path(oldest.duplicate())
	check(not forged.ok and forged.error.code=="NotFound","copied ticket rejected")
	var positions := [Vector3(-25,0,8),Vector3(-25,0,12)]
	for i in 2:
		check(field.spawn(handle(i),positions[i]).ok,"spawn driver")
	var first_path_count := meter.queries
	for attempt in 2:
		var begun := field.begin_step(16)
		if not begun.ok:
			check(false,"open current movement transaction");return
		for i in 2:check(field.apply_move_intent(begun.value,move(i),ai).ok,"drive first cached and another new origin")
		var paths := field.stage_step(16,DT,begun.value)
		check(paths.ok,"resolve same-batch FIFO eviction "+str(paths.get("error","")))
		if not paths.ok:
			field.rollback_step(begun.value)
			return
		check(paths.value.total_queried==1 and meter.queries==first_path_count+1,"one native query across both attempts")
		for i in 2:
			var actor: Dictionary = field.view(handle(i),begun.value).value
			check(actor.position.x>positions[i].x,"driver %d after batch: %s"%[i,actor])
		if attempt==0:
			check(field.rollback_step(begun.value).ok and queue.poll_path(oldest).ok,"rollback restores queue and ticket")
			for i in 2: check(field.view(handle(i)).value.position==positions[i],"rollback restores driving positions")
		else:
			check(field.commit_step(begun.value).ok,"publish retried movement")
	var stale: Dictionary = field._direct.poll_path(oldest)
	check(not stale.ok and stale.error.code=="NotFound","expired ticket rejected after commit")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var engine := Adapter.new(root,true)
	meter.engine=engine
	var opened := engine.open_scope(SCOPE)
	var loaded := engine.load_scene({"id":"field:scene/retention","simulation_scene":"res://tests/p2/ai/arena.tscn"},opened.value)
	check(loaded.ok,"load real navigation")
	var synced := false
	for frame in 90:
		await physics_frame
		var nav := engine.sync_navigation(SCOPE)
		if nav.ok and nav.value.status=="applied":
			var probe := engine.query_path_batch([{"from":[-25000,0,8000],"to":[-7000,0,8000]}],nav.value.applied_revision,SCOPE)
			if probe.ok and probe.value[0].reachable:
				synced=true
				break
	check(synced,"synchronized navigation")
	if synced:retention()
	engine.release_scope(SCOPE)
	print("PATH_RETENTION checks=",checks," failures=",failures)
	quit(int(failures>0))
