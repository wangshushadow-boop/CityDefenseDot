extends SceneTree

const Runtime = preload("res://core/runtime.gd")
const Canon = preload("res://contracts/canonical.gd")

var failures := 0
var main_thread: int

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL ",message)

func _initialize() -> void:
	main_thread = OS.get_thread_caller_id()
	var initial := failures
	var serial := replay(1)
	var parallel := replay(3)
	check(serial == parallel, "replay hash across worker counts")
	print("T-CORE-01 ", "PASS" if failures == initial else "FAIL", " digest=", serial)
	initial = failures
	cancel_late_results()
	print("T-CORE-02 ", "PASS" if failures == initial else "FAIL")
	initial = failures
	followup_budget()
	print("T-CORE-03 ", "PASS" if failures == initial else "FAIL")
	print("CORE failures=",failures)
	quit(1 if failures else 0)

func work(snapshot: Dictionary) -> Dictionary:
	OS.delay_msec(snapshot.delay)
	return {"result":snapshot.payload.n * 2, "readonly":snapshot.is_read_only() and snapshot.payload.is_read_only(),
		"off_main":OS.get_thread_caller_id() != main_thread}

func replay(worker_count: int) -> String:
	var runtime := Runtime.new("aabbccdd00001111",worker_count)
	var token: Dictionary = runtime.open_scope("world").value
	var order: Array = []
	var movement := runtime.derive_rng("world","army/actions")
	var weather := runtime.derive_rng("world","weather")
	check(movement != weather and movement == runtime.derive_rng("world","army/actions"),"independent persistent streams")
	var saved: Dictionary = runtime.snapshot_rng("world").value
	var first := movement.next_u32()
	var removed := runtime.derive_rng("world","transient")
	var before := movement.snapshot()
	var invalid_snapshot: Dictionary = saved.duplicate(true)
	invalid_snapshot["bad"] = {"algorithm_version":5,"state":"0"}
	check(not runtime.restore_rng("world",invalid_snapshot).ok and movement.snapshot() == before,"invalid restore is atomic")
	check(runtime.restore_rng("world",saved).ok, "restore RNG")
	check(movement == runtime.derive_rng("world","army/actions") and first == movement.next_u32(), "cached RNG resumes exact next draw")
	check(removed.next_u32() == -1 and not removed.restore(saved["army/actions"]).ok, "removed cached stream retired")
	var vector := runtime.derive_rng("world","vector")
	check(vector.restore({"algorithm_version":1,"state":"fedcba9876543210"}).ok,"restore high RNG bit")
	check(vector.next_u32() == 1059586262 and vector.snapshot().state == "3f2800d6691e1e74","unsigned xorshift64 reference")
	for key in ["z","b","a"]:
		var queued := runtime.schedule({"scope_id":"world","phase":"day","job_id":key,
			"due_tick":2,"priority":2 if key=="z" else 1,"run":func(): order.append(key)})
		check(queued.ok, "queue accepted")
	check(runtime.run_phase("day",1,10).executed.is_empty(), "future jobs wait")
	check(runtime.call("run_phase","day",5.5,1).error == "InvalidArgument", "dynamic float does not advance tick")
	var report := runtime.run_phase("day",2,2)
	check(report.executed == ["z","a"] and report.remaining == 1, "stable due order and budget")
	runtime.run_phase("day",2,2)
	check(order == ["z","a","b"],"callback order")
	check(runtime.run_phase("day",1,2).error == "InvalidState","old clock rejected")
	for n in [3,2,1]:
		var snapshot := {"scope_id":"world","revision":3,"delay":n*3,"payload":{"n":n},"tick":5}
		check(runtime.submit_worker(snapshot,token,{"stable_key":str(n),"run":work}).ok,"submit work")
		snapshot.payload.n = 100
	var results := []
	for result: Dictionary in runtime.collect_ready("world",3,{"tick":5}):
		check(result.value.readonly and result.value.off_main, "worker immutable isolated data on a background thread")
		results.append([result.stable_key, result.value.result])
	check(results == [["1",2],["2",4],["3",6]],"stable write set")
	var digest := Canon.hash_value([order,results,runtime.snapshot_rng("world").value])
	check(digest.ok, "replay digest")
	runtime.cancel_scope("world")
	return digest.value

