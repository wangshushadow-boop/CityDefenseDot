extends SceneTree

const Adapter = preload("res://infrastructure/engine/adapter.gd")
const Mov = preload("res://mission/movement/ports/field_movement.gd")
const PLAIN := {"id":"field:scene/river_plain","simulation_scene":"res://content/base/field/river_plain.tscn"}
var adapter: Adapter
var sweeps := 0
var paths := 0

func sync_navigation(id: String) -> Dictionary:
	return adapter.sync_navigation(id)

func query_path_batch(rows: Array, revision: int, id: String) -> Dictionary:
	paths+=rows.size()
	return adapter.query_path_batch(rows,revision,id)

func query_sweep_batch(rows: Array, stamp: Dictionary) -> Dictionary:
	sweeps+=rows.size()
	return adapter.query_sweep_batch(rows,stamp)

func _initialize() -> void:
	run.call_deferred()

class Meter:
	var tree: SceneTree
	func _init(owner: SceneTree) -> void: tree=owner
	func sync_navigation(id: String) -> Dictionary: return tree.sync_navigation(id)
	func query_path_batch(rows: Array,r: int,id: String) -> Dictionary: return tree.query_path_batch(rows,r,id)
	func query_sweep_batch(rows: Array,stamp: Dictionary) -> Dictionary: return tree.query_sweep_batch(rows,stamp)

func bench(n: int) -> bool:
	var id:="active-drivers/"+str(n)
	var scope:=adapter.open_scope(id)
	if not scope.ok or not adapter.load_scene(PLAIN,scope.value).ok: return false
	for frame in 30:
		await physics_frame
		var nav:=adapter.sync_navigation(id)
		if nav.ok and nav.value.status=="applied":
			var path:=adapter.query_path_batch([{"from":[-50000,0,-25000],"to":[-32000,0,-25000]}],nav.value.applied_revision,id)
			if path.ok and path.value[0].reachable and path.value[0].points.size()>1: break
			if frame==29:
				print("navigation not ready ",path)
				return false
	var context:=RefCounted.new()
	var motion:=Mov.new(Meter.new(self),id,func(_s,_h,ctx,_t):return is_same(ctx,context))
	var roster:=[]
	var initial:=PackedVector3Array()
	for i in n:
		var handle:={"index":i,"generation":1}
		var at:=Vector3(-50+float(i%40)*1.5,0,-25+floori(float(i)/40)*1.5)
		roster.append(handle)
		initial.append(at)
		if not motion.spawn(handle,at,"mounted" if i%5==0 else "foot",Vector3.RIGHT).ok: return false
	var token: RefCounted=motion.bind_roster(roster).value
	sweeps=0
	paths=0
	var samples:=PackedInt64Array()
	var hash_state:=HashingContext.new()
	hash_state.start(HashingContext.HASH_SHA256)
	for tick in 200:
		var stage: Variant=motion.begin_step(tick).value
		if tick==0:
			for h in roster:
				var drive:={"actor_handle":h,"desired_direction":[1000000,0,0],"speed_fraction":1,"stance":"walk"}
				if not motion.apply_move_intent(stage,drive,context).ok: return false
		var start:=Time.get_ticks_usec()
		var stepped:=motion.stage_step(tick,1.0/60.0,stage)
		var elapsed:=Time.get_ticks_usec()-start
		if not stepped.ok or not motion.commit_step(stage).ok: return false
		if tick>=140: samples.append(elapsed)
		var pose: Dictionary=motion.read_poses(token).value
		hash_state.update(pose.positions.to_byte_array())
		hash_state.update(pose.velocities.to_byte_array())
	var moved:=0
	var final: PackedVector3Array=motion.read_positions(token).value
	for i in n:
		if initial[i].distance_to(final[i])>0.01: moved+=1
	samples.sort()
	print("MOV_SWEEP_AB people=",n," moved=",moved," steps=200 samples=",samples.size(),
		" real_sweeps=",sweeps," real_paths=",paths," median_us=",samples[29]," p95_us=",samples[56],
		" replay_sha256=",hash_state.finish().hex_encode())
	adapter.release_scope(id)
	return moved==n and sweeps>n and paths>=n

func run() -> void:
	adapter=Adapter.new(root,true)
	var ok: bool=await bench(500) and await bench(1000)
	print("MOV_SWEEP_AB ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
