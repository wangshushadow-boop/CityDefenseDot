extends RefCounted
const Field = preload("res://mission/movement/ports/field_movement.gd")
const SCOPE := "moving-field"
const DT := 1.0 / 30.0
const COUNT := 48

var errors := 0
var completed := false

func expect(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		printerr("FAIL field movement: ", label)

func handle(i: int) -> Dictionary:
	return {"index":i,"generation":1}

func crowd(engine: RefCounted) -> bool:
	var before := errors
	var field := Field.new(engine,SCOPE)
	var narrow := AABB(Vector3(-1.1,-1,-0.7),Vector3(6.2,2,1.4))
	expect(field.set_terrain([{"bounds":narrow,"profiles":["foot"]}]).ok,"narrow terrain")
	expect(field.set_corridor("line", Vector3(-35,0,0), Vector3(22,0,0)).ok,"shared route")
	var last := PackedVector3Array()
	for i in COUNT:
		var row := floori(i/3.0)
		var lane := float(i%3-1)
		var start := Vector3(-5.4-row*1.04,0,lane*1.05)
		last.append(start)
		expect(field.spawn(handle(i),start).ok,"spawn")
		expect(field.assign(handle(i),"line",Vector3(11-row*1.04,0,lane*1.05)).ok,"slot")
	var queried := 0
	var yields := 0
	var escapes := 0
	var longest := 0.0
	var arrived := 0
	var elapsed := 0
	for tick in 1500:
		var step: Dictionary = field.step(tick,DT)
		if not step.ok:
			expect(false,"navigation step")
			break
		queried += step.value.queried
		yields += step.value.yielding
		arrived = 0
		for i in COUNT:
			var pose: Dictionary = field.view(handle(i)).value
			var pos: Vector3 = pose.position
			longest = maxf(longest,pos.distance_to(last[i]))
			last[i] = pos
			if pos.x > -0.95 and pos.x < 4.9 and absf(pos.z) > 0.421:
				escapes += 1
			if pose.arrived:
				arrived += 1
		elapsed = tick+1
		if arrived == COUNT:
			break
	expect(queried == 1,"one shared query")
	expect(arrived == COUNT and yields > 0 and escapes == 0,"all actors physically passed the choke")
	expect(longest <= 3.4*DT+0.0001,"no teleport")
	var removed := handle(0)
	expect(field.despawn(removed).ok and not field.view(removed).ok,"removed handle invalid")
	expect(not field.spawn(removed,Vector3.ZERO).ok,"old generation rejected")
	expect(field.spawn({"index":0,"generation":2},Vector3.ZERO).ok,"slot reuse")
	print("T-MOV-02 people=",COUNT," arrived=",arrived," ticks=",elapsed," yields=",yields,
		" queried=",queried," outside=",escapes," max_step=",longest)
	return errors == before

func horse(engine: RefCounted) -> bool:
	var before := errors
	var field := Field.new(engine,SCOPE)
	var rider := handle(0)
	field.spawn(rider,Vector3(-32,0,0),"mounted",Vector3.RIGHT)
	field.set_corridor("riders",Vector3(-32,0,0),Vector3(-6,0,0),"mounted")
	field.assign(rider,"riders")
	for tick in 66:
		expect(field.step(tick,DT).ok,"mounted acceleration")
	var running: Dictionary = field.view(rider).value
	var speed: float = running.velocity.length()
	field.set_corridor("riders",running.position,Vector3(-42,0,3),"mounted")
	field.step(66,DT)
	var turning: Dictionary = field.view(rider).value
	var yaw: float = running.heading.angle_to(turning.heading)
	expect(speed > 7.0 and yaw > 0.01 and yaw <= 3.0*DT/(1.0+0.22*speed)+0.0001,"mounted turn rate depends on speed")
	expect(turning.velocity.length() >= speed-8.0*DT-0.001,"mounted braking bound")
	# Same geometric route and open link as infantry, with a narrow foot-only approach.
	field.set_terrain([{"bounds":AABB(Vector3(-2,-1,-0.7),Vector3(7,2,1.4)),"profiles":["foot"]}])
	field.set_corridor("riders",turning.position,Vector3(18,0,0),"mounted")
	var max_x := -INF
	var blocked := false
	for tick in range(67,900):
		expect(field.step(tick,DT).ok,"restricted approach")
		var pose: Dictionary = field.view(rider).value
		max_x = maxf(max_x,pose.position.x)
		blocked = blocked or pose.blocked == "yield"
	expect(blocked and max_x < -2.0,"mounted unit stopped before the foot-only link")
	print("T-MOV-03 speed_mps=",speed," yaw_radians=",yaw," restricted_max_x=",max_x," blocked=",blocked)
	return errors == before

func large_field(engine: RefCounted, population: int) -> bool:
	var field := Field.new(engine,SCOPE)
	for group in 20:
		var profile := "mounted" if group % 5 == 0 else "foot"
		field.set_corridor(str(group),Vector3(-34,0,0),Vector3(-29+0.005*group,0,0),profile)
	var first: Vector3
	for i in population:
		var p := Vector3(-53+(i%40)*0.9,0,-9+floori(i/40.0)*0.72)
		var profile := "mounted" if i % 5 == 0 else "foot"
		if i == 0:
			first = p
		if not field.spawn(handle(i),p,profile,Vector3.RIGHT).ok or not field.assign(handle(i),str(i%20),p-Vector3(-34,0,0)).ok:
			return false
	var samples: Array[int] = []
	var queries := 0
	var checks := 0
	for tick in 24:
		var before := Time.get_ticks_usec()
		var receipt: Dictionary = field.step(tick,DT)
		samples.append(Time.get_ticks_usec()-before)
		if not receipt.ok:
			return false
		queries += receipt.value.queried
		checks = maxi(checks,receipt.value.neighbour_checks)
	samples.sort()
	var moved := first.distance_to(field.view(handle(0)).value.position)
	print("MOV_ACTIVE people=",population," ticks=24 queries=",queries," first_m=",moved,
		" max_neighbour_checks=",checks," tick_p95_us=",samples[22])
	return queries == 20 and moved > 0.01 and checks <= population * 48 * 3

func live_close(tree: SceneTree, engine: RefCounted) -> bool:
	var field := Field.new(engine,SCOPE)
	var actor := handle(0)
	field.spawn(actor,Vector3(-8,0,0))
	field.set_corridor("bridge",Vector3(-8,0,0),Vector3(12,0,0))
	field.assign(actor,"bridge")
	if not field.step(0,DT).ok:
		return false
	var old_position: Vector3 = field.view(actor).value.position
	for enabled in [false,true]:
		if not engine.apply_nav_links([{"link_id":"bridge","enabled":enabled}],SCOPE).ok:
			return false
		var next_tick := 2 if enabled else 1
		var pending: Dictionary = field.step(next_tick,DT)
		if pending.ok or pending.error.code != "Unavailable" or field.view(actor).value.position != old_position:
			return false
		var ready := false
		for frame in 120:
			await tree.physics_frame
			if engine.sync_navigation(SCOPE).value.status == "applied":
				ready = true
				break
		if not ready or not field.step(next_tick,DT).ok:
			return false
		var pose: Dictionary = field.view(actor).value
		if not enabled and (pose.position != old_position or pose.blocked != "no_route" or pose.velocity != Vector3.ZERO):
			return false
	return field.view(actor).value.position.x > old_position.x

func run(tree: SceneTree, engine: RefCounted) -> int:
	var token: Dictionary = engine.open_scope(SCOPE)
	if not token.ok or not engine.load_scene({"id":"base:scene/moving_field","simulation_scene":"res://tests/p2/movement/field.tscn"},token.value).ok:
		return 1
	var ready := false
	for frame in 120:
		await tree.physics_frame
		var sync: Dictionary = engine.sync_navigation(SCOPE)
		if sync.ok and sync.value.status == "applied":
			var result: Dictionary = engine.query_path_batch([{"from":[-35000,0,0],"to":[22000,0,0]}],sync.value.applied_revision,SCOPE)
			if result.ok and result.value[0].reachable:
				ready = true
				break
	if ready:
		expect(crowd(engine),"T-MOV-02 completed")
		expect(horse(engine),"T-MOV-03 completed")
		expect(large_field(engine,500),"500 active mixed agents")
		expect(large_field(engine,1000),"1000 active mixed agents")
		expect(await live_close(tree, engine),"active corridor invalidation and resumption")
	else:
		expect(false,"real navmesh and enabled bridge ready")
	engine.release_scope(SCOPE)
	completed = true
	return errors
