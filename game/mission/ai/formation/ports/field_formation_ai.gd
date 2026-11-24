extends RefCounted
## One team's L2 controller, owned by one Mission. Only the composition root
## publishes orders/feedback. A speculative decision has no FORM/MOV/COM effects.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const Behavior = preload("res://mission/ai/formation/behaviors/field_behavior.gd")

var _scope: String
var _issuer: String
var _team: Variant
var _intel: Callable
var _formation: Callable
var _collect: Callable
var _accepted := {}
var _states := {}
var _pending := {}
var _tokens := {}
var _closed := false
var _reading := false

func _init(scope: String, issuer: String, ai_formation_view: Callable, formation_view: Callable, team_key: Variant, collect_job: Callable) -> void:
	_scope = scope
	_issuer = issuer
	_intel = ai_formation_view
	_formation = formation_view
	_team = team_key
	_collect = collect_job

func view(id: int) -> Dictionary:
	return R.ok(_states[id].duplicate(true)) if _states.has(id) else R.fail("NotFound","formation_brain")

func close() -> void:
	_closed = true
	_states.clear()
	_pending.clear()
	_tokens.clear()
	_accepted.clear()

static func _same_roster(handles: Array, units: Array) -> bool:
	if handles.size() != units.size():
		return false
	for i in handles.size():
		if handles[i] == units[i].handle:
			continue
		# BAI publish order is independent of FORM's sorted display order.
		var generations := {}
		for handle in handles:
			generations[handle.index] = handle.generation
		for unit in units:
			if generations.get(unit.handle.index) != unit.handle.generation:
				return false
		break
	return true

func _inputs(job: Dictionary, for_decision := false) -> Dictionary:
	if _closed or _reading or _issuer.is_empty() or not _intel.is_valid() or not _formation.is_valid():
		return R.fail("InvalidState","formation_brain")
	var stamp: Variant = job.get("stamp")
	var id: Variant = job.get("subject")
	if job.get("layer") != "formation" or not V.integer(id,0,V.MAX_U32) or not V.integer(job.get("id")) or not stamp is Dictionary:
		return R.fail("Unauthorized","formation_job")
	if not is_same(stamp.get("scope_id"),_scope) or not V.integer(stamp.get("tick")) or not V.integer(stamp.get("control_revision")):
		return R.fail("Unauthorized","formation_stamp")
	_reading = true
	var intel: Dictionary = _intel.call(id)
	var form: Dictionary = _formation.call(id)
	_reading = false
	if _closed:
		return R.fail("InvalidState","formation_brain")
	if not intel.ok:
		return intel
	if not form.ok:
		return form
	if intel.value.stamp != stamp or form.value.control_revision != stamp.control_revision:
		return R.fail("StaleVersion","formation_stamp")
	if form.value.id != id or not is_same(form.value.team_key, _team) or intel.value.own_units.is_empty() or not is_same(intel.value.own_units[0].team_key, _team):
		return R.fail("Unauthorized","formation_team")
	if for_decision and not _same_roster(form.value.members,intel.value.own_units):
		return R.fail("StaleVersion","formation_roster")
	var ally_position: Variant = null
	var active: Variant = form.value.active
	if for_decision and active != null and active.order_type == "follow":
		_reading = true
		var ally: Dictionary = _intel.call(active.target_formation_id)
		_reading = false
		if _closed:
			return R.fail("InvalidState","formation_brain")
		if ally.ok and not ally.value.own_units.is_empty() and is_same(ally.value.own_units[0].team_key,_team) and ally.value.stamp.tick == stamp.tick and ally.value.stamp.instance == stamp.instance:
			ally_position = Behavior.aggregate(ally.value.own_units).center
	return R.ok({"intel":intel.value,"form":form.value,"ally_position":ally_position})

static func _guard(f: Dictionary) -> Array:
	# Includes independent order modes, which can change without a control revision.
	return [f.owner,f.delegate,f.control_revision,f.members_revision,f.active,f.queued,
		f.routing,f.fire_mode,f.layout,f.distance_mm,f.facing_target_id,f.terrain_feedback]

func _orders(d: Dictionary, form: Dictionary, job: Dictionary, sequence: int) -> Dictionary:
	if not d.command:
		return R.ok([])
	var kind: String = {"Move":"move","Follow":"follow","Charge":"charge","Advance":"advance","Retreat":"retreat"}.get(d.behavior,"hold")
	if d.regroup_move or (kind == "advance" and d.positioned):
		kind = "move"
	var target: Variant = d.contact_formation if kind == "charge" else null
	var pos: Variant = null
	if kind == "move":
		pos = []
		for coord in [d.local_goal.x,d.local_goal.y,d.local_goal.z]:
			var mm := V.millimeters(coord)
			if not mm.ok:
				return mm
			pos.append(mm.value)
	# Keep a standing equivalent order. In particular, do not enqueue a new
	# 'advance' every time a budgeted L2 job fires.
	for o: Variant in [form.active] + form.queued:
		if o != null and o.issuer_id == _issuer and o.order_type == kind and o.target_position == pos and o.target_formation_id == target:
			return R.ok([])
	var params := {}
	if kind == "advance" and form.active != null:
		# FORM's append default would leave an earlier completed recovery hold active.
		params.queue_policy = "replace"
	var order := {"mission_id":_scope, "issuer_id":_issuer, "client_sequence":sequence, "issued_tick":job.stamp.tick+1,
		"order_id":"l2/%d/%d/%d"%[job.subject,job.stamp.tick,sequence], "formation_ids":[job.subject],
		"order_type":kind,"target_position":pos,"target_formation_id":target,"parameters":params}
	return R.ok([order])

