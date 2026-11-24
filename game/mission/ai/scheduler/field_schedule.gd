extends RefCounted
## A scope-local calendar indexes the next deadline. A stable roster costs work
## proportional to the jobs due plus the outstanding emergency signals.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const DEFAULT := {"tactical":4,"formation":16,"individual":256,"urgent":32}
var _roster_id := -1
var _clocks := {}
var _calendar := {}
var _emergencies := {}
var _last_tick := -1

static func _before(a: Dictionary,b: Dictionary) -> bool:
	if a.due != b.due:
		return a.due < b.due
	if typeof(a.id) != typeof(b.id):
		return typeof(a.id) < typeof(b.id)
	return a.id < b.id

func _queue(layer: String, clock: Dictionary) -> void:
	var days: Dictionary = _calendar[layer]
	if not days.has(clock.due):
		days[clock.due] = []
	days[clock.due].append(clock)

func _sync(layers: Array, tick: int, board: RefCounted) -> void:
	if _roster_id == board.get_instance_id():
		return
	_roster_id = board.get_instance_id()
	for layer in layers:
		var name: String = layer[0]
		var members: Dictionary = layer[1]
		var period: int = layer[2]
		var previous: Dictionary = _clocks.get(name,{})
		var live := {}
		_calendar[name] = {}
		for id in members:
			var generation: int = members[id].handle.generation if name=="individual" else 0
			var clock: Dictionary = previous.get(id,{})
			if clock.is_empty() or clock.gen != generation:
				var phase: int = id if typeof(id)==TYPE_INT else String(id).hash()
				if name == "individual":
					phase += members[id].formation_id * maxi(1,period/3)
				clock = {"id":id,"gen":generation,"due":tick+posmod(phase,period)}
			live[id] = clock
			_queue(name,clock)
		_clocks[name] = live
	for id in _emergencies.keys():
		if not board.actors.has(id) or board.actors[id].handle.generation != _emergencies[id].gen:
			_emergencies.erase(id)

func due(tick: int, hz: int, board: RefCounted, budgets: Dictionary) -> Dictionary:
	if tick == _last_tick:
		return R.fail("Conflict","already_scheduled")
	for name in budgets:
		if not DEFAULT.has(name) or not V.integer(budgets[name],0,4096):
			return R.fail("InvalidArgument","decision_budget")
	var layers := [
		["tactical",board.teams,hz],
		["formation",board.formations,maxi(1,roundi(hz/3.0))],
		["individual",board.actors,maxi(1,roundi(hz/5.0))]
	]
	_sync(layers,tick,board)
	for id in board.urgent:
		if not _emergencies.has(id):
			_emergencies[id] = {"id":id,"gen":board.actors[id].handle.generation,"due":tick}
	var jobs := []
	var backlog := {"tactical":0,"formation":0,"individual":0,"urgent":0}
	var emergency := _emergencies.values()
	emergency.sort_custom(_before)
	var served := {}
	for index in mini(emergency.size(),budgets.get("urgent",DEFAULT.urgent)):
		var id: int = emergency[index].id
		jobs.append({"layer":"individual","subject":board.actors[id].handle,"urgent":true})
		served[id] = true
		_emergencies.erase(id)
	backlog.urgent = _emergencies.size()
	for layer in layers:
		var name: String = layer[0]
		var rows: Dictionary = layer[1]
		var period: int = layer[2]
		var days: Dictionary = _calendar[name]
		var ready := []
		for day in days.keys():
			if day <= tick:
				ready.append_array(days[day])
				days.erase(day)
		ready.sort_custom(_before)
		var used := 0
		for clock in ready:
			var id: Variant = clock.id
			var coalesced: bool = name=="individual" and served.has(id)
			if not coalesced:
				if used >= budgets.get(name,DEFAULT[name]) or (name=="individual" and _emergencies.has(id)):
					backlog[name] += 1
					_queue(name,clock)
					continue
				used += 1
				jobs.append({"layer":name,"subject":rows[id].handle if name=="individual" else id,"urgent":false})
			var next_period := period
			if name=="formation" and board.threatened(id,tick):
				next_period = maxi(1,roundi(hz/5.0))
			if name=="individual" and board.high_priority(id,tick):
				next_period = maxi(1,roundi(hz/10.0))
			clock.due = tick+next_period
			_queue(name,clock)
	_last_tick = tick
	return R.ok({"jobs":jobs,"backlog":backlog})
