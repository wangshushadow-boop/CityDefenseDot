extends SceneTree

const Adapter = preload("res://infrastructure/engine/adapter.gd")
const Queue = preload("res://mission/movement/path_queue.gd")
const SCENE := {"id":"base:scene/nav_test", "simulation_scene":"res://tests/p2/movement/links.tscn"}
const SCOPE := "movement-fixture"
var errors := 0
var engine: RefCounted

func check(value: bool, label: String) -> void:
	if not value:
		errors += 1
		printerr("FAIL ", label)

func rejected(result: Dictionary, code: String) -> bool:
	return not result.ok and result.error.code == code

func _initialize() -> void:
	run.call_deferred()

func wait_navigation() -> bool:
	for frame in 120:
		await physics_frame
		var receipt: Dictionary = engine.sync_navigation(SCOPE)
		if receipt.ok and receipt.value.status == "applied":
			return true
	return false

func links() -> void:
	var start := errors
	var queue := Queue.new(engine, SCOPE, 8, 2)
	var tick := 0
	var origin := [0,0,0]
	for edge in [["gate",[6000,0,0]], ["ladder",[12000,2000,0]], ["breach",[18000,2000,0]]]:
		var ticket: Dictionary = queue.request_path(origin, edge[1], "foot").value
		check(queue.process_budget(tick).value.queried == 1, "closed corridor queried")
		var closed: Dictionary = queue.poll_path(ticket)
		check(closed.ok and not closed.value.reachable, "closed link " + edge[0])
		var receipt: Dictionary = engine.apply_nav_links([{"link_id":edge[0], "enabled":true}], SCOPE)
		check(receipt.ok and receipt.value.status == "pending", "link change pending")
		check(rejected(queue.poll_path(ticket), "Unavailable"), "cached negative disabled during sync")
		check(rejected(queue.request_path(origin, edge[1], "foot"), "Unavailable"), "no request on unsynced mesh")
		check(await wait_navigation(), "engine published link " + edge[0])
		check(rejected(queue.poll_path(ticket), "StaleVersion"), "old corridor rejected")
		ticket = queue.request_path(origin, edge[1], "foot").value
		tick += 1
		check(queue.process_budget(tick).value.queried == 1, "new corridor queried")
		var open: Dictionary = queue.poll_path(ticket)
		check(open.ok and open.value.reachable and open.value.points.back() == edge[1], "new link reachable")
		tick += 1
	var full: Dictionary = queue.request_path(origin, [18000,2000,0], "foot").value
	var change: Dictionary = engine.apply_nav_links([{"link_id":"gate","enabled":false}], SCOPE)
	check(change.ok and rejected(queue.process_budget(tick), "Unavailable"), "wait for actual gate closure")
	check(await wait_navigation(), "closed gate published")
	check(rejected(queue.poll_path(full), "StaleVersion"), "cached positive invalidated")
	var after_close: Dictionary = queue.request_path(origin, [18000,2000,0], "foot").value
	check(queue.process_budget(tick).ok and not queue.poll_path(after_close).value.reachable, "gate cut route")
	print("T-MOV-01 ", "PASS" if errors == start else "FAIL", " links=3 reopen_close=true")

func pressure(population: int) -> void:
	var start := errors
	var queue := Queue.new(engine, SCOPE, 24, 4)
	var tickets := []
	var begun := Time.get_ticks_usec()
	for i in population:
		var group_id := i % 20
		var goal := [500 + group_id * 20, 0, 100]
		var profile := "foot" if group_id % 2 == 0 else "mounted"
		var request: Dictionary = queue.request_path([0,0,0], goal, profile, group_id)
		check(request.ok, "formation member shares path")
		if request.ok:
			tickets.append(request.value)
	var solved := 0
	var peak := 0
	for t in 5:
		var result := queue.process_budget(t)
		if not result.ok:
			check(false, "batch failed")
			return
		solved += result.value.queried
		peak = maxi(peak, result.value.queried)
		check(queue.process_budget(t).value.queried == 0, "budget cannot be spent twice in one tick")
		if t == 0:
			check(queue.poll_path(tickets[19]).ok and rejected(queue.poll_path(tickets[0]), "Unavailable"), "priority then stable request order")
	check(solved == 20 and peak == 4, "one native path per unique corridor")
	for ticket in tickets:
		var route := queue.poll_path(ticket)
		check(route.ok and route.value.reachable, "actual cached route for every member")
	check(queue.process_budget(8).value.queried == 0, "steady frame performs no global query")
	check(rejected(queue.process_budget(7), "StaleVersion"), "reject past tick")
	print("MOV_LOAD agents=", population, " corridors=", solved, " ticks=5 max_per_tick=", peak,
		" elapsed_us=", Time.get_ticks_usec()-begun, " errors=", errors-start)

