extends RefCounted
## A scheduler belongs to one runtime. Its owning thread drives all public methods.
const R = preload("res://contracts/result.gd")
const Values = preload("res://contracts/values.gd")
const Schema = preload("res://contracts/schema.gd")
const Canon = preload("res://contracts/canonical.gd")
const Stream = preload("res://core/random_stream.gd")
const Workers = preload("res://core/worker_queue.gd")

var _seed: String
var _generation := 0
var _scopes := {}
var _queue: Array[Dictionary] = []
var _workers: Workers
var _last_tick := {}
var _running := false
var _depth := -1
var _phase_limit: int
var _capacity: int
var _max_depth: int
var backpressure := 0

func _init(world_seed: String = "0000000000000000", worker_count: int = 1,
		max_jobs_per_phase: int = 128, max_queue: int = 4096, max_followup_depth: int = 8) -> void:
	_seed = world_seed
	_capacity = maxi(1, max_queue)
	_phase_limit = maxi(1, max_jobs_per_phase)
	_max_depth = maxi(0, max_followup_depth)
	_workers = Workers.new(maxi(0, worker_count), _capacity)

func open_scope(scope: String) -> Dictionary:
	if scope.is_empty():
		return R.fail("InvalidArgument","scope_id")
	if _scopes.has(scope):
		return R.fail("Conflict","scope_id")
	_generation += 1
	var token := {"scope_id":scope, "generation":_generation}
	token.make_read_only()
	_scopes[scope] = {"token":token,"streams":{},"listeners":[]}
	return R.ok(token)

func derive_rng(scope: String, stream_key: String) -> Stream:
	if not _scopes.has(scope) or stream_key.is_empty():
		return null
	var streams: Dictionary = _scopes[scope].streams
	if not streams.has(stream_key):
		var digest := Canon.hash_value([_seed,scope,stream_key])
		if not digest.ok:
			return null
		streams[stream_key] = Stream.new(digest.value.left(16))
	return streams[stream_key]

func snapshot_rng(scope: String) -> Dictionary:
	if not _scopes.has(scope):
		return R.fail("NotFound","scope_id")
	var snapshot := {}
	for key: String in _scopes[scope].streams:
		snapshot[key] = _scopes[scope].streams[key].snapshot()
	return R.ok(snapshot)

func restore_rng(scope: String, snapshot: Dictionary) -> Dictionary:
	if not _scopes.has(scope):
		return R.fail("NotFound","scope_id")
	var restored := {}
	for key in snapshot:
		if typeof(key) != TYPE_STRING or key.is_empty() or typeof(snapshot[key]) != TYPE_DICTIONARY:
			return R.fail("InvalidArgument","streams")
		var stream := Stream.new("0000000000000001")
		var checked := stream.restore(snapshot[key])
		if not checked.ok:
			return checked
		restored[key] = stream
	var existing: Dictionary = _scopes[scope].streams
	for key in existing:
		var cached: Stream = existing[key]
		if restored.has(key):
			cached.restore(snapshot[key])
			restored[key] = cached
		else:
			cached.retire()
	_scopes[scope].streams = restored
	return R.ok()

func schedule(job: Dictionary) -> Dictionary:
	if typeof(job.get("scope_id")) != TYPE_STRING or not _scopes.has(job.scope_id):
		return R.fail("NotFound","scope_id")
	if job.has("generation") and job.generation != _scopes[job.scope_id].token.generation:
		return R.fail("StaleVersion","generation")
	for field in ["phase","job_id"]:
		if typeof(job.get(field)) != TYPE_STRING or job[field].is_empty():
			return R.fail("InvalidArgument",field)
	if not Values.integer(job.get("due_tick")) or not Values.integer(job.get("priority",0), -Values.MAX_INTEGER):
		return R.fail("InvalidArgument","schedule")
	if typeof(job.get("run")) != TYPE_CALLABLE or not job.run.is_valid() or job.get("budget_class","normal") not in ["normal","urgent"]:
		return R.fail("InvalidArgument","job")
	if _depth + 1 > _max_depth or _queue.size() >= _capacity:
		backpressure += 1
		return R.fail("Unavailable","followup_depth" if _depth + 1 > _max_depth else "queue")
	for prior in _queue:
		if prior.scope_id == job.scope_id and prior.job_id == job.job_id:
			return R.fail("Conflict","job_id")
	_queue.append({"scope_id":job.scope_id,"generation":_scopes[job.scope_id].token.generation,
		"phase":job.phase,"job_id":job.job_id,
		"due_tick":job.due_tick,"priority":job.get("priority",0),"run":job.run,
		"urgent":job.get("budget_class","normal") == "urgent","depth":_depth + 1})
	return R.ok(job.job_id)

