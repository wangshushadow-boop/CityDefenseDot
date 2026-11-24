extends RefCounted
## Mission-local field victory, withdrawal and reinforcement eligibility.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const Sources = preload("res://contracts/field_sources.gd")

var _scope: String
var _index: RefCounted
var _totals := {}
var _exits := {}
var _authorize: Callable
var _condition: Callable
var _position: Callable
var _last_tick := 0
var _last_rows: Variant
var _last_slots: Variant
var _counts := {}
var _entered := {}
var _runners := []
var _status := {}
var _pending: Variant = null
var _candidate := {}
var _busy := false
var _commander: Variant = null
var _commander_team: Variant = null
var _mode_request := ""

static func _point(p: Variant) -> bool:
	return typeof(p)==TYPE_ARRAY and p.size()==3 and V.integer(p[0],-2147483648,2147483647) and V.integer(p[1],-2147483648,2147483647) and V.integer(p[2],-2147483648,2147483647)

static func build(scope: String, encounter: Dictionary, exit_zones: Array, authorize: Callable, condition: Callable, position: Callable) -> Dictionary:
	if scope.is_empty() or not authorize.is_valid() or not condition.is_valid() or not position.is_valid():
		return R.fail("InvalidArgument","field_rules")
	var source := Sources.build(encounter)
	if not source.ok:
		return source
	var rules = new()
	rules._scope = scope
	rules._index = source.value
	rules._authorize = authorize
	rules._condition = condition
	rules._position = position
	for side in encounter.sides:
		var total := 0
		for a in side.roster_allocations:
			total += a.source_slot_range[1]-a.source_slot_range[0]
		rules._totals[side.team_key] = total
	for zone in exit_zones:
		if typeof(zone)!=TYPE_DICTIONARY or not rules._totals.has(zone.get("team_key")) or rules._exits.has(zone.team_key) or not _point(zone.get("min_mm")) or not _point(zone.get("max_mm")):
			return R.fail("InvalidArgument","exit_zones")
		for axis in 3:
			if zone.min_mm[axis]>zone.max_mm[axis]:
				return R.fail("InvalidArgument","exit_zones")
		rules._exits[zone.team_key] = zone.duplicate(true)
	if rules._exits.size()!=rules._totals.size():
		return R.fail("InvalidArgument","exit_zones")
	rules._status = {"tick":0,"teams":[],"outcome":null,"commander_downed":false,"control_mode":"direct","commander_options":[]}
	return R.ok(rules)

func view() -> Dictionary:
	return _status.duplicate(true)

func watch_commander(handle: Dictionary, team: Variant) -> Dictionary:
	if _busy or not _candidate.is_empty() or _status.outcome!=null or not V.integer(handle.get("index"),0,V.MAX_U32) or not V.integer(handle.get("generation"),1,V.MAX_U32):
		return R.fail("InvalidState","commander")
	if not _totals.has(team):
		return R.fail("NotFound","team_key")
	_commander = handle.duplicate()
	_commander_team = team
	_last_rows = null
	return R.ok()

func request_downed_mode(team: Variant, mode: String, context: Variant) -> Dictionary:
	if _busy or not _candidate.is_empty() or _status.outcome!=null or not _status.commander_downed:
		return R.fail("InvalidState","commander")
	if not is_same(team,_commander_team) or mode not in ["spectate","delegate","withdraw"]:
		return R.fail("Unauthorized","commander")
	if mode=="withdraw":
		return request_withdrawal(team,context)
	_busy = true
	var permission: Variant = _authorize.call(context,team,mode)
	_busy = false
	if not is_same(permission,true):
		return R.fail("Unauthorized","commander")
	_mode_request = mode
	return R.ok()

func request_withdrawal(team: Variant, context: Variant) -> Dictionary:
	if _busy or not _candidate.is_empty() or _status.outcome!=null:
		return R.fail("InvalidState","outcome")
	if not _totals.has(team):
		return R.fail("NotFound","team_key")
	_busy = true
	var auth: Variant = _authorize.call(context,team,"withdraw")
	_busy = false
	if not is_same(auth,true):
		return R.fail("Unauthorized","withdraw")
	if _pending!=null and not is_same(_pending,team):
		return R.fail("Conflict","withdraw")
	_pending = team
	return R.ok()

func _has_changes(reports: Array) -> bool:
	for report in reports:
		var payload: Variant = report.get("value")
		if typeof(payload)==TYPE_DICTIONARY:
			for ev in payload.get("events",[]):
				if ev.get("type") in ["routed","regrouped","downed"]:
					return true
	return false

func _roster(rows: Array, counts: Dictionary, runners: Array) -> Dictionary:
	var down := _status.get("commander_downed",false) as bool
	var seen_commander := false
	for row in rows:
		if row.source_slot==null:
			continue
		var team: Variant = row.components.team_key
		var health: Variant = _condition.call(row.handle)
		if typeof(health)!=TYPE_DICTIONARY or typeof(health.get("ok"))!=TYPE_BOOL:
			return R.fail("InvalidArgument","combat.read_view")
		if not health.ok:
			return health
		if typeof(health.get("value"))!=TYPE_DICTIONARY:
			return R.fail("InvalidArgument","combat.read_view")
		var info: Dictionary = health.value
		if not V.integer(info.get("hp")) or typeof(info.get("routing"))!=TYPE_BOOL:
			return R.fail("InvalidArgument","combat.read_view")
		var incapacitated: bool = info.hp==0
		if _commander!=null and row.handle==_commander:
			down = incapacitated
			seen_commander = true
		if not incapacitated:
			if info.routing:
				runners.append(row)
			else:
				counts[team] = counts.get(team,0)+1
	# A watched, already deployed commander's generation never transfers on reuse.
	return R.ok(down or (_commander!=null and not seen_commander))

