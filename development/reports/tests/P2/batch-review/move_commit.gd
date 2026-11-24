extends SceneTree
const Field = preload("res://mission/movement/ports/field_movement.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const SCOPE := "move-intent-field"
const DT := 1.0/60
const RIGHT := [1000000,0,0]
var failures := 0
var checks := 0
var player := RefCounted.new()
var ai := RefCounted.new()
var permitted := true
var player_index := -1
var engine: RefCounted
var meter: Meter

class Meter:
	var engine: RefCounted
	var queries := 0
	var sweeps := 0
	var on_sweep: Callable
	func sync_navigation(scope: String) -> Dictionary:
		return engine.sync_navigation(scope)
	func query_path_batch(rows: Array,revision: int,scope: String) -> Dictionary:
		queries += rows.size()
		return engine.query_path_batch(rows,revision,scope)
	func query_sweep_batch(rows: Array,stamp: Dictionary) -> Dictionary:
		sweeps += rows.size()
		if on_sweep.is_valid(): on_sweep.call()
		return engine.query_sweep_batch(rows,stamp)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func authorize(scope: String,actor: Dictionary,context: Variant,_tick: int) -> bool:
	return scope==SCOPE and permitted and (is_same(context,ai) or (is_same(context,player) and (player_index<0 or player_index==actor.index)))

func handle(i: int,generation:=1) -> Dictionary:
	return {"index":i,"generation":generation}

func move(i: int,fraction:=1.0,direction:=RIGHT,stance: Variant=null) -> Dictionary:
	return {"actor_handle":handle(i),"desired_direction":direction,"speed_fraction":fraction,"stance":stance}

func enqueue(field: Field,tick: int,input: Dictionary,owner: Variant) -> Dictionary:
	var opened := field.begin_step(tick)
	check(opened.ok,"open tick %d"%tick)
	if not opened.ok: return opened
	var accepted := field.apply_move_intent(opened.value,input,owner)
	if not accepted.ok:
		field.rollback_step(opened.value)
		return accepted
	return field.stage_step(tick,DT,opened.value)

func commit(field: Field,tick: int,input: Dictionary,owner: Variant) -> bool:
	var stage := enqueue(field,tick,input,owner)
	return stage.ok and field.commit_step(stage.value.stage_token).ok

func wait_nav() -> bool:
	for frame in 120:
		await physics_frame
		var sync: Dictionary = engine.sync_navigation(SCOPE)
		if sync.ok and sync.value.status=="applied":
			var probe: Dictionary = engine.query_path_batch([{"from":[-10000,0,0],"to":[-8000,0,0]}],sync.value.applied_revision,SCOPE)
			if probe.ok and probe.value[0].reachable: return true
	return false

func arena(scene: String) -> bool:
	var opened: Dictionary = engine.open_scope(SCOPE)
	return opened.ok and engine.load_scene({"id":"base:scene/move_intents","simulation_scene":scene},opened.value).ok and await wait_nav()

func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	engine = Adapter.new(root,true)
	meter = Meter.new()
	meter.engine=engine
	if not await arena("res://tests/p2/ai/arena.tscn"): quit(2);return
	var origin:=Vector3(-19,0,6)
	var field:=Field.new(meter,SCOPE,authorize)
	field.spawn(handle(0),origin)
	var stage := enqueue(field,1,move(0),player)
	var staged: Dictionary = field.view(handle(0),stage.value.stage_token)
	permitted = false
	var write := field.commit_step(stage.value.stage_token)
	var displacement: float = origin.distance_to(field.view(handle(0)).value.position)
	print("after revoke commit_ok=",write.ok," candidate_x=",staged.value.position.x," committed_distance=",displacement)
	permitted = true
	var rider := Field.new(meter,SCOPE,authorize)
	var where:=Vector3(-20,0,-6)
	rider.spawn(handle(2),where)
	var collider := StaticBody3D.new()
	collider.collision_layer = 2
	collider.set_meta("entity_handle","moving-2-1")
	var shape:=CollisionShape3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.32
	shape.shape=capsule
	collider.add_child(shape)
	collider.position = where+Vector3.UP*.9
	get_first_node_in_group("ai_test_wall").get_parent().add_child(collider)
	await physics_frame
	await physics_frame
	var accepted:=commit(rider,1,move(2),player)
	for t in range(2,11): rider.step(t,DT)
	var held:Dictionary=rider.view(handle(2)).value
	print("self hurtbox accepted=",accepted," displacement=",held.position.distance_to(where)," reason=",held.blocked)
	engine.release_scope(SCOPE)
	quit(1 if write.ok and displacement>0 or accepted and held.position==where else 0)
