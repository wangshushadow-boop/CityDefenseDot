extends RefCounted

const Field = preload("res://mission/movement/ports/field_movement.gd")
const RIDER := {"index":0,"generation":3}
const DT := 1.0/60
var verify: Callable
var field: RefCounted
var tick := 0
var credential := RefCounted.new()

func _start(engine: RefCounted,scope: String,origin: Vector3,direction: Vector3) -> void:
	var owner := credential
	field=Field.new(engine,scope,func(id,h,ctx,_t):return id==scope and h==RIDER and is_same(ctx,owner))
	tick=0
	verify.call(field.spawn(RIDER,origin,"foot",direction).ok,"edge fixture actor")

func _flight(direction: Vector3) -> Dictionary:
	tick+=1
	var stage: Variant=field.begin_step(tick).value
	var send: Dictionary=field.request_jump(RIDER,credential,stage)
	if not verify.call(send.ok,"jump from actual support "+str(send.get("error"))): return {}
	var drive := {"actor_handle":RIDER,"desired_direction":[roundi(direction.x*1000000),0,roundi(direction.z*1000000)],"speed_fraction":1.0,"stance":"sprint"}
	verify.call(field.apply_move_intent(stage,drive,credential).ok and field.stage_step(tick,DT,stage).ok and field.commit_step(stage).ok,"launch with horizontal drive")
	var peak := 0.0
	var blocked := false
	for frame in 120:
		tick+=1
		var next: Variant=field.begin_step(tick).value
		if not verify.call(field.stage_step(tick,DT,next).ok,"collision step"): return {}
		var pose: Dictionary=field.view(RIDER,next).value
		if pose.blocked=="no_landing" and not blocked:
			blocked=true
			verify.call(field.rollback_step(next).ok,"discard unsupported candidate movement")
			next=field.begin_step(tick).value
			verify.call(field.stage_step(tick,DT,next).ok and field.view(RIDER,next).value==pose,"same edge pose and velocity on retry")
		if not verify.call(field.commit_step(next).ok,"publish trajectory"): return {}
		peak=maxf(peak,pose.position.y)
		if not pose.airborne: return {"position":pose.position,"peak":peak,"edge":blocked}
	verify.call(false,"bounded trajectory must land")
	return {}

func obstacles(engine: RefCounted,scope: String,check: Callable) -> void:
	verify=check
	_start(engine,scope,Vector3(-20,0,-20),Vector3.RIGHT)
	var on_step:=_flight(Vector3.RIGHT)
	if on_step.is_empty(): return
	verify.call(on_step.position.x> -19.4 and absf(on_step.position.y-.45)<.015,"land on top of elevated step")
	var off_step:=_flight(Vector3.RIGHT)
	if off_step.is_empty(): return
	verify.call(off_step.position.x> -17.3 and absf(off_step.position.y)<.015,"jump down from walkable ledge")
	_start(engine,scope,Vector3(-20,0,-15),Vector3.RIGHT)
	var beyond:=_flight(Vector3.RIGHT)
	if beyond.is_empty(): return
	verify.call(beyond.position.x> -18.8 and beyond.peak>.30 and absf(beyond.position.y)<.015,"jump over solid low hurdle")
	print("JUMP_OBSTACLES step=",on_step.position," lower=",off_step.position," hurdle=",beyond.position)

func river(engine: RefCounted,scene_tree: SceneTree,check: Callable) -> void:
	verify=check
	var scope: String="test:river_edge"
	var opened: Dictionary=engine.open_scope(scope)
	var scene := {"id":"field:scene/river_plain","simulation_scene":"res://content/base/field/river_plain.tscn"}
	if not verify.call(opened.ok and engine.load_scene(scene,opened.value).ok,"load production River Plain"): return
	var ready := false
	for i in 90:
		await scene_tree.physics_frame
		var nav: Dictionary=engine.sync_navigation(scope)
		if nav.ok and nav.value.status=="applied":
			var proof: Dictionary=engine.query_path_batch([{"from":[0,0,80000],"to":[0,0,89500]}],nav.value.applied_revision,scope)
			if proof.ok and proof.value[0].reachable:
				ready=true
				break
	if verify.call(ready,"real river mesh ready"):
		_start(engine,scope,Vector3(0,0,87.5),Vector3.BACK)
		var first:=_flight(Vector3.BACK)
		var second:=_flight(Vector3.BACK)
		var third:=_flight(Vector3.BACK)
		if not first.is_empty() and not second.is_empty() and not third.is_empty():
			verify.call(second.edge and third.edge and third.position.z<=90 and third.position.z>89.8 and absf(third.position.y)<.015,"outward jumps finish on river ground")
			print("JUMP_RIVER landings=",first.position," ",second.position," ",third.position)
	engine.release_scope(scope)
	field=null