func cancel_late_results() -> void:
	var runtime := Runtime.new("0000000000000001",1)
	var old: Dictionary = runtime.open_scope("mission").value
	var other := Runtime.new()
	var foreign: Dictionary = other.open_scope("mission").value
	check(not runtime.submit_worker({"scope_id":"mission","revision":2},foreign,
		{"stable_key":"foreign","run":func(_s):return 1}).ok,"foreign runtime cannot submit with equal scope values")
	other.cancel_scope("mission")
	var started := Semaphore.new()
	var job := func(s):
		started.post()
		OS.delay_msec(16)
		return s.revision
	check(runtime.submit_worker({"scope_id":"mission","revision":2},old,{"stable_key":"late","run":job}).ok,"start late worker")
	started.wait()
	check(runtime.cancel_scope("mission").discarded == 1,"cancel joins late worker")
	var current: Dictionary = runtime.open_scope("mission").value
	check(current.generation > old.generation, "new scope generation")
	check(not runtime.submit_worker({"scope_id":"mission","revision":2},old,{"stable_key":"late","run":job}).ok,"stale token rejected")
	check(runtime.collect_ready("mission",2).is_empty(), "old mission has no write set")
	var stamp := {"scope_id":"mission","revision":2,"tick":4,"nav_revision":3}
	check(runtime.submit_worker(stamp,current,{"stable_key":"new","run":func(_s):return 1}).ok,"submit new generation")
	check(runtime.call("collect_ready","mission",2.5).is_empty() and runtime.stale_worker_count()==0,"fractional revision does not consume candidates")
	check(runtime.collect_ready("mission",2,{"tick":4,"nav_revision":4}).is_empty(),"old nav revision rejected")
	stamp["control_revision"] = 6
	check(runtime.submit_worker(stamp,current,{"stable_key":"no-current","run":func(_s):return 2}).ok,"submitted stamped snapshot")
	check(runtime.collect_ready("mission",2).is_empty(),"absent current tick, nav and control cannot authorize apply")
	check(runtime.submit_worker(stamp,current,{"stable_key":"no-control","run":func(_s):return 2}).ok,"submitted partial-stamp case")
	check(runtime.collect_ready("mission",2,{"tick":4,"nav_revision":3}).is_empty(),"missing control version rejected")
	check(runtime.stale_worker_count() == 3, "stale diagnostic")
	runtime.cancel_scope("mission")

func followup_budget() -> void:
	var runtime := Runtime.new("0000000000000001",1,1,2,2)
	runtime.open_scope("world")
	var calls := []
	var rejected := []
	var listener := func(event):
		calls.append(event.event_id)
		check(runtime.run_phase("effects",1,20).error == "InvalidState","reentrant phase rejected")
		var next: Dictionary = event.duplicate(true)
		next["event_id"] = "effect-%d" % calls.size()
		var result := runtime.publish_committed([next],1)
		if not result.ok:
			rejected.append(result.error.field)
	check(runtime.subscribe("world","changed","effects",listener).ok,"subscribe")
	var event := {"event_id":"initial","scope_id":"world","revision":1,"tick":1,"type":"changed","payload":{}}
	check(not runtime.call("publish_committed",[event],1.5).ok, "fractional commit revision rejected")
	check(runtime.publish_committed([event],1).ok,"publish")
	check(calls.is_empty(),"no inline callbacks")
	for i in 3:
		var report := runtime.run_phase("effects",1,1000)
		check(report.executed.size() == 1 and calls.size() == i+1,"one notification per phase barrier")
	check(rejected == ["followup_depth"] and runtime.backpressure == 1,"bounded feedback with diagnostic")
	check(runtime.run_phase("effects",1,20).executed.is_empty(), "queue drained")
	for id in ["a","b","c"]:
		var result := runtime.schedule({"scope_id":"world","job_id":id,"phase":"effects","due_tick":1,"run":func():pass})
		check(result.ok == (id != "c"),"queue limit")
	check(runtime.backpressure == 2, "queue pressure diagnostic")
	check(runtime.cancel_scope("world").removed_jobs == 2, "cancel queued jobs")
