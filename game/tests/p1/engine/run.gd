extends SceneTree
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const Arena := {"id":"base:scene/arena","simulation_scene":"res://tests/p1/engine/arena.tscn"}
var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var adapter := Adapter.new(root,true)
	var token: Dictionary = adapter.open_scope("m").value
	var loaded := adapter.load_scene(Arena,token)
	check(loaded.ok,"load collision and nav scene")
	var another := adapter.load_scene(Arena,token)
	check(another.ok and loaded.value.lease_id != another.value.lease_id,"independent claims on the same scene")
	check(adapter.release_lease(another.value).ok and not adapter.release_lease(another.value).ok,
		"double release cannot destroy another caller's scene")
	var initial := failures
	for i in 120:
		await physics_frame
		if adapter.sync_navigation("m").value.status == "applied":
			break
	var previous: int = adapter.sync_navigation("m").value.applied_revision
	var req := [{"from":[-4500,0,0],"to":[4500,0,0]}]
	var route := adapter.query_path_batch(req,previous,"m")
	check(route.ok and not route.value[0].reachable,"closed gate")
	var change := adapter.apply_nav_links([{"link_id":"gate","enabled":true}],"m")
	check(change.ok and change.value.status=="pending" and change.value.applied_revision == previous,"request does not publish")
	check(not adapter.query_path_batch(req,previous,"m").ok,"no path returned from pending topology")
	check(not adapter.query_path_batch(req,previous+1,"m").ok,"future revision rejected")
	for i in 120:
		await physics_frame
		if adapter.sync_navigation("m").value.status == "applied":
			break
	route = adapter.query_path_batch(req,previous+1,"m")
	check(route.ok and route.value[0].reachable,"actual synced route goes across open link")
	check(not adapter.query_path_batch(req,previous,"m").ok,"old topology rejected after sync")
	print("T-INF-ENGINE-01 ","PASS" if failures==initial else "FAIL")
	initial = failures
	var ray := {"from":[-10000,1000,0],"to":[10000,1000,0]}
	var sphere := {"from":[-10000,1000,250],"to":[10000,1000,250],"radius_mm":150}
	var stamp := {"scope_id":"m","tick":1}
	var hits := adapter.query_sweep_batch([ray,sphere],stamp)
	check(hits.ok and hits.value.size() == 4,"20 m ray and grazing sphere each traverse two 40 mm bodies")
	if hits.ok and hits.value.size()==4:
		for i in [0,2]:
			check(hits.value[i].entity_handle=="near" and hits.value[i+1].entity_handle=="far","physical hit order")
			check(hits.value[i].fraction_ppm<hits.value[i+1].fraction_ppm,"monotonic time of impact")
		check(adapter.query_sweep_batch([ray,sphere],stamp).value==hits.value,"repeat stable sweep")
		ray["ignored_handles"] = ["near"]
		check(adapter.query_sweep_batch([ray],stamp).value.size()==1,"ignore handle")
	var overlap := adapter.query_sweep_batch([{"from":[-2000,1000,0],"to":[10000,1000,0],"radius_mm":50}],stamp)
	check(overlap.ok and overlap.value.size()==2 and overlap.value[0].entity_handle=="near" and overlap.value[0].fraction_ppm==0, "report initial overlap before later sweep contact")
	var long_hit := adapter.query_sweep_batch([{"from":[-1000000,1000,250],"to":[1000000,1000,250],"radius_mm":150}],stamp)
	check(long_hit.ok and long_hit.value.size()==2,"2 km continuous sphere detects both thin bodies")
	print("T-INF-ENGINE-02 ","PASS" if failures==initial else "FAIL", " hits=",hits.get("value",[]))
	initial = failures
	check(not adapter.instantiate_visual({}, "m").ok,"headless refuses presentation")
	check(adapter.release_scope("m").released==1,"release real root")
	var client := Adapter.new(root, false)
	var visual_scope := client.open_scope("visual-control")
	var server_scope := adapter.open_scope("visual-control")
	check(visual_scope.ok and server_scope.ok, "open separate runtimes")
	check(client.instantiate_visual({"visual_scene":Arena.simulation_scene},"visual-control").ok, "load client-only scene with real colliders")
	await physics_frame
	await physics_frame
	var comparison := {"scope_id":"visual-control", "tick":2}
	var only_ray := {"from":[-10000,1000,0],"to":[10000,1000,0]}
	var client_hits := client.query_sweep_batch([only_ray],comparison)
	var server_hits := adapter.query_sweep_batch([only_ray],comparison)
	check(client_hits.ok and server_hits.ok and client_hits.value.is_empty() and client_hits.value == server_hits.value, "presentation cannot affect authority")
	client.release_scope("visual-control")
	adapter.release_scope("visual-control")
	print("P1-ENGINE-HEADLESS-SLICE ","PASS" if failures==initial else "FAIL")
	initial = failures
	var samples: Array[int] = []
	var base_nodes := root.get_child_count()
	for i in 50:
		var started := Time.get_ticks_usec()
		var scope := "repeat"
		token = adapter.open_scope(scope).value
		var lease := adapter.load_scene({"id":"base:scene/root","simulation_scene":Adapter.DEFAULT_SCENE},token)
		check(lease.ok,"load isolated scene")
		var foreign := {"scope_id":scope,"generation":token.generation}
		check(not adapter.load_scene(Arena,foreign).ok,"copied generation does not authorize loading")
		var pending := adapter.begin_scene_load(Arena,token)
		check(pending.ok,"real pending resource request")
		var released := adapter.release_scope(scope)
		check(released.released==1 and released.cancelled==1,"barrier releases scene and request")
		check(not adapter.finish_scene_load(pending.value).ok and not adapter.load_scene(Arena,token).ok,"late completion rejected")
		check(adapter.counts()=={"scopes":0,"leases":0,"requests":0} and root.get_child_count()==base_nodes,"no growing handles or nodes")
		samples.append(Time.get_ticks_usec()-started)
	samples.sort()
	print("T-INF-ENGINE-04 ","PASS" if failures==initial else "FAIL"," loops=50 median_us=",samples[24],
		" p95_us=",samples[47]," max_us=",samples[-1])
	print("ENGINE failures=",failures)
	quit(1 if failures else 0)
