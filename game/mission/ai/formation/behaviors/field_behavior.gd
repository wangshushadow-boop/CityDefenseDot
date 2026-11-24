extends RefCounted

const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const GOALS := ["hold", "advance", "retreat", "cover", "harass", "flank"]
const ROLES := ["infantry", "archer", "cavalry", "mounted_archer"]
const ARRIVAL := 1.5
const RANGED_NEAR := 4.0
const RANGED_FAR := 20.0

static func valid_task(task: Dictionary, formation_id: int) -> bool:
	return typeof(task.get("id")) == TYPE_STRING and not task.id.is_empty() \
		and is_same(task.get("formation_id"), formation_id) and task.get("goal") in GOALS and task.get("role") in ROLES \
		and task.has("position") and (task.position == null or (task.position is Vector3 and task.position.is_finite())) \
		and task.has("target_formation") and (task.target_formation == null or V.integer(task.target_formation, 0, V.MAX_U32)) \
		and V.integer(task.get("priority")) and V.integer(task.get("timeout")) and V.integer(task.get("control_revision")) \
		and task.get("completion") in ["arrived", "executed"] and task.get("constraints") is Dictionary \
		and typeof(task.constraints.get("fire_allowed")) == TYPE_BOOL and typeof(task.constraints.get("engage_allowed")) == TYPE_BOOL

static func valid_ground(ground: Dictionary) -> bool:
	for field in ["clear_width", "spacing", "slot_error", "yaw"]:
		var value: Variant = ground.get(field)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
			return false
	return typeof(ground.get("compressed",false)) == TYPE_BOOL and ground.clear_width > 0 and ground.spacing > 0 and ground.slot_error >= 0 and typeof(ground.get("reachable")) == TYPE_BOOL

static func _contact(visible: Array, target: Variant, origin: Vector3) -> Dictionary:
	var best := {}
	var distance := INF
	for row: Dictionary in visible:
		if target != null and row.formation_id != target:
			continue
		var d := origin.distance_squared_to(row.position)
		if d < distance or (d == distance and row.handle.index < best.handle.index):
			best = row
			distance = d
	return best

static func aggregate(units: Array) -> Dictionary:
	var sum := Vector3.ZERO
	var living := 0
	var ammo := 0
	for own: Dictionary in units:
		if own.get("hp", 1) <= 0:
			continue
		living += 1
		sum += Vector3(own.position)
		if own.role in ["archer", "mounted_archer"]:
			ammo += int(own.get("ammo", 0))
	return {"center":sum / maxi(1, living), "count":living, "ammo":ammo}

static func _current_order(order: Dictionary) -> String:
	match order.order_type:
		"follow": return "Follow"
		"charge", "free_attack": return "Charge"
		"move": return "Move"
		"advance": return "Advance"
		"retreat": return "Retreat"
	return "Hold"

static func _from_task(task: Dictionary, contact: Dictionary, center: Vector3, previous: Dictionary, minimum_range: float, tick: int) -> String:
	var at_site: bool = task.position == null or center.distance_to(task.position) <= ARRIVAL
	match task.goal:
		"retreat": return "Retreat"
		"hold": return "Hold" if at_site else "Move"
		"advance": return "Advance"
		"cover", "harass":
			if not at_site:
				return "Move"
			if contact.is_empty():
				return "Hold"
			var distance := center.distance_to(contact.position)
			if distance < minimum_range:
				return "Retreat"
			return "Fire" if distance <= maxf(minimum_range,RANGED_FAR) else "Hold"
		"flank":
			var near_contact := not contact.is_empty() and center.distance_to(contact.position) < RANGED_NEAR
			if (previous.get("behavior") == "Charge" and near_contact) or (previous.get("recovery") == "charge" and tick < previous.get("retry_after",0)):
				return "Regroup"
			if not at_site:
				return "Move"
			if contact.is_empty() or not task.constraints.engage_allowed:
				return "Hold"
			return "Charge"
	return "Hold"

