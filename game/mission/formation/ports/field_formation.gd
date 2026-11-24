extends RefCounted
## Per-Mission authority. Deployment and execution callbacks run on the Mission thread.
## Authentication resolves an opaque session context; reachability uses integer mm.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const S = preload("res://contracts/schema.gd")
const Layout = preload("res://mission/formation/slot_layout.gd")
const Orders = preload("res://mission/formation/order_rules.gd")

var _mission: String
var _auth: Callable
var _reachable: Callable
var _groups := {}
var _used_ids := {}
var _membership := {}
var _last_sequence := {}
var _history := {}
var _pending: Array = []
var _tick := 0
var _in_callback := false

func _init(mission_id: String, authenticate: Callable, reachable: Callable) -> void:
	_mission = mission_id
	_auth = authenticate
	_reachable = reachable

func _actor(context: Variant) -> String:
	if not _auth.is_valid() or _in_callback:
		return ""
	_in_callback = true
	var reply: Variant = _auth.call(context)
	_in_callback = false
	if typeof(reply) == TYPE_DICTIONARY and reply.get("ok") == true and typeof(reply.get("value")) == TYPE_STRING:
		return reply.value
	return ""

func _controlled(g: Dictionary, actor: String) -> bool:
	return not actor.is_empty() and (actor == g.owner or actor == g.delegate)

func _members(members: Array, allowed_id: int) -> Dictionary:
	var seen := {}
	for h in members:
		if typeof(h) != TYPE_DICTIONARY or h.size() != 2 or not V.integer(h.get("index"), 0, V.MAX_U32) or not V.integer(h.get("generation"), 1, V.MAX_U32):
			return R.fail("InvalidArgument", "member_handle")
		if seen.has(h.index) or (_membership.has(h.index) and _membership[h.index].id != allowed_id):
			return R.fail("Conflict", "membership")
		seen[h.index] = h.duplicate()
	var ids := seen.keys()
	ids.sort()
	var result := []
	for id in ids:
		result.append(seen[id])
	return R.ok(result)

func _set_members(g: Dictionary, members: Array) -> void:
	if g.members == members:
		return
	g.members_revision += 1
	for h in g.members:
		_membership.erase(h.index)
	g.members = members
	for h in members:
		_membership[h.index] = {"id":g.id, "generation":h.generation}

func _create(id: int, team: Variant, owner: String, members: Array) -> void:
	var g := {"id":id, "team_key":team, "owner":owner, "delegate":"", "control_revision":0,
		"members":[], "members_revision":0, "layout":"line", "layout_state":Layout.new(), "active":null, "queued":[],
		"feedback":{}, "terrain_feedback":{}, "routing":false, "fire_mode":"fire_at_will", "mounted":false,
		"facing_microradians":0, "facing_target_id":null, "use_ranged":false, "distance_mm":0}
	_groups[id] = g
	_used_ids[id] = owner
	_set_members(g, members)

func add_formation(id: int, team_key: Variant, owner_actor: String, members: Array) -> Dictionary:
	if _in_callback or _used_ids.has(id):
		return R.fail("Conflict", "formation_id")
	if not V.integer(id, 0, V.MAX_U32) or owner_actor.is_empty() or not (V.integer(team_key, 0, V.MAX_U32) or (typeof(team_key) == TYPE_STRING and not team_key.is_empty())):
		return R.fail("InvalidArgument", "formation")
	var checked := _members(members, -1)
	if checked.ok:
		_create(id, team_key, owner_actor, checked.value)
	return R.ok(id) if checked.ok else checked

## Trusted Mission lifecycle update (casualty, deployment or late wave).
func assign_members(id: int, members: Array) -> Dictionary:
	if _in_callback or not _groups.has(id):
		return R.fail("InvalidState", "formation")
	var checked := _members(members, id)
	if checked.ok:
		_set_members(_groups[id], checked.value)
	return R.ok(id) if checked.ok else checked

