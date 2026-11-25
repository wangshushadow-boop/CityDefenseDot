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

var _checkpoint := {}

func begin_tick() -> Dictionary:
	if _reading or _closed or not _checkpoint.is_empty():
		return R.fail("InvalidState","tick_transaction")
	_checkpoint = {"states":_states.duplicate(), "accepted":_accepted.duplicate(),
		"pending":_pending.duplicate(), "tokens":_tokens.duplicate()}
	return R.ok()

func commit_tick() -> void:
	if not _reading:
		_checkpoint = {}

func rollback_tick() -> void:
	if _reading or _closed or _checkpoint.is_empty():
		return
	_states = _checkpoint.states
	_accepted = _checkpoint.accepted
	_pending = _checkpoint.pending
	_tokens = _checkpoint.tokens
	_checkpoint = {}

func _init(scope: String, issuer: String, ai_formation_view: Callable, formation_view: Callable, team_key: Variant, collect_job: Callable) -> void:
	_scope = scope
	_issuer = issuer
	_intel = ai_formation_view
	_formation = formation_view
	_team = team_key
	_collect = collect_job

func view(id: int) -> Dictionary:
	if not _states.has(id):
		return R.fail("NotFound","formation_brain")
	if _reading or not _formation.is_valid() or not _intel.is_valid():
		return R.fail("InvalidState","formation_brain")
	_reading = true
	var result := _current_view(id,_states[id])
	_reading = false
	return R.fail("InvalidState","formation_brain") if _closed else result

static func _order_key(order: Variant) -> Array:
	return [] if order == null else [order.issuer_id,order.order_id]

static func _authority(f: Dictionary, order: Variant) -> Dictionary:
	return {"order":_order_key(order),"control":f.control_revision,"members":f.members_revision,
		"routing":f.routing,"distance":f.distance_mm,"terrain":f.terrain_feedback}

func _ally_center(active: Variant, stamp: Dictionary) -> Variant:
	if active == null or active.order_type != "follow":
		return null
	var ally: Dictionary = _intel.call(active.target_formation_id)
	if ally.ok and not ally.value.own_units.is_empty() and is_same(ally.value.own_units[0].team_key,_team) and ally.value.stamp.tick == stamp.tick and ally.value.stamp.instance == stamp.instance:
		return Behavior.aggregate(ally.value.own_units).center
	return null

## FORM may activate a different order between granted L2 jobs. Project that
## winner without issuing a new command or advancing brain memory.
func _current_view(id: int, published: Dictionary) -> Dictionary:
	var read: Dictionary = _formation.call(id)
	if not read.ok or _closed:
		return read
	var form: Dictionary = read.value
	if form.id != id or not is_same(form.team_key,_team):
		return R.fail("Unauthorized","formation_team")
	var state: Dictionary = published.state.duplicate(true)
	if published.authority == _authority(form,form.active):
		if form.fire_mode == "hold_fire":
			state.member_constraint.fire_allowed = false
			if state.behavior == "Fire":
				state.behavior = "Hold"
				state.member_constraint.engage_allowed = false
				if state.feedback != null:
					state.feedback.merge({"status":"blocked","reason":"fire_restricted","progress":0.0},true)
			if not state.member_constraint.engage_allowed:
				state.member_constraint.focus_target = null
		return R.ok(state)
	var intel: Dictionary = _intel.call(id)
	if not intel.ok:
		return intel
	if _closed or intel.value.stamp.scope_id != _scope or intel.value.own_units.is_empty() or not is_same(intel.value.own_units[0].team_key,_team) or not _same_roster(form.members,intel.value.own_units):
		return R.fail("StaleVersion","formation_roster")
	var active: Variant = form.active
	var current_ground: Dictionary = published.ground.duplicate()
	current_ground.reachable = form.terrain_feedback.is_empty()
	var effective := Behavior.decide(null,intel.value,form,current_ground,state,_issuer,_ally_center(active,intel.value.stamp))
	# Changes in terrain or membership do not remove a still-active task's restrictions.
	if active != null and active.issuer_id == _issuer and _order_key(active) == published.authority.order and form.control_revision == state.control_revision:
		for key in ["engage_allowed","fire_allowed"]:
			effective.member_constraint[key] = effective.member_constraint[key] and state.member_constraint[key]
		effective.member_constraint.movement_limit = minf(effective.member_constraint.movement_limit,state.member_constraint.movement_limit)
	for key in ["behavior","local_goal","member_constraint","slot_request","recovery","retry_after","count"]:
		state[key] = effective[key]
	state.control_revision = form.control_revision
	state.order_revision = intel.value.stamp.order_revision
	if effective.behavior != published.state.behavior:
		state.started_tick = active.issued_tick if active != null else form.feedback.get("tick",state.tick)
	if state.feedback != null:
		var reason: String = form.feedback.get("reason","")
		if active != null and active.issuer_id != _issuer:
			reason = "player_order"
		elif form.routing:
			reason = "routing"
		elif _issuer not in [form.owner,form.delegate]:
			reason = "not_delegated"
		elif active == null and form.feedback.get("state") == "Completed" and _order_key(form.feedback) == published.authority.order and state.feedback.status == "completed":
			return R.ok(state)
		elif reason.is_empty():
			reason = "order_changed" if active != null else "order_inactive"
		state.feedback.merge({"status":"blocked","reason":reason,"progress":0.0},true)
	return R.ok(state)

