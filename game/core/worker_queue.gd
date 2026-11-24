extends RefCounted

const R = preload("res://contracts/result.gd")
const Values = preload("res://contracts/values.gd")
const Canon = preload("res://contracts/canonical.gd")

# Only a task's worker writes its result. The owner reads it after the pool barrier.
class Task:
	var token: Dictionary
	var snapshot: Dictionary
	var key: String
	var run: Callable
	var output: Variant
	var handle := -1
	var done := false

	func compute() -> void:
		output = run.call(snapshot)

var _tasks: Array[Task] = []
var _parallelism: int
var _capacity: int
var stale_results := 0

func _init(parallelism: int, capacity: int) -> void:
	_parallelism = parallelism
	_capacity = capacity

static func _freeze(value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for nested in value.values():
			_freeze(nested)
		value.make_read_only()
	elif typeof(value) == TYPE_ARRAY:
		for nested in value:
			_freeze(nested)
		value.make_read_only()

func submit(snapshot: Dictionary, token: Dictionary, job: Dictionary) -> Dictionary:
	if snapshot.get("scope_id") != token.scope_id or not Values.integer(snapshot.get("revision")):
		return R.fail("InvalidArgument", "snapshot")
	for field in ["tick","nav_revision","control_revision","generation"]:
		if snapshot.get(field) != null and not Values.integer(snapshot[field]):
			return R.fail("InvalidArgument",field)
	if typeof(job.get("stable_key")) != TYPE_STRING or job.stable_key.is_empty() or typeof(job.get("run")) != TYPE_CALLABLE or not job.run.is_valid():
		return R.fail("InvalidArgument", "job")
	if _tasks.size() >= _capacity:
		return R.fail("Unavailable", "worker_queue")
	for prior in _tasks:
		if prior.token == token and prior.key == job.stable_key:
			return R.fail("Conflict", "stable_key")
	var wire := Canon.encode(snapshot)
	if not wire.ok:
		return wire
	var task := Task.new()
	task.token = token.duplicate()
	task.snapshot = Canon.decode(wire.value).value
	_freeze(task.snapshot)
	task.key = job.stable_key
	task.run = job.run
	_tasks.append(task)
	_dispatch()
	return R.ok(task.key)

func _join(task: Task) -> void:
	if task.handle != -1 and not task.done:
		WorkerThreadPool.wait_for_task_completion(task.handle)
		task.done = true

func _dispatch() -> void:
	var running := 0
	for task in _tasks:
		if not task.done and task.handle != -1:
			if WorkerThreadPool.is_task_completed(task.handle):
				_join(task)
			else:
				running += 1
	for task in _tasks:
		if task.done or task.handle != -1:
			continue
		if _parallelism == 0:
			task.compute()
			task.done = true
		elif running < _parallelism:
			task.handle = WorkerThreadPool.add_task(task.compute)
			running += 1
		else:
			break

func cancel(scope: String) -> int:
	var discarded := 0
	for task in _tasks.duplicate():
		if task.token.scope_id == scope:
			_join(task)
			_tasks.erase(task)
			discarded += 1
	_dispatch()
	return discarded

func collect(token: Dictionary, revision: int, stamp: Dictionary) -> Array:
	var ready := []
	# Commit the whole submitted group. Completion order must never select the write set.
	for task in _tasks.duplicate():
		if task.token.scope_id != token.scope_id:
			continue
		while task.handle == -1 and not task.done:
			_dispatch()
			if task.handle == -1 and not task.done:
				for running in _tasks:
					if running.handle != -1 and not running.done:
						_join(running)
						break
		_join(task)
		_tasks.erase(task)
		var valid: bool = task.token == token and task.snapshot.revision == revision
		for key in ["tick","nav_revision","control_revision","generation"]:
			if task.snapshot.get(key) != null and not stamp.has(key):
				valid = false
		for key in stamp:
			valid = valid and task.snapshot.has(key) and typeof(task.snapshot[key]) == typeof(stamp[key]) and task.snapshot[key] == stamp[key]
		if valid:
			ready.append({"stable_key":task.key, "value":task.output, "revision":revision})
		else:
			stale_results += 1
	ready.sort_custom(func(a,b): return a.stable_key < b.stable_key)
	_dispatch()
	return ready