## A player can only rearrange deployed, owned units. A transfer names the source
## explicitly so a destination-only order cannot silently remove another roster.
func _assign_deployed(g: Dictionary, parameters: Dictionary) -> Dictionary:
	var source: Dictionary = _groups[parameters.get("source_id", g.id)]
	if source.team_key != g.team_key or source.owner != g.owner:
		return R.fail("Unauthorized", "source_id")
	var checked := _members(parameters.members, source.id)
	if not checked.ok:
		return checked
	var selected := {}
	for handle in checked.value:
		var entry: Variant = _membership.get(handle.index)
		if entry == null or entry.id != source.id or entry.generation != handle.generation:
			return R.fail("NotFound", "member_handle")
		selected[handle.index] = true
	if source.id != g.id:
		var combined: Array = g.members + checked.value
		combined.sort_custom(func(a,b): return a.index < b.index)
		_set_members(source, source.members.filter(func(h): return not selected.has(h.index)))
		_set_members(g, combined)
	return R.ok()

func member_formation(handle: Dictionary) -> Dictionary:
	if not V.integer(handle.get("index"), 0, V.MAX_U32) or not V.integer(handle.get("generation"), 1, V.MAX_U32) or handle.size() != 2:
		return R.fail("InvalidArgument", "member_handle")
	var entry: Variant = _membership.get(handle.index)
	if entry == null or entry.generation != handle.generation:
		return R.fail("NotFound", "member_handle")
	return R.ok(entry.id)

func split(id: int, new_id: int, selected: Array, context: Variant, expected_revision: int) -> Dictionary:
	var actor := _actor(context)
	if not _groups.has(id) or actor != _groups[id].owner:
		return R.fail("Unauthorized", "owner")
	return _split(_groups[id], new_id, selected, expected_revision)

func _split(g: Dictionary, new_id: int, selected: Array, expected_revision: int) -> Dictionary:
	var id: int = g.id
	if expected_revision != g.control_revision or _used_ids.has(new_id):
		return R.fail("Conflict", "formation_revision")
	if not V.integer(new_id, 0, V.MAX_U32) or selected.is_empty() or selected.size() >= g.members.size():
		return R.fail("InvalidArgument", "selection")
	var checked := _members(selected, id)
	if not checked.ok:
		return checked
	var left := []
	var take := {}
	for h in checked.value:
		take[h.index] = h.generation
	for h in g.members:
		if take.get(h.index) != h.generation:
			left.append(h)
	if left.size() + take.size() != g.members.size():
		return R.fail("NotFound", "member_handle")
	_set_members(g, left)
	_create(new_id, g.team_key, g.owner, checked.value)
	return R.ok(new_id)

func merge(into: int, source: int, context: Variant, expected_into: int, expected_source: int) -> Dictionary:
	var actor := _actor(context)
	if not _groups.has(into) or not _groups.has(source) or actor != _groups[into].owner or actor != _groups[source].owner:
		return R.fail("Unauthorized", "owner")
	return _merge(_groups[into], _groups[source], expected_into, expected_source)

func _merge(g: Dictionary, other: Dictionary, expected_into: int, expected_source: int) -> Dictionary:
	var into: int = g.id
	var source: int = other.id
	if into == source or g.team_key != other.team_key:
		return R.fail("InvalidArgument", "formation_ids")
	if expected_into != g.control_revision or expected_source != other.control_revision:
		return R.fail("Conflict", "control_revision")
	var combined: Array = g.members + other.members
	combined.sort_custom(func(a,b): return a.index < b.index)
	_clear(other, "Replaced", "formation_merged")
	_set_members(other, [])
	_set_members(g, combined)
	_groups.erase(source)
	return R.ok(into)

func set_delegate(id: int, actor_or_empty: String, context: Variant, expected_revision: int) -> Dictionary:
	var actor := _actor(context)
	if not _groups.has(id) or actor != _groups[id].owner:
		return R.fail("Unauthorized", "owner")
	return _delegate(_groups[id], actor_or_empty, expected_revision)

func _delegate(g: Dictionary, actor_or_empty: String, expected_revision: int) -> Dictionary:
	if g.control_revision != expected_revision:
		return R.fail("Conflict", "control_revision")
	if actor_or_empty == g.owner:
		return R.fail("InvalidArgument", "delegate")
	if actor_or_empty != g.delegate:
		var previous: String = g.delegate
		g.delegate = actor_or_empty
		g.control_revision += 1
		if not previous.is_empty():
			for job in g.queued.duplicate():
				if job.order.issuer_id == previous:
					_finish(g, job, "Failed", "control_revoked")
			if g.active != null and g.active.order.issuer_id == previous:
				_finish(g, g.active, "Failed", "control_revoked")
	return R.ok(g.control_revision)

