extends SceneTree

const Field = preload("res://mission/movement/ports/field_movement.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const SCOPE := "profile-field"
const RIDER := {"index":0,"generation":3}
const ALLY := {"index":1,"generation":1}
const DT := 1.0/60.0
var checks := 0
var failures := 0
var engine: RefCounted
var credential := RefCounted.new()
var nested_stage: Variant
var controlled: RefCounted
var rejected_nesting := false

func check(ok: bool, why: String) -> bool:
	checks += 1
	if not ok:
		failures+=1
		printerr("FAIL ",why)
	return ok

func group_case() -> void:
	var f := Field.new(engine,SCOPE)
	var start := Vector3(-20,0,8)
	var goal := Vector3(8,0,8)
	check(f.spawn(RIDER,start,"foot",Vector3.RIGHT).ok and f.spawn(ALLY,start+Vector3.BACK*3,"foot",Vector3.RIGHT).ok,"two live source generations")
	var roster: Dictionary=f.bind_roster([RIDER,ALLY])
	check(roster.ok,"bound existing lineup")
	var narrow := AABB(Vector3(-12,-1,7.65),Vector3(8,2,0.70))
	check(f.set_terrain([{"bounds":narrow,"profiles":["foot","mounted"]}]).ok,"both profiles may use passage if footprint fits")
	check(f.set_corridor("squad",start,goal).ok and f.assign(RIDER,"squad").ok and f.assign(ALLY,"squad",Vector3.BACK*3.0).ok,"shared foot arrangement")
	var stage: Variant = f.begin_step(1).value
	check(not f.set_profile(RIDER,"mounted",null).ok and not f.set_profile(RIDER,"mounted",RefCounted.new()).ok,"only outstanding stage token")
	check(not f.set_profile({"index":0,"generation":2},"foot",stage).ok and not f.set_profile({"index":12,"generation":1},"mounted",stage).ok,"retired or missing body")
	check(not f.set_profile(RIDER,"horse",stage).ok,"unknown locomotion profile")
	check(f.set_profile(RIDER,"mounted",stage).ok and f.set_profile(RIDER,"mounted",stage).ok,"mount twice")
	check(f.view(RIDER).value.profile=="foot" and f.view(RIDER,stage).value.profile=="mounted" and f.view(ALLY,stage).value.profile=="foot","isolated profile and fellow soldier")
	check(f.stage_step(1,DT,stage).ok,"stage mixed corridor")
	var candidate: Dictionary=f.view(RIDER,stage).value
	check(f.read_poses(roster.value,stage).value.positions[0]==candidate.position,"original roster identity still bound")
	check(f.rollback_step(stage).ok and not f.set_profile(RIDER,"mounted",stage).ok,"discarded token revoked")
	check(f.view(RIDER).value.position==start and f.read_positions(roster.value).value[0]==start,"no discarded motion")
	stage=f.begin_step(1).value
	check(f.set_profile(RIDER,"mounted",stage).ok and f.stage_step(1,DT,stage).ok and f.view(RIDER,stage).value==candidate and f.commit_step(stage).ok,"same-tick replay mixed path and kinematics")
	var fast := 0.0
	for t in range(2,241):
		var token: Variant=f.begin_step(t).value
		if t==20:
			check(f.set_corridor("squad",start,Vector3(12,0,8),"foot",token).ok and f.assign(RIDER,"squad",Vector3.ZERO,token).ok,"retarget mixed group without changing teammate profile")
		if not check(f.stage_step(t,DT,token).ok and f.commit_step(token).ok,"shared move"): return
		fast=maxf(fast,f.view(RIDER).value.velocity.length())
	var mounted: Dictionary=f.view(RIDER).value
	var ally: Dictionary=f.view(ALLY).value
	check(fast>3.5 and fast<=9.01,"mounted profile accelerates above foot speed")
	check(mounted.position.x < -11.99 and mounted.position.x > -12.2 and mounted.blocked=="yield","0.94m mounted footprint blocked by 0.70m")
	check(ally.profile=="foot" and ally.position.x> -9.0 and ally.position.z>9,"teammate kept original corridor and slot")
	stage=f.begin_step(241).value
	check(f.stage_step(241,DT,stage).ok,"movement completes before combat")
	var contact: Dictionary=f.view(RIDER,stage).value
	check(f.set_profile(RIDER,"foot",stage).ok and f.view(RIDER,stage).value.position==contact.position,"late fall preserves this step's travel")
	check(f.rollback_step(stage).ok and f.view(RIDER).value==mounted,"late dismount rollback preserves original footprint")
	stage=f.begin_step(241).value
	check(f.stage_step(241,DT,stage).ok and f.set_profile(RIDER,"foot",stage).ok and f.commit_step(stage).ok,"same-tick late fall commit")
	for t in range(242,690):
		if not check(f.step(t,DT).ok,"foot movement"): return
	var foot: Dictionary=f.view(RIDER).value
	check(foot.profile=="foot" and foot.arrived and foot.position.distance_to(Vector3(12,0,8))<0.08,"0.56m foot traverses narrow passage to retargeted goal")
	check(f.read_poses(roster.value).value.positions[0]==foot.position,"same birth across both transitions")
	print("PROFILE_GROUP max_mounted_mps=",fast," mounted_stop=",mounted.position," foot_goal=",foot.position," ally=",ally.position)

func authority(scope: String,h: Dictionary,ctx: Variant,_tick: int) -> bool:
	if nested_stage!=null:
		rejected_nesting=not controlled.set_profile(RIDER,"foot",nested_stage).ok
	return scope==SCOPE and h==RIDER and is_same(ctx,credential)

func drive_case() -> void:
	controlled=Field.new(engine,SCOPE,authority)
	var start:=Vector3(-5,0,0)
	check(controlled.spawn(RIDER,start,"foot",Vector3.RIGHT).ok,"spawn near wall")
	var rider_body := {"team_key":0,"handle":RIDER,"position":start,"mounted":true,"facing":Vector3.RIGHT}
	var horse_body := {"team_key":0,"handle":{"index":3,"generation":1},"position":start,"type":"mount","facing":Vector3.RIGHT}
	check(engine.field_stage_bodies(SCOPE,[rider_body,horse_body]).ok and engine.field_commit_bodies(SCOPE).ok,"real Jolt mount and rider in movement space")
	nested_stage=controlled.begin_step(1).value
	check(controlled.set_profile(RIDER,"mounted",nested_stage).ok,"upgrade before direct drive")
	var move := {"actor_handle":RIDER,"desired_direction":[1000000,0,0],"speed_fraction":1.0,"stance":"sprint"}
	check(controlled.apply_move_intent(nested_stage,move,credential).ok and rejected_nesting,"reentrant profile write rejected by authority callback")
	var token: Variant=nested_stage
	nested_stage=null
	check(controlled.stage_step(1,DT,token).ok and controlled.commit_step(token).ok,"direct drive commit")
	var speed := 0.0
	for t in range(2,52):
		check(controlled.step(t,DT).ok,"rider clears own colliders")
		speed=maxf(speed,controlled.view(RIDER).value.velocity.length())
	var before: Dictionary=controlled.view(RIDER).value
	check(before.position.x>start.x+1 and speed>3,"human and horse colliders do not pin same rider's drive")
	token=controlled.begin_step(52).value
	check(controlled.stage_step(52,DT,token).ok and controlled.set_profile(RIDER,"foot",token).ok and controlled.view(RIDER,token).value.velocity.length()<=3.401 and controlled.commit_step(token).ok,"active approved drive survives late fall with capped foot speed")
	for t in range(53,181): check(controlled.step(t,DT).ok,"foot drive towards static wall")
	var at: Dictionary=controlled.view(RIDER).value
	check(at.profile=="foot" and at.blocked=="scene" and at.position.x<-.47 and at.position.x>-.6,"real Jolt wall blocks newly foot-sized drive")
	print("PROFILE_DRIVE start=",start," mounted=",before.position," foot_wall=",at.position)

func _initialize() -> void:
	run.call_deferred()

func jump_case(start: Vector3,roof: bool,travel: bool) -> bool:
	var permission := {"active":true}
	var f := Field.new(engine,SCOPE,func(scope,h,ctx,_tick):return scope==SCOPE and permission.active and h==RIDER and is_same(ctx,credential))
	check(f.spawn(RIDER,start,"foot",Vector3.RIGHT).ok,"foot actor for jump")
	var roster: Dictionary=f.bind_roster([RIDER])
	var token: Variant=f.begin_step(1).value
	check(not f.request_jump(RIDER,RefCounted.new(),token).ok,"foreign jump control")
	check(f.set_profile(RIDER,"mounted",token).ok and not f.request_jump(RIDER,credential,token).ok,"mounted jump denied")
	check(f.set_profile(RIDER,"foot",token).ok and not f.request_jump(RIDER,credential,token).ok,"same-tick dismount and jump conflict")
	check(f.rollback_step(token).ok,"reset mounting candidate")
	token=f.begin_step(1).value
	if not check(f.request_jump(RIDER,credential,token).ok,"real foot support and head clearance"): return false
	check(not f.request_jump(RIDER,credential,token).ok and not f.set_profile(RIDER,"mounted",token).ok,"airborne request and mount rejected")
	if travel:
		check(f.apply_move_intent(token,{"actor_handle":RIDER,"desired_direction":[1000000,0,0],"speed_fraction":1.0,"stance":"sprint"},credential).ok,"horizontal airborne input")
	if not check(f.stage_step(1,DT,token).ok,"ballistic advance"): return false
	var branch: Dictionary=f.view(RIDER,token).value
	check(branch.position.y>start.y and branch.velocity.y>0 and branch.airborne and not f.view(RIDER).value.airborne,"real staged pose and velocity")
	permission.active=false
	check(not f.commit_step(token).ok and f.view(RIDER).value.position==start,"revoked launch rolls back even without a drive")
	permission.active=true
	token=f.begin_step(1).value
	check(f.request_jump(RIDER,credential,token).ok,"retry jump")
	if travel: f.apply_move_intent(token,{"actor_handle":RIDER,"desired_direction":[1000000,0,0],"speed_fraction":1.0,"stance":"sprint"},credential)
	check(f.stage_step(1,DT,token).ok and f.view(RIDER,token).value==branch and f.commit_step(token).ok,"same-tick launch replay")
	var apex: float = branch.position.y
	var landed := false
	var synced := false
	for t in range(2,100):
		if not check(f.step(t,DT).ok,"Jolt flight"): return false
		var pose: Dictionary=f.view(RIDER).value
		apex=maxf(apex,pose.position.y)
		var projected: Dictionary=f.read_poses(roster.value).value
		check(projected.positions[0]==pose.position and projected.velocities[0]==pose.velocity,"roster and individual agree through flight")
		if not synced and pose.position.y>0.8:
			var body := {"team_key":0,"handle":RIDER,"position":pose.position}
			check(engine.field_stage_bodies(SCOPE,[body]).ok and engine.field_commit_bodies(SCOPE).ok,"publish flying body to Jolt")
			var ray := []
			for y in [0.2,pose.position.y+0.9]:
				ray.append({"from":[roundi(pose.position.x*1000)-1000,roundi(y*1000),roundi(pose.position.z*1000)],
					"to":[roundi(pose.position.x*1000)+1000,roundi(y*1000),roundi(pose.position.z*1000)]})
			var hits: Dictionary=engine.field_sweep(SCOPE,ray,t)
			check(hits.ok and hits.value.any(func(h):return h.query_index==1 and h.get("target")==RIDER) and not hits.value.any(func(h):return h.query_index==0 and h.get("target")==RIDER),"actual elevated hurtbox clears ground-level ray")
			synced=true
		if not pose.airborne:
			landed=true
			check(absf(pose.position.y)<0.015 and is_zero_approx(pose.velocity.y),"ray-supported landing")
			check(not travel or pose.position.x>start.x+0.4,"horizontal movement during flight")
			break
	if roof: check(apex>0.35 and apex<0.56,"head clipped to actual raised ceiling")
	else: check(apex>0.85 and apex<1.1 and synced,"unobstructed apex")
	check(landed,"flight lands")
	print("FIELD_JUMP start=",start," apex=",apex," landed=",landed)
	return landed

func no_launch(start: Vector3,expected: String) -> void:
	var f := Field.new(engine,SCOPE,func(_scope,_h,_ctx,_tick):return true)
	f.spawn(RIDER,start)
	var stage: Variant=f.begin_step(1).value
	var denied: Dictionary=f.request_jump(RIDER,credential,stage)
	check(not denied.ok and denied.error.field==expected and not f.view(RIDER,stage).value.airborne,"launch rejected for "+expected)
	f.rollback_step(stage)

func run() -> void:
	engine=Adapter.new(root,true)
	var opened: Dictionary=engine.open_scope(SCOPE)
	var scene := {"id":"test:scene/profile","simulation_scene":"res://tests/p2/mount_profile/field.tscn"}
	check(opened.ok and engine.load_scene(scene,opened.value).ok,"actual arena loaded")
	var ready:=false
	for i in 90:
		await physics_frame
		var sync: Dictionary=engine.sync_navigation(SCOPE)
		if sync.ok and sync.value.status=="applied":
			var path: Dictionary=engine.query_path_batch([{"from":[-20000,0,8000],"to":[8000,0,8000]}],sync.value.applied_revision,SCOPE)
			if path.ok and path.value[0].reachable and not engine.field_los(SCOPE,Vector3(-2,0,0),Vector3(2,0,0)):
				ready=true
				break
	if check(ready,"navigation synchronized, wall blocks ray"):
		group_case()
		drive_case()
		check(jump_case(Vector3(-19,0,-8),false,true),"grounded moving launch")
		check(jump_case(Vector3(-7,0,-8),true,false),"ceiling and stationary authority")
		no_launch(Vector3(7,0,-8),"jump_headroom")
		no_launch(Vector3(34,0,-8),"jump_ground")
	engine.release_scope(SCOPE)
	print("MOUNT_PROFILE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
