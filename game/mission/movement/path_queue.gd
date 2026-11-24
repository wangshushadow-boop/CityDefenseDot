extends RefCounted
## A Mission-local queue of shared geometric corridor queries. Coordinates at
## the adapter boundary are integer millimetres. One ticket may serve a formation.
const R = preload("res://contracts/result.gd")

var _engine: RefCounted
var _scope: String
var _capacity: int
var _per_tick: int
var _revision := -1
var _serial := 0
## Native queries have already run even when the containing Mission step rolls back.
## Retain their budget and answers for the same tick and map revision only.
class Meter:
	var tick := -1
	var spent := 0
	var revision := -1
	var answers := {}

var _meter := Meter.new()
var _shared := false
var _by_route := {}
var _pending := {}
var _completed := {}

func _init(engine: RefCounted, mission_id: String, capacity: int = 128, per_tick: int = 8) -> void:
	_engine = engine
	_scope = mission_id
	_capacity = capacity
	_per_tick = per_tick

func fork():
	var copy = get_script().new(_engine,_scope,_capacity,_per_tick)
	copy._revision = _revision
	copy._serial = _serial
	copy._meter = _meter
	copy._by_route = _by_route
	copy._pending = _pending
	copy._completed = _completed
	_shared = true
	copy._shared = true
	return copy

func _detach() -> void:
	if _shared:
		_by_route = _by_route.duplicate()
		_pending = _pending.duplicate()
		_completed = _completed.duplicate()
		_shared = false

func _sync() -> Dictionary:
	if _engine == null or _scope.is_empty() or _per_tick <= 0 or _capacity < _per_tick:
		return R.fail("InvalidArgument", "path_queue")
	var result: Dictionary = _engine.sync_navigation(_scope)
	if not result.ok:
		return result
	if result.value.status != "applied":
		return R.fail("Unavailable", "navigation_sync")
	var confirmed: int = result.value.applied_revision
	if confirmed != _revision:
		# P1 supplies a map revision, not the links touched by a path.
		_pending = {}
		_completed = {}
		_by_route = {}
		_shared = false
		_revision = confirmed
	if _meter.revision != confirmed:
		_meter.revision = confirmed
		_meter.answers.clear()
	return R.ok(_revision)

static func _point_ok(point: Array) -> bool:
	if point.size() != 3:
		return false
	for coordinate in point:
		if typeof(coordinate) != TYPE_INT or coordinate < -2147483648 or coordinate > 2147483647:
			return false
	return true

func request_path(origin: Array, goal: Array, profile: String, priority: int = 0) -> Dictionary:
	if not _point_ok(origin) or not _point_ok(goal) or profile.is_empty():
		return R.fail("InvalidArgument", "path")
	var sync := _sync()
	if not sync.ok:
		return sync
	# Copy inputs once. Caller mutation must never change a live dictionary key.
	var key := [origin.duplicate(), goal.duplicate(), profile]
	if _by_route.has(key):
		var known: Dictionary = _by_route[key]
		if priority > known.priority and _pending.has(known.ticket.request_id):
			_detach()
			known = known.duplicate()
			known.priority = priority
			_by_route[key] = known
			_pending[known.ticket.request_id] = known
		return R.ok(known.ticket)
	if _pending.size() >= _capacity:
		return R.fail("Unavailable", "path_queue.capacity")
	_detach()
	_serial += 1
	var ticket := {"scope_id":_scope, "nav_revision":_revision, "request_id":_serial}
	ticket.make_read_only()
	var job := {"key":key, "ticket":ticket, "priority":priority}
	_pending[_serial] = job
	_by_route[key] = job
	return R.ok(ticket)

static func _comes_first(left: Dictionary, right: Dictionary) -> bool:
	if left.priority != right.priority:
		return left.priority > right.priority
	return left.ticket.request_id < right.ticket.request_id

func attempts_at(tick: int) -> int:
	return _meter.spent if _meter.tick == tick else 0

func has_answer(tick: int, revision: int, origin: Array, goal: Array, profile: String) -> bool:
	return _meter.tick==tick and _meter.revision==revision and _meter.answers.has([origin,goal,profile])

func process_budget(tick: int, remaining: int = 2147483647) -> Dictionary:
	if tick < 0 or tick < _meter.tick:
		return R.fail("StaleVersion", "tick")
	var sync := _sync()
	if not sync.ok:
		return sync
	if tick != _meter.tick:
		_meter.tick = tick
		_meter.spent = 0
		_meter.answers.clear()
	var limit := mini(_per_tick - _meter.spent, maxi(remaining,0))
	if _pending.is_empty() or (limit == 0 and _meter.answers.is_empty()):
		return R.ok({"queried":0, "pending":_pending.size(), "nav_revision":_revision})
	var jobs := _pending.values()
	jobs.sort_custom(_comes_first)
	var batch := []
	var queried := []
	var ready := []
	for job in jobs:
		var route: Array = job.key
		if _meter.answers.has(route):
			ready.append(job)
		elif batch.size() < limit:
			batch.append({"from":route[0], "to":route[1]})
			queried.append(job)
			ready.append(job)
	if not batch.is_empty():
		_meter.spent += batch.size()
		var solved: Dictionary = _engine.query_path_batch(batch, _revision, _scope)
		if not solved.ok:
			return solved
		if typeof(solved.value) != TYPE_ARRAY or solved.value.size() != batch.size():
			return R.fail("InvalidState", "path_query")
		for row in solved.value:
			if typeof(row) != TYPE_DICTIONARY or row.get("nav_revision") != _revision or typeof(row.get("reachable")) != TYPE_BOOL or typeof(row.get("points")) != TYPE_ARRAY:
				return R.fail("InvalidState", "path_query")
		for i in queried.size():
			_meter.answers[queried[i].key] = solved.value[i].duplicate(true)
	if not ready.is_empty(): _detach()
	for selected in ready:
		var job: Dictionary = selected.duplicate()
		var id: int = job.ticket.request_id
		if _completed.size() == _capacity:
			# Insertion order is completion order; eviction is deterministic.
			var oldest: int = _completed.keys()[0]
			_by_route.erase(_completed[oldest].key)
			_completed.erase(oldest)
		job["result"] = _meter.answers[job.key]
		_by_route[job.key] = job
		_pending.erase(id)
		_completed[id] = job
	return R.ok({"queried":batch.size(), "pending":_pending.size(), "nav_revision":_revision})

func poll_path(ticket: Dictionary) -> Dictionary:
	var sync := _sync()
	if not sync.ok:
		return sync
	if ticket.get("scope_id") != _scope or ticket.get("nav_revision") != _revision:
		return R.fail("StaleVersion", "path_ticket")
	var id: Variant = ticket.get("request_id")
	var job: Dictionary = _completed.get(id, _pending.get(id, {}))
	if job.is_empty() or not is_same(job.ticket, ticket):
		return R.fail("NotFound", "path_ticket")
	if not job.has("result"):
		return R.fail("Unavailable", "path_pending")
	return R.ok(job.result.duplicate(true))