func close() -> void:
	_checkpoint = {}
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
		ally_position = _ally_center(active,stamp)
		_reading = false
		if _closed:
			return R.fail("InvalidState","formation_brain")
	return R.ok({"intel":intel.value,"form":form.value,"ally_position":ally_position})

static func _guard(f: Dictionary) -> Array:
	# Includes independent order modes, which can change without a control revision.
	return [f.owner,f.delegate,f.control_revision,f.members_revision,f.active,f.queued,
		f.routing,f.fire_mode,f.layout,f.distance_mm,f.facing_target_id,f.terrain_feedback]

func _orders(d: Dictionary, form: Dictionary, job: Dictionary, sequence: int) -> Dictionary:
	if not d.command:
		return R.ok({"orders":[],"expected":form.active})
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
			return R.ok({"orders":[],"expected":o})
	var params := {}
	if kind == "advance" and form.active != null:
		# FORM's append default would leave an earlier completed recovery hold active.
		params.queue_policy = "replace"
	var order := {"mission_id":_scope, "issuer_id":_issuer, "client_sequence":sequence, "issued_tick":job.stamp.tick+1,
		"order_id":"l2/%d/%d/%d"%[job.subject,job.stamp.tick,sequence], "formation_ids":[job.subject],
		"order_type":kind,"target_position":pos,"target_formation_id":target,"parameters":params}
	return R.ok({"orders":[order],"expected":order})

## terrain is the current MOV/FORM read side: clear_width, spacing, slot_error
## (metres), yaw (radians), reachable, optional current FORM compressed flag.
## next_sequence is reserved by the issuer.
func stage(job: Dictionary, task: Variant, terrain: Dictionary, next_sequence: int) -> Dictionary:
	var read := _inputs(job,true)
	if not read.ok:
		return read
	var id: int = job.subject
	var previous: Dictionary = _states.get(id,{})
	var old: Dictionary = previous.get("state",{})
	if not previous.is_empty():
		var live: Variant = read.value.form.active
		if _order_key(live) != previous.authority.order:
			# Rejected movement cannot start the cavalry recovery timer.
			old = old.duplicate()
			old.merge({"behavior":"","recovery":"","retry_after":0},true)
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
	var orders: Array = commands.value.orders
	var state := {"formation_id":id,"tick":job.stamp.tick, "count":d.count,"behavior":d.behavior,"task_id":d.task_id,
		"control_revision":job.stamp.control_revision, "order_revision":job.stamp.order_revision, "local_goal":d.local_goal,
		"last_order_id":old.get("last_order_id") if orders.is_empty() else orders[0].order_id,
		"started_tick":old.started_tick if old.get("behavior") == d.behavior and old.get("task_id") == d.task_id else job.stamp.tick,
		"retry_after":d.retry_after, "recovery":d.recovery, "member_constraint":d.member_constraint, "feedback":d.feedback, "slot_request":d.slot_request}
	var ticket := RefCounted.new()
	_tokens[ticket] = id
	var published := {"state":state,"authority":_authority(read.value.form,commands.value.expected),"ground":terrain.duplicate()}
	_pending[id] = {"ticket":ticket, "job":job,"guard":_guard(read.value.form),"published":published,"orders":orders}
	var result := state.duplicate(true)
	result.orders = orders.duplicate(true)
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
	_states[id] = _pending[id].published
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