## Auth and all selected scopes are checked even for a previously admitted order ID.
func issue_order(order: Dictionary, context: Variant, expected_control_revision: Variant) -> Dictionary:
	var actor := _actor(context)
	if actor.is_empty() or actor != order.get("issuer_id") or _mission != order.get("mission_id"):
		return R.fail("Unauthorized", "issuer")
	var shape := S.validate_shape("FormationOrder", order)
	if not shape.ok:
		return shape
	order = shape.value
	for id in order.formation_ids:
		if not _groups.has(id) or not _controlled(_groups[id], actor):
			return R.fail("Unauthorized", "formation_ids")
	if order.order_type in Orders.ORGANIZE and order.formation_ids.any(func(id): return _groups[id].owner != actor):
		return R.fail("Unauthorized", "owner")
	var uses_source: bool = order.order_type == "merge" or (order.order_type == "assign_members" and order.parameters.has("source_id"))
	if uses_source:
		var source: Variant = order.parameters.get("source_id")
		if _used_ids.get(source) != actor:
			return R.fail("Unauthorized", "source_id")
	var records: Dictionary = _history.get(actor, {})
	if records.has(order.order_id):
		var previous: Dictionary = records[order.order_id]
		if previous.order != order:
			return R.fail("Conflict", "order_id")
		# A newly granted delegation must not resurrect an old grant.
		for id in order.formation_ids:
			if actor != _groups[id].owner and previous.revisions[id] != _groups[id].control_revision:
				return R.fail("Unauthorized", "control_revision")
		return R.ok(previous.receipt.duplicate(true))
	var revisions := {}
	for id in order.formation_ids:
		var expected: Variant = expected_control_revision.get(id) if typeof(expected_control_revision) == TYPE_DICTIONARY else expected_control_revision
		if not V.integer(expected) or expected != _groups[id].control_revision:
			return R.fail("Conflict", "control_revision")
		revisions[id] = expected
	if order.issued_tick != _tick + 1 or order.client_sequence <= _last_sequence.get(actor, -1):
		return R.fail("Conflict", "sequence_or_tick")
	var checked := Orders.validate(order)
	if not checked.ok:
		return checked
	if uses_source and not _groups.has(order.parameters.source_id):
		return R.fail("NotFound", "source_id")
	var receipt := {"order_id":order.order_id, "issued_tick":order.issued_tick, "state":"Pending"}
	var job := {"order":order, "revisions":revisions, "receipt":receipt, "states":{},
		"source_revision":_groups[order.parameters.source_id].control_revision if uses_source else -1}
	for id in order.formation_ids:
		_mark(job, id, "Pending", "")
	records[order.order_id] = job
	_history[actor] = records
	_last_sequence[actor] = order.client_sequence
	_pending.append(job)
	return R.ok(receipt.duplicate(true))

func _mark(job: Dictionary, id: int, state: String, reason: String) -> void:
	job.states[id] = {"order_id":job.order.order_id, "issuer_id":job.order.issuer_id,
		"state":state, "reason":reason, "tick":_tick}

func _finish(g: Dictionary, job: Dictionary, state: String, reason: String) -> void:
	_mark(job, g.id, state, reason)
	g.feedback = job.states[g.id]
	if is_same(g.active, job):
		g.active = null
	g.queued.erase(job)

func _clear(g: Dictionary, state: String, reason: String) -> void:
	for job in g.queued.duplicate():
		_finish(g, job, state, reason)
	if g.active != null:
		_finish(g, g.active, state, reason)