func _exited(row: Dictionary) -> Dictionary:
	var reading: Variant = _position.call(row.handle)
	if typeof(reading)!=TYPE_DICTIONARY or typeof(reading.get("ok"))!=TYPE_BOOL:
		return R.fail("InvalidArgument","movement.position_mm")
	if not reading.ok:
		return reading
	var point: Variant = reading.value
	if not _point(point):
		return R.fail("InvalidArgument","movement.position_mm")
	var zone: Dictionary = _exits[row.components.team_key]
	for axis in 3:
		if point[axis]<zone.min_mm[axis] or point[axis]>zone.max_mm[axis]:
			return R.ok(false)
	return R.ok(true)

func _outcome(kind: String, winners: Array, reason: String) -> Dictionary:
	return {"outcome":kind,"winner_team_keys":winners,"reason":reason,
		"objective_results":[{"id":"field","status":"completed","reason":reason}]}

func _evaluate(context: Dictionary, tick: int) -> Dictionary:
	var rows: Array = context.entities
	var slots: Array = context.spawned_slots
	var counts := _counts
	var runners := _runners
	var commander_down: bool = _status.commander_downed
	if not is_same(rows,_last_rows) or _has_changes(context.get("phase_reports",[])):
		counts = {}
		runners = []
		var found := _roster(rows,counts,runners)
		if not found.ok:
			return found
		commander_down = found.value
	var entered := _entered
	if not is_same(slots,_last_slots):
		entered = {}
		for slot in slots:
			var owner: Dictionary = _index.team_for_slot(slot)
			if not owner.ok:
				return owner
			entered[owner.value] = entered.get(owner.value,0)+1
	var retire := []
	var slot_events := []
	var routed := {}
	for runner in runners:
		var away := _exited(runner)
		if not away.ok:
			return away
		var team: Variant = runner.components.team_key
		if away.value:
			retire.append(runner.handle)
			slot_events.append({"source_slot_id":runner.source_slot,"end_status":"withdrawn"})
		else:
			routed[team] = routed.get(team,0)+1
	var contenders := []
	var summaries := []
	for team in _totals:
		var reserve: int = _totals[team]-entered.get(team,0)
		var ready: int = counts.get(team,0)
		summaries.append({"team_key":team,"ready":ready,"routed":routed.get(team,0),"reserve":reserve})
		if ready+reserve>0 and (_pending==null or not is_same(team,_pending)):
			contenders.append(team)
	var outcome: Variant = null
	if _pending!=null:
		outcome = _outcome("withdrawn",contenders if contenders.size()==1 else [],"ordered_withdrawal")
		outcome["withdrawn_team_key"] = _pending
	elif contenders.size()==1:
		outcome = _outcome("victory",contenders,"no_opposing_force")
	elif contenders.is_empty():
		outcome = _outcome("draw",[],"no_fighting_force")
	var options := ["spectate","delegate","withdraw"] if commander_down and outcome==null else []
	var control: String = "direct" if not commander_down else (_mode_request if not _mode_request.is_empty() else _status.control_mode)
	if commander_down and control=="direct":
		control = "spectate"
	var status := {"tick":tick,"teams":summaries,"outcome":outcome,"commander_downed":commander_down,
		"control_mode":control,"commander_options":options}
	_candidate = {"rows":rows,"slots":slots,"counts":counts,"runners":runners,"entered":entered,"status":status}
	return R.ok({"outcome":outcome.duplicate(true) if outcome!=null else null,
		"retire_handles":retire.duplicate(true),"slot_events":slot_events,"commander_downed":commander_down,"teams":summaries.duplicate(true)})

func stage(context: Dictionary, batch: Dictionary) -> Dictionary:
	if _busy or not _candidate.is_empty() or _status.outcome!=null:
		return R.fail("InvalidState","field_rules")
	if context.get("mission_id")!=_scope or batch.get("mission_id")!=_scope:
		return R.fail("NotFound","mission_id")
	if batch.get("source_tick")!=_last_tick+1 or context.get("tick")!=_last_tick:
		return R.fail("StaleVersion","tick")
	_busy = true
	var result := _evaluate(context,batch.source_tick)
	_busy = false
	return result

func commit() -> void:
	if _candidate.is_empty():
		return
	_last_rows = _candidate.rows
	_last_slots = _candidate.slots
	_counts = _candidate.counts
	_runners = _candidate.runners
	_entered = _candidate.entered
	_status = _candidate.status
	_last_tick = _status.tick
	_pending = null
	_mode_request = ""
	_candidate = {}

func rollback() -> void:
	_candidate = {}

func system() -> Dictionary:
	return {"id":"field.rules","run":stage,"commit":commit,"rollback":rollback,"can_retire":true}