func distinct_burst(population: int) -> void:
	var queue := Queue.new(engine, SCOPE, 24, 4)
	var waiting := []
	var next_id := 0
	var completed := 0
	var tick := 0
	var rejected_count := 0
	var peak := 0
	while completed < population and tick <= population:
		while next_id < population:
			var profile := "foot" if next_id % 2 == 0 else "mounted"
			var request := queue.request_path([0,0,0], [200 + next_id,0,next_id % 3], profile)
			if not request.ok:
				check(rejected(request, "Unavailable"), "only queue capacity rejects a new path")
				rejected_count += 1
				break
			waiting.append(request.value)
			next_id += 1
		peak = maxi(peak, waiting.size())
		var batch := queue.process_budget(tick)
		if not batch.ok or batch.value.queried < 1 or batch.value.queried > 4:
			check(false, "bounded burst failed to make progress")
			return
		for i in batch.value.queried:
			var route := queue.poll_path(waiting.pop_front())
			check(route.ok and route.value.reachable, "retried distinct path served")
			completed += 1
		tick += 1
	check(completed == population and peak == 24 and rejected_count > 0, "capacity with distinct paths")
	print("MOV_BURST agents=", population, " distinct=", completed, " ticks=", tick, " peak_queued=", peak)

func bounds() -> void:
	var queue := Queue.new(engine, SCOPE, 3, 2)
	check(rejected(queue.request_path([1.5,0,0], [1,0,0], "foot"), "InvalidArgument"), "integer quantization required")
	var from := [0,0,0]
	var first := queue.request_path(from, [100,0,0], "foot")
	from[0] = 50
	var same := queue.request_path([0,0,0], [100,0,0], "foot")
	check(is_same(first.value, same.value), "request copied and shared")
	var mounted := queue.request_path([0,0,0], [100,0,0], "mounted")
	check(not is_same(first.value, mounted.value), "profile-specific cache key")
	var third := queue.request_path([0,0,0], [300,0,0], "foot")
	check(rejected(queue.request_path([0,0,0], [400,0,0], "foot"), "Unavailable"), "saturation is explicit")
	check(queue.process_budget(0).value.queried == 2 and rejected(queue.poll_path(third.value), "Unavailable"), "stable equal-priority scheduling")
	check(rejected(queue.poll_path(first.value.duplicate()), "NotFound"), "fabricated ticket denied")
	var other := Queue.new(engine, SCOPE, 3, 2)
	other.request_path([0,0,0], [100,0,0], "foot")
	check(rejected(other.poll_path(first.value), "NotFound"), "ticket belongs to its queue")
	var isolated: Dictionary = queue.poll_path(first.value).value
	isolated.points.clear()
	check(not queue.poll_path(first.value).value.points.is_empty(), "caller cannot mutate cache")
	var retry := queue.request_path([0,0,0], [400,0,0], "foot")
	check(retry.ok and queue.process_budget(1).value.queried == 2, "request can be retried after draining")
	check(queue.poll_path(retry.value).ok and rejected(queue.poll_path(first.value), "NotFound"), "completed cache has a fixed bound")

func run() -> void:
	engine = Adapter.new(root, DisplayServer.get_name() == "headless")
	var token: Dictionary = engine.open_scope(SCOPE)
	check(token.ok and engine.load_scene(SCENE, token.value).ok, "load real navigation mesh")
	if errors != 0 or not await wait_navigation():
		printerr("FAIL navigation startup")
		quit(1)
		return
	await links()
	var before := errors
	pressure(500)
	pressure(1000)
	distinct_burst(500)
	distinct_burst(1000)
	bounds()
	print("T-MOV-04 ", "PASS" if errors == before else "FAIL", " shared_requests=1500 distinct_requests=1500")
	var queue := Queue.new(engine, SCOPE)
	var ticket := queue.request_path([0,0,0], [100,0,0], "foot")
	engine.release_scope(SCOPE)
	check(rejected(queue.poll_path(ticket.value), "NotFound"), "released scope cannot serve path")
	print("MOV_QUEUE_CHECKS errors=", errors, " display=", DisplayServer.get_name())
	quit(1 if errors else 0)
