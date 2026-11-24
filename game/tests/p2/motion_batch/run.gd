extends SceneTree
const Field = preload("res://mission/movement/ports/field_movement.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const R = preload("res://contracts/result.gd")
const SCOPE := "motion-batch-field"
const DT := 1.0/30.0
var failures := 0
var checks := 0

class Meter:
	var engine: RefCounted
	var queries := 0
	var reject := false
	var callback: Callable
	func _init(adapter: RefCounted) -> void: engine = adapter
	func sync_navigation(scope: String) -> Dictionary: return engine.sync_navigation(scope)
	func query_path_batch(batch: Array, revision: int, scope: String) -> Dictionary:
		queries += batch.size()
		if callback.is_valid(): callback.call()
		var reply: Dictionary = engine.query_path_batch(batch,revision,scope)
		return R.fail("Unavailable","injected_after_native_query") if reject else reply

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func h(index: int, gen := 1) -> Dictionary:
	return {"index":index,"generation":gen}

func _initialize() -> void: run.call_deferred()

func identity(engine: RefCounted) -> bool:
	var mov := Field.new(engine,SCOPE)
	var other := Field.new(engine,SCOPE)
	var high := h(4294967295)
	check(mov.spawn(high,Vector3(-4,0,0)).ok and mov.spawn(h(2),Vector3(-10,0,1)).ok,"two initial bodies")
	var handles := [h(2),high]
	var token: RefCounted = mov.bind_roster(handles).value
	handles[0].index = 97
	var old := mov.read_poses(token)
	check(old.ok and old.value.positions == PackedVector3Array([Vector3(-10,0,1),Vector3(-4,0,0)]),"ordered uint32 handles copied")
	old.value.positions[0] = Vector3.ONE
	check(mov.read_positions(token).value[0] == Vector3(-10,0,1),"packed outputs detached")
	check(other.spawn(h(2),Vector3.ZERO).ok and not other.read_poses(token).ok and not mov.read_positions(RefCounted.new()).ok,"same named scope still isolated")
	check(not mov.bind_roster([h(2),h(2)]).ok and not mov.bind_roster([h(2,0)]).ok and mov.read_poses(mov.bind_roster([]).value).value.positions.is_empty(),"duplicate, invalid, empty")
	var stage: RefCounted = mov.begin_step(1).value
	check(mov.despawn(h(2),stage).ok and mov.spawn(h(2,2),Vector3(-12,0,3),"foot",Vector3.RIGHT,stage).ok,"candidate replacement")
	var reborn: RefCounted = mov.bind_roster([h(2,2)],stage).value
	check(mov.read_positions(token).ok and not mov.read_positions(token,stage).ok and not mov.read_positions(reborn).ok,"committed and speculative generations separate")
	check(not mov.spawn(h(9),Vector3.ZERO).ok and not mov.commit_step(stage).ok and not other.rollback_step(stage).ok,"stage ownership and phase")
	check(mov.set_corridor("early",Vector3(-12,0,3),Vector3(-10,0,3),"foot",stage).ok and mov.assign(h(2,2),"early",Vector3.ZERO,stage).ok,"pre-motion intent assignment")
	var stepped := mov.stage_step(1,DT,stage)
	check(stepped.ok and mov.read_positions(reborn,stage).value[0].x > -12 and not mov.view(h(2,2)).ok,"downstream sees staged motion")
	check(not mov.despawn(h(2,2),stage).ok and not mov.step(1,DT).ok,"seal candidate")
	check(mov.rollback_step(stage).ok and mov.view(h(2)).ok and not mov.view(h(2,2)).ok and not mov.read_positions(reborn,stage).ok,"downstream failure restores original")
	var retry: RefCounted = mov.begin_step(1).value
	check(mov.despawn(h(2),retry).ok and mov.spawn(h(2,2),Vector3(-12,0,3),"foot",Vector3.RIGHT,retry).ok,"retry identical public number")
	check(not mov.read_positions(reborn,retry).ok,"abandoned spawn token never resurrected")
	var valid: RefCounted = mov.bind_roster([h(2,2)],retry).value
	check(mov.stage_step(1,DT).ok and mov.commit_step(retry).ok and mov.read_positions(valid).ok and not mov.read_positions(token).ok,"commit publishes exact roster")
	check(not mov.commit_step(retry).ok and not mov.rollback_step(retry).ok and not mov.stage_step(1,DT).ok,"stale stage or tick")
	return true

func configured(engine: RefCounted, count: int) -> Field:
	var field := Field.new(engine,SCOPE)
	for group in 20:
		var mode := "mounted" if group % 5 == 0 else "foot"
		field.set_corridor(str(group),Vector3(-34,0,0),Vector3(-29+0.005*group,0,0),mode)
	for i in count:
		var origin := Vector3(-53+(i%40)*0.9,0,-9+floori(i/40.0)*0.72)
		var mode := "mounted" if i % 5 == 0 else "foot"
		check(field.spawn(h(i),origin,mode,Vector3.RIGHT).ok and field.assign(h(i),str(i%20),origin-Vector3(-34,0,0)).ok,"mixed deployment")
	return field

func rollback_and_meter(engine: RefCounted) -> bool:
	var meter := Meter.new(engine)
	var mov := configured(meter,60)
	var control := configured(Meter.new(engine),60)
	var token: RefCounted = mov.bind_roster([h(0),h(23),h(59)]).value
	var before: Dictionary = mov.read_poses(token).value
	var stage: RefCounted = mov.begin_step(0).value
	meter.callback = func():
		check(not mov.rollback_step(stage).ok and not mov.stage_step(0,DT).ok and not mov.read_poses(token,stage).ok and mov.read_poses(token).value==before,"no reentrant candidate publication")
	var first := mov.stage_step(0,DT)
	meter.callback = Callable()
	check(first.ok and meter.queries==8 and mov.rollback_step(stage).ok,"discard successful native work")
	var replay := mov.stage_step(0,DT)
	check(replay.ok and meter.queries==8 and replay.value.total_queried==8 and mov.commit_step(replay.value.stage_token).ok,"same-tick responses reused, native budget conserved")
	for tick in 30:
		if tick>0:
			var a := mov.stage_step(tick,DT)
			check(a.ok and mov.commit_step(a.value.stage_token).ok,"advanced stage")
		check(control.step(tick,DT).ok,"reference direct step")
		for i in [0,7,23,59]:
			check(mov.view(h(i)).value==control.view(h(i)).value,"same continued positions/kinematics and path progress")
	var failed_meter := Meter.new(engine)
	failed_meter.reject = true
	var failed := configured(failed_meter,30)
	for attempt in 4:
		var r := failed.stage_step(0,DT)
		if r.ok: check(failed.rollback_step(r.value.stage_token).ok,"safe wait after budget exhaustion")
	check(failed_meter.queries==8,"failed real attempts charged once")
	failed_meter.reject = false
	check(failed.step(0,DT).ok and failed_meter.queries==8 and failed.step(1,DT).ok and failed_meter.queries==16,"failed stage allows retry and next tick budget")
	return true

func choke(engine: RefCounted) -> bool:
	var field := Field.new(engine,SCOPE)
	var reference := Field.new(engine,SCOPE)
	var handles := []
	for i in 48: handles.append(h(i))
	for mov in [field,reference]:
		var zones := [{"bounds":AABB(Vector3(-1.1,-1,-0.7),Vector3(6.2,2,1.4)),"profiles":["foot"]}]
		if not mov.set_terrain(zones).ok or not mov.set_corridor("line",Vector3(-35,0,0),Vector3(22,0,0)).ok: return false
		for i in handles.size():
			var row := floori(i/3.0)
			var lane := float(i%3-1)*1.05
			if not mov.spawn(handles[i],Vector3(-5.4-row*1.04,0,lane)).ok or not mov.assign(handles[i],"line",Vector3(11-row*1.04,0,lane)).ok: return false
	var live: RefCounted = field.bind_roster(handles).value
	var ref: RefCounted = reference.bind_roster(handles).value
	var retries := 0
	for tick in 1500:
		var old_pose: Dictionary = field.read_poses(live).value
		var candidate := field.stage_step(tick,DT)
		if not candidate.ok: return false
		if tick in [0,80,200,430,650]:
			var preview: Dictionary = field.read_poses(live,candidate.value.stage_token).value
			if not field.rollback_step(candidate.value.stage_token).ok or field.read_poses(live).value != old_pose: return false
			candidate = field.stage_step(tick,DT)
			if not candidate.ok or field.read_poses(live,candidate.value.stage_token).value != preview: return false
			retries += 1
		if not field.commit_step(candidate.value.stage_token).ok or not reference.step(tick,DT).ok: return false
		var poses: Dictionary = field.read_poses(live).value
		if poses != reference.read_poses(ref).value: return false
		var arrived := 0
		for i in handles.size():
			var point: Vector3 = poses.positions[i]
			if point.x > -0.95 and point.x < 4.9 and absf(point.z)>0.421: return false
			if point.distance_to(old_pose.positions[i])>3.4*DT+0.0001: return false
			if field.view(handles[i]).value.arrived: arrived += 1
		if arrived==48:
			print("MOV_STAGE_CHOKE arrived=",arrived," ticks=",tick+1," downstream_rollbacks=",retries," divergent_frames=0")
			return retries==5
	return false

func p95(samples: Array) -> int:
	var ordered := samples.duplicate()
	ordered.sort()
	return ordered[ceili(0.95*ordered.size())-1]

func bench(engine: RefCounted, count: int) -> bool:
	var legacy := configured(engine,count)
	var field := configured(engine,count)
	var handles := []
	for i in count: handles.append(h(i))
	var token: RefCounted = field.bind_roster(handles).value
	var scalar := []
	var positions := []
	var poses := []
	var stages := []
	var old_frames := []
	var new_frames := []
	var max_queries := 0
	var scalar_positions := PackedVector3Array()
	var scalar_velocities := PackedVector3Array()
	var scalar_headings := PackedVector3Array()
	scalar_positions.resize(count)
	scalar_velocities.resize(count)
	scalar_headings.resize(count)
	for tick in 210:
		var start := Time.get_ticks_usec()
		var l := legacy.step(tick,DT)
		if not l.ok: return false
		var after_move := Time.get_ticks_usec()
		for i in count:
			var row: Dictionary = legacy.view(handles[i]).value
			scalar_positions[i] = row.position
			scalar_velocities[i] = row.velocity
			scalar_headings[i] = row.heading
		var end_scalar := Time.get_ticks_usec()
		var staged := field.stage_step(tick,DT)
		if not staged.ok: return false
		var after_stage := Time.get_ticks_usec()
		var state := field.read_poses(token,staged.value.stage_token)
		var after_read := Time.get_ticks_usec()
		if not field.commit_step(staged.value.stage_token).ok: return false
		var after_commit := Time.get_ticks_usec()
		var xyz := field.read_positions(token)
		var end := Time.get_ticks_usec()
		if not state.ok or not xyz.ok or xyz.value!=scalar_positions or state.value.positions!=scalar_positions or state.value.velocities!=scalar_velocities or state.value.headings!=scalar_headings:
			return false
		max_queries = maxi(max_queries,staged.value.total_queried)
		if tick >= 140:
			scalar.append(end_scalar-after_move)
			poses.append(after_read-after_stage)
			positions.append(end-after_commit)
			stages.append(after_stage-end_scalar)
			old_frames.append(end_scalar-start)
			new_frames.append(after_commit-end_scalar)
	var moving := 0
	for i in count:
		var origin := Vector3(-53+(i%40)*0.9,0,-9+floori(i/40.0)*0.72)
		if scalar_positions[i].distance_to(origin)>0.01: moving += 1
	print("MOV_BATCH people=",count," moved=",moving," samples=70 ticks=210 budget_peak=",max_queries,
		" p95_us scalar_poses=",p95(scalar)," packed_positions=",p95(positions)," packed_poses=",p95(poses),
		" stage=",p95(stages)," direct_plus_scalar=",p95(old_frames)," stage_read_commit=",p95(new_frames))
	return moving==count and max_queries<=8 and p95(poses)<p95(scalar)

func run() -> void:
	var engine := Adapter.new(root,true)
	var token := engine.open_scope(SCOPE)
	var scene := {"id":"base:scene/field_motion_batch","simulation_scene":"res://tests/p2/movement/field.tscn"}
	if not token.ok or not engine.load_scene(scene,token.value).ok:
		quit(1)
		return
	var ready := false
	for frame in 120:
		await physics_frame
		var sync: Dictionary = engine.sync_navigation(SCOPE)
		if sync.ok and sync.value.status=="applied":
			var probe := engine.query_path_batch([{"from":[-34000,0,0],"to":[-29000,0,0]}],sync.value.applied_revision,SCOPE)
			if probe.ok and probe.value[0].reachable:
				ready = true
				break
	check(ready,"real field map ready")
	if ready:
		check(identity(engine),"roster lifecycle completed")
		check(rollback_and_meter(engine),"budget and rollback completed")
		check(choke(engine),"staged choke with downstream faults")
		check(bench(engine,500),"500 live mixed field")
		check(bench(engine,1000),"1000 live mixed field")
	engine.release_scope(SCOPE)
	print("P2-BAI-002 ", "PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