## terrain is the current MOV/FORM read side: clear_width, spacing, slot_error
## (metres), yaw (radians), reachable, optional current FORM compressed flag.
## next_sequence is reserved by the issuer.
func stage(job: Dictionary, task: Variant, terrain: Dictionary, next_sequence: int) -> Dictionary:
	var read := _inputs(job,true)
	if not read.ok:
		return read
	var id: int = job.subject
	var old: Dictionary = _states.get(id,{})
	if _pending.has(id) or job.stamp.tick <= old.get("tick",-1):
		return R.fail("Conflict","formation_tick")
	if not V.integer(next_sequence) or not Behavior.valid_ground(terrain):
		return R.fail("InvalidArgument","formation_terrain_or_sequence")
	if task != null:
		if not task is Dictionary or not Behavior.valid_task(task, id):
			return R.fail("InvalidArgument","formation_task")
		if task.control_revision != job.stamp.control_revision:
			return R.fail("StaleVersion","task_control_revision")
		if task.has("order_revision") and not is_same(task.order_revision, job.stamp.order_revision):
			var active: Variant = read.value.form.active
			# A live owner order still needs L3 constraints even if it superseded
			# an earlier task. Only our own last published order may continue it.
			var owner_override: bool = active != null and active.issuer_id != _issuer
			var continuing: bool = active != null and active.issuer_id == _issuer and active.order_id == old.get("last_order_id") and old.get("task_id") == task.id
			if not owner_override and not continuing:
				return R.fail("StaleVersion","task_order_revision")
	var d := Behavior.decide(task, read.value.intel, read.value.form, terrain, old, _issuer, read.value.ally_position)
	var commands := _orders(d, read.value.form, job, next_sequence)
	if not commands.ok:
		return commands
	var state := {"formation_id":id,"tick":job.stamp.tick, "count":d.count,"behavior":d.behavior,"task_id":d.task_id,
		"control_revision":job.stamp.control_revision, "order_revision":job.stamp.order_revision, "local_goal":d.local_goal,
		"last_order_id":old.get("last_order_id") if commands.value.is_empty() else commands.value[0].order_id,
		"started_tick":old.started_tick if old.get("behavior") == d.behavior and old.get("task_id") == d.task_id else job.stamp.tick,
		"retry_after":d.retry_after, "recovery":d.recovery, "member_constraint":d.member_constraint, "feedback":d.feedback, "slot_request":d.slot_request}
	var ticket := RefCounted.new()
	_tokens[ticket] = id
	_pending[id] = {"ticket":ticket, "job":job,"guard":_guard(read.value.form),"state":state,"orders":commands.value}
	var result := state.duplicate(true)
	result.orders = commands.value.duplicate(true)
	result.token = ticket
	return R.ok(result)

## The BAI grant is single-use. A retry after downstream failure may replay the
## same accepted proposal; a changed proposal requires the next granted job.
func collect(token: Variant) -> Dictionary:
	if _closed or _reading or not _collect.is_valid():
		return R.fail("InvalidState","formation_collect")
	if not _tokens.has(token):
		return R.fail("StaleVersion","formation_stage")
	var id: int = _tokens[token]
	var p: Dictionary = _pending.get(id,{})
	if is_same(p.get("ticket"),token):
		var read := _inputs(p.job)
		if not read.ok:
			return read
		if p.guard != _guard(read.value.form):
			return R.fail("StaleVersion","formation_order")
		var before: Dictionary = _accepted.get(id,{})
		if is_same(before.get("job"),p.job):
			return R.ok() if before.orders == p.orders else R.fail("Conflict","formation_retry")
		_reading = true
		var checked: Dictionary = _collect.call(p.job,p.orders)
		_reading = false
		if _closed:
			return R.fail("InvalidState","formation_brain")
		if checked.ok:
			_accepted[id] = {"job":p.job,"orders":p.orders}
		return checked
	return R.fail("StaleVersion","formation_stage")

## The row must be returned by BAI.drain() after its single-use collect(job,orders).
## Preflight all participating domains before publishing the frame. On retry the
## composition root may reuse the drained row for the same unchanged job/inputs.
func validate(token: Variant, drained_row: Dictionary) -> Dictionary:
	var job: Variant = drained_row.get("job")
	if not job is Dictionary or not V.integer(job.get("subject"),0,V.MAX_U32):
		return R.fail("StaleVersion","formation_grant")
	var p: Dictionary = _pending.get(job.subject,{})
	if p.is_empty() or not is_same(token,p.ticket) or not is_same(job,p.job) or drained_row.get("intents") != p.orders:
		return R.fail("StaleVersion","formation_grant")
	var accepted: Dictionary = _accepted.get(job.subject,{})
	if not is_same(accepted.get("job"),job) or accepted.orders != p.orders:
		return R.fail("Unauthorized","formation_grant")
	var read := _inputs(job)
	if not read.ok:
		return read
	if p.guard != _guard(read.value.form):
		return R.fail("StaleVersion","formation_order")
	return R.ok()

func commit(token: Variant, drained_row: Dictionary) -> Dictionary:
	var checked := validate(token,drained_row)
	if not checked.ok:
		return checked
	var id: int = drained_row.job.subject
	_states[id] = _pending[id].state
	_pending.erase(id)
	_tokens.erase(token)
	_accepted.erase(id)
	return R.ok()

func rollback(token: Variant) -> Dictionary:
	if _reading:
		return R.fail("InvalidState","formation_callback")
	if _tokens.has(token):
		_pending.erase(_tokens[token])
		_tokens.erase(token)
		return R.ok()
	return R.fail("StaleVersion","formation_stage")