## Uses only FINITE coordinates and a scoped formation's permitted contacts.
static func decide(task: Variant, intel: Dictionary, form: Dictionary, ground: Dictionary, old: Dictionary, actor: String, ally_position: Variant) -> Dictionary:
	var tick: int = intel.stamp.tick
	var own := aggregate(intel.own_units)
	var center: Vector3 = own.center
	var active: Variant = form.active
	var controlling: bool = actor in [form.owner, form.delegate]
	var standing: bool = active != null and active.issuer_id != actor
	var queued_owner: bool = form.queued.any(func(o): return o.issuer_id != actor)
	var intent_task: bool = task != null and controlling and not standing and not queued_owner
	var goal: Variant = center
	var target: Variant = null
	var minimum_range := maxf(RANGED_NEAR, float(form.distance_mm)*.001)
	if intent_task:
		goal = task.position if task.position != null else center
		target = task.target_formation
	elif active != null:
		target = active.target_formation_id
		if active.order_type == "follow" and ally_position != null:
			goal = ally_position
		if active.target_position != null:
			var p: Array = active.target_position
			goal = Vector3(p[0], p[1], p[2]) * .001
	var contact := _contact(intel.visible_enemies, target, center)
	var behavior := "Hold"
	var status := "running"
	var reason := ""
	var narrow: bool = own.count > 1 and (ground.get("compressed",false) or ground.clear_width < ground.spacing * 2.0)
	var loss: bool = own.count < old.get("count", own.count)
	var recovering: bool = ground.slot_error > maxf(ground.spacing * 2.0, ARRIVAL) or (old.get("behavior") == "Regroup" and ground.slot_error > ARRIVAL)
	if task != null and not intent_task:
		status = "blocked"
		reason = "player_order" if standing or queued_owner else "not_delegated"
	if active != null and not intent_task:
		behavior = _current_order(active)
		if (active.order_type == "charge" and contact.is_empty()) or (active.order_type == "follow" and ally_position == null) or (not ground.reachable and behavior != "Hold"):
			behavior = "Hold"
	if form.routing or own.count == 0:
		behavior = "Retreat" if form.routing else "Hold"
		status = "failed"
		reason = "routing" if form.routing else "no_members"
	elif intent_task:
		if tick >= task.timeout:
			status = "failed"
			reason = "timeout"
		elif not ground.reachable or not form.terrain_feedback.is_empty() or form.feedback.get("reason") == "unreachable":
			status = "blocked"
			reason = "unreachable"
		elif task.goal in ["cover","harass"] and own.ammo == 0:
			status = "failed"
			reason = "ammo_depleted"
		elif target != null and contact.is_empty():
			status = "blocked"
			reason = "target_not_visible"
		elif narrow or loss or recovering:
			behavior = "Regroup"
			status = "blocked"
			reason = "casualties" if loss else ("bottleneck" if narrow else "reforming")
		else:
			behavior = _from_task(task, contact, center, old, minimum_range, tick)
			if behavior == "Fire" and (form.fire_mode == "hold_fire" or not task.constraints.fire_allowed):
				behavior = "Hold"
				status = "blocked"
				reason = "fire_restricted"
			elif behavior == "Regroup":
				reason = "charge_recovery"
			elif task.completion == "executed" and behavior in ["Hold", "Fire"] and (task.goal == "hold" or behavior == "Fire"):
				status = "completed"
				reason = "executed"
	# A narrowing changes the slots. Keep the reachable destination so the group
	# can actually clear the passage while reforming.
	var passage_move: bool = behavior == "Regroup" and narrow and intent_task and task.position != null and center.distance_to(task.position) > ARRIVAL
	var recovering_charge := reason == "charge_recovery"
	if intent_task and not form.routing and own.count > 0 and tick < task.timeout and task.completion == "arrived" and task.position != null and center.distance_to(task.position) <= ARRIVAL:
		status = "completed"
		reason = "arrived"
		if behavior in ["Move","Advance","Retreat"]:
			behavior = "Hold"
	var retry_after: int = old.get("retry_after",0) if recovering_charge and old.get("recovery") == "charge" else (tick + 8 if recovering_charge else 0)
	if recovering_charge and not contact.is_empty() and center.distance_to(goal) <= ARRIVAL:
		goal = center - center.direction_to(contact.position) * RANGED_NEAR
	elif behavior in ["Hold","Fire"] or (behavior == "Regroup" and not passage_move and not recovering_charge):
		goal = center
	elif behavior == "Charge" and not contact.is_empty():
		goal = contact.position
	elif behavior == "Retreat" and intent_task and task.goal in ["harass","cover"] and not contact.is_empty():
		var away := center.direction_to(contact.position)
		goal = center - away * minimum_range
	var fire_allowed: bool = form.fire_mode != "hold_fire" and behavior not in ["Retreat","Regroup"] and own.ammo > 0
	var engage_allowed := behavior in ["Advance","Charge","Fire"]
	if intent_task:
		fire_allowed = fire_allowed and task.constraints.fire_allowed
		engage_allowed = engage_allowed and task.constraints.engage_allowed
	var moving := behavior in ["Move","Follow","Advance","Charge","Retreat","Regroup"]
	var constraint := {"fire_allowed":fire_allowed, "engage_allowed":engage_allowed,
		"slot_tolerance":ground.spacing * (2.0 if behavior == "Charge" else 0.5),
		"focus_target":contact.get("handle") if fire_allowed or engage_allowed else null,
		"movement_limit":maxf(ground.spacing, center.distance_to(goal)) if moving else 0.0}
	return {"behavior":behavior, "local_goal":goal, "count":own.count, "task_id":task.id if task != null else null,
		"member_constraint":constraint, "command":intent_task and not form.routing and own.count > 0,
		"positioned":intent_task and task.position != null, "regroup_move":passage_move or recovering_charge,
		"retry_after":retry_after, "recovery":"charge" if recovering_charge else "",
		"feedback":{"status":status, "reason":reason, "formation_id":form.id, "task_id":task.id,
			"progress":1.0 if status == "completed" else 0.0} if task != null else null,
		"slot_request":{"formation_id":form.id, "center":center, "yaw":ground.yaw, "spacing":ground.spacing, "clear_width":ground.clear_width},
		"target":target, "contact_formation":contact.get("formation_id")}