func _failure(g: Dictionary, job: Dictionary, check_navigation: bool = true) -> String:
	var o: Dictionary = job.order
	var committed_owner: bool = is_same(g.active, job) and o.issuer_id == g.owner
	if not _controlled(g, o.issuer_id) or (g.control_revision != job.revisions[g.id] and not committed_owner):
		return "control_revoked"
	if o.parameters.get("expires_tick", V.MAX_INTEGER) < _tick:
		return "expired"
	if job.source_revision >= 0:
		if not _groups.has(o.parameters.source_id) or _groups[o.parameters.source_id].control_revision != job.source_revision:
			return "invalid_source"
	if o.issuer_id != g.owner and g.active != null and g.active.order.issuer_id == g.owner and g.active.revisions[g.id] == g.control_revision and Orders.policy(o) == "replace":
		return "player_priority"
	if o.order_type == "cancel":
		return ""
	if g.routing:
		return "routing"
	if o.target_formation_id != null:
		var target: Variant = _groups.get(o.target_formation_id)
		if target == null or target.id == g.id or target.members.is_empty() or ((target.team_key == g.team_key) != (o.order_type == "follow")):
			return "invalid_target"
	if check_navigation and o.target_position != null:
		if not _reachable.is_valid():
			return "unreachable"
		_in_callback = true
		var reaches: Variant = _reachable.call(g.id, o.target_position)
		_in_callback = false
		if typeof(reaches) != TYPE_BOOL or not reaches:
			return "unreachable"
	return ""

func _activate(g: Dictionary, job: Dictionary) -> void:
	var o: Dictionary = job.order
	match o.order_type:
		"layout": g.layout = o.parameters.layout
		"face":
			g.facing_microradians = o.parameters.facing_microradians
			g.facing_target_id = null
		"face_enemy": g.facing_target_id = o.target_formation_id
		"use_ranged": g.use_ranged = true
		"keep_distance": g.distance_mm = o.parameters.distance_mm
		"hold_fire", "fire_at_will": g.fire_mode = o.order_type
		"mount", "dismount": g.mounted = o.order_type == "mount"
		"assign_members", "split", "merge", "delegate", "appoint_captain":
			var result: Dictionary
			match o.order_type:
				"assign_members": result = _assign_deployed(g, o.parameters)
				"split": result = _split(g, o.parameters.new_formation_id, o.parameters.members, job.revisions[g.id])
				"merge": result = _merge(g, _groups[o.parameters.source_id], job.revisions[g.id], job.source_revision)
				_: result = _delegate(g, o.parameters.actor, job.revisions[g.id])
			if not result.ok:
				_finish(g, job, "Failed", result.error.field)
				return
		"move", "charge", "hold", "advance", "retreat", "free_attack", "follow":
			g.active = job
			_mark(job, g.id, "Active", "")
			g.feedback = job.states[g.id]
			return
	_finish(g, job, "Completed", "")

func _pump(g: Dictionary) -> void:
	while g.active == null and not g.queued.is_empty():
		var job: Dictionary = g.queued.pop_front()
		var reason := _failure(g, job)
		if reason.is_empty():
			_activate(g, job)
		else:
			_finish(g, job, "Failed", reason)

func _dispatch(g: Dictionary, job: Dictionary) -> void:
	var o: Dictionary = job.order
	var policy := Orders.policy(o)
	if policy == "immediate":
		_activate(g, job)
		return
	if policy == "append" and g.active != null:
		g.queued.append(job)
		_mark(job, g.id, "Pending", "queued")
		return
	_clear(g, "Replaced", "superseded" if o.order_type != "cancel" else "cancelled")
	_activate(g, job)