static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.due_tick != b.due_tick:
		return a.due_tick < b.due_tick
	if a.priority != b.priority:
		return a.priority > b.priority
	if a.scope_id != b.scope_id:
		return a.scope_id < b.scope_id
	return a.job_id < b.job_id

func run_phase(phase: String, tick: Variant, budget: Variant, urgent_reserve: Variant = 0) -> Dictionary:
	var report := {"executed":[],"remaining":0,"backpressure":0,"elapsed_usec":0,"error":""}
	if phase.is_empty() or not Values.integer(tick) or not Values.integer(budget) or not Values.integer(urgent_reserve):
		report.error = "InvalidArgument"
		return report
	if _running or tick < _last_tick.get(phase,0):
		report.error = "InvalidState"
		return report
	var started := Time.get_ticks_usec()
	var previous_pressure := backpressure
	_running = true
	_last_tick[phase] = tick
	var available := mini(budget, _phase_limit)
	var normal := available - mini(available, urgent_reserve)
	var eligible := _queue.filter(func(j): return j.phase == phase and j.due_tick <= tick)
	eligible.sort_custom(_before)
	for job: Dictionary in eligible:
		if available == 0:
			break
		if not _queue.has(job) or (not job.urgent and normal == 0):
			continue
		_queue.erase(job)
		_depth = job.depth
		job.run.call()
		report.executed.append(job.job_id)
		available -= 1
		if not job.urgent:
			normal -= 1
	_depth = -1
	_running = false
	report.remaining = _queue.filter(func(j): return j.phase == phase and j.due_tick <= tick).size()
	report.backpressure = backpressure - previous_pressure
	report.elapsed_usec = Time.get_ticks_usec() - started
	return report

func subscribe(scope: String, event_type: String, phase: String, handler: Callable) -> Dictionary:
	if not _scopes.has(scope):
		return R.fail("NotFound","scope_id")
	if event_type.is_empty() or phase.is_empty() or not handler.is_valid():
		return R.fail("InvalidArgument","subscription")
	_scopes[scope].listeners.append({"type":event_type,"phase":phase,"handler":handler})
	return R.ok()

func publish_committed(events: Array, revision: Variant) -> Dictionary:
	if not Values.integer(revision):
		return R.fail("InvalidArgument","revision")
	# Roll back newly queued notifications if any entry in the batch is invalid.
	var start := _queue.size()
	for event in events:
		var checked := Schema.validate_shape("EventEnvelope",event)
		if not checked.ok:
			_queue.resize(start)
			return checked
		var row: Dictionary = checked.value
		if row.revision != revision or not _scopes.has(row.scope_id):
			_queue.resize(start)
			return R.fail("StaleVersion","event")
		var listeners: Array = _scopes[row.scope_id].listeners
		for index in listeners.size():
			var sub: Dictionary = listeners[index]
			if sub.type != row.type:
				continue
			var queued := schedule({"job_id":"event/%d/%s" % [index,row.event_id],
				"scope_id":row.scope_id,"phase":sub.phase,"priority":0,
				"due_tick":0 if row.tick == null else row.tick,"run":sub.handler.bind(row)})
			if not queued.ok:
				_queue.resize(start)
				return queued
	return R.ok()

func submit_worker(snapshot: Dictionary, token: Dictionary, job: Dictionary) -> Dictionary:
	var scope: Variant = token.get("scope_id")
	if not _scopes.has(scope) or not is_same(_scopes[scope].token, token):
		return R.fail("StaleVersion","generation")
	return _workers.submit(snapshot,token,job)

func collect_ready(scope: String, revision: Variant, current_stamp: Dictionary = {}) -> Array:
	if not _scopes.has(scope) or not Values.integer(revision):
		return []
	return _workers.collect(_scopes[scope].token,revision,current_stamp)

func stale_worker_count() -> int:
	return _workers.stale_results

func cancel_scope(scope: String) -> Dictionary:
	if not _scopes.has(scope):
		return {"discarded":0,"removed_jobs":0}
	for stream: Stream in _scopes[scope].streams.values():
		stream.retire()
	_scopes.erase(scope)
	if _scopes.is_empty():
		_last_tick.clear()
	var count := _queue.size()
	_queue = _queue.filter(func(job): return job.scope_id != scope)
	return {"discarded":_workers.cancel(scope),"removed_jobs":count - _queue.size()}
