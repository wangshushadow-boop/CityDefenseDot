extends SceneTree
const Vis = preload("res://presentation/visuals/ports/field_visuals.gd")
const Melee = preload("res://mission/combat/melee.gd")
const R = preload("res://contracts/result.gd")
const A := {"index":0,"generation":1}
const B := {"index":1,"generation":1}
var failures := 0
var vis: Vis

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	call_deferred("_run")

func actor(handle: Dictionary, role: String, at: Vector3, team: int) -> Dictionary:
	return {"handle":handle,"role":role,"team":team,"position":at,"heading":Vector3.BACK,
		"velocity":Vector3.ZERO,"phase":"Ready","since":0,"direction":""}

func fig(id: int) -> Node3D:
	return vis.find_child("Agent_%d_1"%id,true,false)

func controls() -> void:
	var ra := actor(A,"cavalry",Vector3(1,0,0),0)
	var rb := actor(B,"mount",Vector3.ZERO,0)
	var rc := actor({"index":2,"generation":1},"archer",Vector3(2,0,0),1)
	ra.mount_handle = B
	var missile := {"id":"a","position":Vector3.UP,"direction":Vector3.FORWARD}
	check(vis.apply_snapshot({"scope_id":"test","tick":1,"actors":[ra,rb,rc],"projectiles":[missile]}).ok,"accept mixed roles")
	vis.render_interpolated(1,Vector3.ZERO)
	check(vis.report().near_skeletons==3 and vis.report().mounts==1 and vis.report().projectiles==1,"live skeletons and arrow")
	check(fig(0).position.y > .40 and fig(0).position.y < .85 and absf(fig(0).position.x)<.15,"registered horse torso anchors rider hips")
	var archer := fig(2)
	var helmet := archer.find_child("garment-hat",true,false) as MeshInstance3D
	check(helmet != null and helmet.material_override.vertex_color_use_as_albedo and helmet.material_override.vertex_color_is_srgb,"imported vertex paint visible on close meshes")
	var crossbow := archer.find_child("attach-righthand-mesh",true,false) as MeshInstance3D
	check(crossbow != null and crossbow.skin != null and crossbow.visible,"equipped crossbow uses skin weights")
	rc.weapon_slot = 0
	rc.position = Vector3(6,0,0)
	ra.mount_handle = null
	check(vis.apply_snapshot({"scope_id":"test","tick":2,"actors":[ra,rb,rc]}).ok,"next frame")
	vis.render_interpolated(.5,Vector3.ZERO)
	check(fig(2).position.x==4 and fig(0).position.y==0,"interpolation and dismount")
	vis.render_interpolated(1,Vector3.ZERO)
	check(not crossbow.visible,"melee slot hides ranged weapon")
	var early := {"type":"hit","actor_handle":A,"event_id":"early","confirmed":true,"position":Vector3.ZERO}
	var deferred_hit := vis.consume_view_events("test",3,[early])
	check(not deferred_hit.ok and deferred_hit.error.retryable and vis.report().impacts==0,"future effect waits for its snapshot")
	var before := vis.report()
	check(not vis.apply_snapshot({"scope_id":"other","tick":3,"actors":[]}).ok,"foreign scope")
	check(not vis.apply_snapshot({"scope_id":"test","tick":2,"actors":[]}).ok,"stale snapshot")
	check(not vis.apply_snapshot({"scope_id":"test","tick":3,"actors":[ra,ra]}).ok and vis.report()==before,"reject duplicate atomically")
	var hit := {"type":"hit","actor_handle":A,"event_id":"h","confirmed":false}
	vis.consume_view_events("test",2,[hit])
	check(vis.report().impacts==0,"predicted hit does not create confirmed feedback")
	hit.confirmed = true
	vis.consume_view_events("test",2,[hit,hit,{"type":"downed","event_id":"d","actor_handle":B,"confirmed":true}])
	check(vis.report().impacts==1 and vis.report().corpses==1,"bounded confirmed effects deduplication")
	vis.render_interpolated(1,Vector3(300,0,0))
	check(vis.report().far_animated_instances==3 and vis.report().near_skeletons==0,"distance switches to shared mesh poses")
	check(vis.apply_snapshot({"scope_id":"test","tick":3,"actors":[ra,rb,rc]}).ok,"publish next snapshot")
	check(vis.consume_view_events("test",3,[early,early]).ok and vis.report().impacts==2,"retried effect applied once")
	check(vis.apply_snapshot({"scope_id":"test","tick":190,"actors":[]}).ok,"release actors")
	vis.render_interpolated(1,Vector3.ZERO)
	check(vis.report().corpses==0 and vis.report().impacts==0,"visual lifetimes")
	vis.release_scope("test")
	check(vis.get_child_count()==0 and vis.report().visible_actors==0,"scope cleanup")

func replay(scope: String, eye: Vector3, direction: String) -> Array:
	var sim := Melee.new()
	sim.add_actor(A)
	sim.add_actor(B)
	var results := []
	var attack_pose := Quaternion.IDENTITY
	check(vis.open_field(scope).ok,"new replay scope")
	for tick in range(1,15):
		var inputs := []
		var changes := {1:"start",3:"hold",8:"release"}
		if changes.has(tick):
			inputs.append({"actor_handle":A,"input_phase":changes[tick],"direction":direction,"weapon_slot":0,"target_hint":B})
		var step := sim.step(tick,inputs,func(_t,swings):
			var contacts := []
			for swing in swings:
				contacts.append({"attacker":A,"attack_id":swing.attack_id,"target":B,"contact_order":0})
			return R.ok(contacts))
		check(step.ok,"real COM fixed step")
		var a := actor(A,"infantry",Vector3.ZERO,0)
		var b := actor(B,"infantry",Vector3.BACK,1)
		a.merge(sim.view(A).value,true)
		b.merge(sim.view(B).value,true)
		var snap := {"scope_id":scope,"tick":tick,"actors":[a,b]}
		var original := snap.duplicate(true)
		check(vis.apply_snapshot(snap).ok,"consume combat read models")
		if eye == Vector3.ZERO:
			for sample in [.25,.5,.75,1.0]:
				vis.render_interpolated(sample,eye)
		elif tick%2==0:
			vis.render_interpolated(1.0,eye)
		check(snap==original,"render does not alter authoritative projection")
		if tick==9 and fig(0):
			var skeleton := fig(0).find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
			attack_pose = skeleton.get_bone_pose_rotation(skeleton.find_bone("RightArm"))
		results.append([a.phase,b.hp,step.value.hits])
	check(sim.view(B).value.hp==86,"real charged hit applied once")
	vis.release_scope(scope)
	return [results,attack_pose]

func _run() -> void:
	vis = Vis.new()
	root.add_child(vis)
	var opened := vis.open_field("test")
	check(opened.ok,"BASE imported field models")
	if opened.ok:
		controls()
		var poses := []
		for dir: String in ["left","right","up","thrust"]:
			var near_run := replay("close-"+dir,Vector3.ZERO,dir)
			var far_run := replay("distant-"+dir,Vector3(250,0,0),dir)
			check(near_run[0]==far_run[0],"identical authoritative actions, damage and HP across LOD")
			for prior: Quaternion in poses:
				check(prior.angle_to(near_run[1])>.025,"distinct active weapon shoulder pose")
			poses.append(near_run[1])
	vis.free()
	print("VIS_FUNCTIONAL failures=",failures)
	quit(int(failures>0))