## Exactly one Mission fixed step. Batch validation precedes all selected-group writes.
func advance(tick: int) -> Dictionary:
	if _in_callback or tick != _tick + 1:
		return R.fail("Conflict", "tick")
	_tick = tick
	var ids := _groups.keys()
	ids.sort()
	for id in ids:
		var g: Dictionary = _groups[id]
		for job in g.queued.duplicate():
			if job.order.parameters.get("expires_tick", V.MAX_INTEGER) < tick:
				_finish(g, job, "Failed", "expired")
		if g.active != null:
			var reason := _failure(g, g.active)
			if not reason.is_empty():
				_finish(g, g.active, "Failed", reason)
		_pump(g)
	# Preflight once so a failed player order cannot displace a valid delegated one.
	var claims := {}
	var eligible := []
	for job in _pending:
		var failure := ""
		for id in job.order.formation_ids:
			failure = _failure(_groups[id], job) if _groups.has(id) else "formation_merged"
			if failure != "":
				break
		if failure != "":
			for id in job.order.formation_ids:
				_mark(job, id, "Failed", failure)
				if _groups.has(id):
					_groups[id].feedback = job.states[id]
			continue
		eligible.append(job)
		for id in job.order.formation_ids:
			if _groups[id].owner == job.order.issuer_id:
				claims[id] = true
	eligible.sort_custom(func(a, b):
		if a.order.issuer_id != b.order.issuer_id:
			return a.order.issuer_id < b.order.issuer_id
		return a.order.client_sequence < b.order.client_sequence)
	for job in eligible:
		var loses := false
		for id in job.order.formation_ids:
			if claims.has(id) and _groups.has(id) and job.order.issuer_id != _groups[id].owner:
				loses = true
		# Recheck identities affected by an earlier same-tick organization order.
		var reason := ""
		for id in job.order.formation_ids:
			reason = _failure(_groups[id], job, false) if _groups.has(id) else "formation_merged"
			if reason != "":
				break
		for id in job.order.formation_ids:
			if loses:
				_mark(job, id, "Replaced", "player_priority")
			elif reason != "":
				_mark(job, id, "Failed", reason)
				if _groups.has(id):
					_groups[id].feedback = job.states[id]
			else:
				_dispatch(_groups[id], job)
	_pending.clear()
	return R.ok(tick)

## Mission executor signals arrival or explicit completion. Stale acknowledgments cannot
## complete a newer order since the issuer and order ID must both match.
func complete_active(id: int, issuer: String, order_id: String, condition: String) -> Dictionary:
	if _in_callback or not _groups.has(id):
		return R.fail("InvalidState", "formation")
	var g: Dictionary = _groups[id]
	if g.active == null or g.active.order.issuer_id != issuer or g.active.order.order_id != order_id:
		return R.fail("Conflict", "active_order")
	if condition != Orders.completion(g.active.order):
		return R.fail("Conflict", "completion_condition")
	_finish(g, g.active, "Completed", "")
	_pump(g)
	return R.ok()

func set_routing(id: int, routing: bool) -> Dictionary:
	if _in_callback or not _groups.has(id):
		return R.fail("InvalidState", "formation")
	var g: Dictionary = _groups[id]
	g.routing = routing
	if routing:
		_clear(g, "Failed", "routing")
	return R.ok()

func build_slot_targets(id: int, center: Vector3, yaw: float, spacing: float, clear_width: float, project_batch: Callable) -> Dictionary:
	if _in_callback or not _groups.has(id):
		return R.fail("InvalidState", "formation")
	var g: Dictionary = _groups[id]
	_in_callback = true
	var result: Dictionary = g.layout_state.rebuild(g.members, g.layout, center, yaw, spacing, clear_width, project_batch)
	_in_callback = false
	if result.ok:
		g.terrain_feedback = {}
	elif result.error.get("code") == "Unavailable":
		g.terrain_feedback = {"reason":"unreachable", "field":result.error.get("field", "terrain"), "tick":_tick}
		if g.active != null:
			_finish(g, g.active, "Failed", "unreachable")
	return result

func view(id: int) -> Dictionary:
	if not _groups.has(id):
		return R.fail("NotFound", "formation")
	var g: Dictionary = _groups[id]
	var out := {"id":id, "team_key":g.team_key, "owner":g.owner, "delegate":g.delegate,
		"control_revision":g.control_revision, "members":g.members.duplicate(true), "members_revision":g.members_revision, "layout":g.layout,
		"routing":g.routing, "fire_mode":g.fire_mode, "mounted":g.mounted, "facing_microradians":g.facing_microradians,
		"facing_target_id":g.facing_target_id, "use_ranged":g.use_ranged, "distance_mm":g.distance_mm,
		"terrain_feedback":g.terrain_feedback.duplicate(),
		"active":null if g.active == null else g.active.order, "queued":[], "feedback":g.feedback.duplicate()}
	for job in g.queued:
		out.queued.append(job.order)
	return R.ok(out)

func order_status(actor: String, id: String) -> Dictionary:
	var job: Variant = _history.get(actor, {}).get(id)
	if job == null:
		return R.fail("NotFound", "order_id")
	return R.ok(job.states.duplicate(true))
