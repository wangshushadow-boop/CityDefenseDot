extends RefCounted

const R = preload("res://contracts/result.gd")
const S = preload("res://contracts/schema.gd")
const V = preload("res://contracts/values.gd")
const RANGE_PER_TICK := {"bow":1700, "crossbow":2800, "throw":1100}
const POWER := {"bow":16, "crossbow":20, "throw":12}
const LIFETIME := 90


static func vector(value: Variant, limit: int) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == 3 and value.all(func(v): return V.integer(v, -limit, limit))


static func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func mm(v: Vector3) -> Array:
	return [roundi(v.x), roundi(v.y), roundi(v.z)]


static func _query(origin: Array, end: Array, radius: int) -> Dictionary:
	return {"from":origin, "to":end, "radius_mm":radius}


static func _hit_less(a: Dictionary, b: Dictionary) -> bool:
	if a.query_index != b.query_index:
		return a.query_index < b.query_index
	if a.fraction_ppm != b.fraction_ppm:
		return a.fraction_ppm < b.fraction_ppm
	var index_a: int = -1 if a.get("target") == null else a.target.index
	var index_b: int = -1 if b.get("target") == null else b.target.index
	if index_a != index_b:
		return index_a < index_b
	if (a.get("region") == "shield") != (b.get("region") == "shield"):
		return a.get("region") == "shield"
	return str(a.get("region","")) < str(b.get("region",""))


static func collect(tick: int, active: Array, states: Dictionary, poses: Dictionary, sweep: Callable, flights: Dictionary, events: Array) -> Dictionary:
	var queries := []
	var owners := []
	for swing: Dictionary in active:
		var weapon: String = swing.weapon
		if weapon != "melee" and swing.released != tick:
			continue
		var pose: Variant = poses.get(swing.attacker.index)
		if typeof(pose) != TYPE_DICTIONARY or not vector(pose.get("position_mm"), 1000000000) or not vector(pose.get("facing_ppm"),1000000):
			return R.fail("InvalidArgument", "attacker_pose")
		var forward := v3(pose.facing_ppm).normalized()
		if forward == Vector3.ZERO:
			return R.fail("InvalidArgument", "facing_ppm")
		var origin: Array = pose.position_mm
		if weapon == "melee":
			var begin := v3(origin)
			var end := begin + forward * 1500
			if swing.direction in ["left","right"]:
				var side := forward.cross(Vector3.UP).normalized() * (1 if swing.direction == "left" else -1)
				var arc_offset := 330.0 if tick == swing.released else -330.0
				begin += forward * 280 + side * arc_offset
				end -= side * arc_offset
			elif swing.direction == "up":
				begin.y += 230
				end.y -= 160
			queries.append(_query(mm(begin), mm(end), 80))
			var on_mount: bool = states[swing.attacker.index].get("mount_handle") != null
			if not V.integer(pose.get("speed_mm_tick", 0), 0, 1000000):
				return R.fail("InvalidArgument", "speed_mm_tick")
			owners.append({"swing":swing, "projectile":false, "forward":forward,
				"bonus":mini(5, int(pose.get("speed_mm_tick", 0) / 100.0)) if on_mount else 0})
		else:
			flights[swing.attack_id] = {"swing":swing.duplicate(true), "start":tick, "position":origin.duplicate(),
				"velocity":mm(forward * RANGE_PER_TICK[weapon]), "power":POWER[weapon] + swing.charge}
			events.append({"type":"projectile_launched", "actor_handle":swing.attacker.duplicate(), "attack_id":swing.attack_id})
	for id in flights.keys():
		var shot: Dictionary = flights[id]
		if tick - shot.start >= LIFETIME:
			flights.erase(id)
			continue
		var end := mm(v3(shot.position) + v3(shot.velocity))
		queries.append(_query(shot.position, end, 15))
		owners.append({"swing":shot.swing, "projectile":true, "forward":v3(shot.velocity).normalized(), "power":shot.power})
		var moved := shot.duplicate()
		moved.position = end
		moved.velocity = [shot.velocity[0], shot.velocity[1] - 3, shot.velocity[2]]
		flights[id] = moved
	if queries.is_empty():
		return R.ok([])
	if not sweep.is_valid():
		return R.fail("Unavailable", "sweep")
	var reply: Variant = sweep.call(queries.duplicate(true), tick)
	if typeof(reply) != TYPE_DICTIONARY or typeof(reply.get("ok")) != TYPE_BOOL:
		return R.fail("InvalidArgument", "sweep")
	if not reply.ok:
		return reply if typeof(reply.get("error")) == TYPE_DICTIONARY else R.fail("Unavailable", "sweep")
	if typeof(reply.get("value")) != TYPE_ARRAY:
		return R.fail("InvalidArgument", "sweep")
	var ordered: Array = reply.value.duplicate()
	for hit in ordered:
		if typeof(hit) != TYPE_DICTIONARY or not V.integer(hit.get("query_index"), 0, queries.size()-1) or not V.integer(hit.get("fraction_ppm"), 0, 1000000):
			return R.fail("InvalidArgument", "collision_hit")
		if hit.get("target") != null and not S.validate_shape("AgentHandle", hit.target).ok:
			return R.fail("InvalidArgument", "collision_target")
		if typeof(hit.get("region", "body")) != TYPE_STRING:
			return R.fail("InvalidArgument","collision_region")
	ordered.sort_custom(_hit_less)
	var contacts := []
	var stopped := {}
	var impacted := {}
	for hit: Dictionary in ordered:
		var q: int = hit.query_index
		if stopped.has(q):
			continue
		var owner: Dictionary = owners[q]
		var swing: Dictionary = owner.swing
		if hit.get("target") == null:
			stopped[q] = true
			if owner.projectile and flights.erase(swing.attack_id):
				events.append({"type":"projectile_obstructed", "attack_id":swing.attack_id})
			continue
		var victim: Dictionary = states.get(hit.target.index,{})
		if victim.is_empty() or victim.handle != hit.target or victim.phase == "Downed" or victim.handle == swing.attacker:
			continue
		if victim.get("rider_handle") == swing.attacker or victim.get("mount_handle") == swing.attacker:
			continue
		var region: String = hit.get("region","body")
		var facing := true
		if victim.phase == "Guard":
			var guard_pose: Variant = poses.get(hit.target.index)
			if typeof(guard_pose) != TYPE_DICTIONARY or not vector(guard_pose.get("facing_ppm"),1000000):
				return R.fail("InvalidArgument","guard_pose")
			facing = v3(guard_pose.facing_ppm).dot(owner.forward) < 0
		if region == "shield":
			if victim.get("shield",0) <= 0 or victim.phase != "Guard" or victim.direction != swing.direction or not facing:
				continue
		if owner.projectile:
			if impacted.has(q) and impacted[q] != hit.target:
				stopped[q] = true
				continue
			impacted[q] = hit.target
			flights.erase(swing.attack_id)
		if victim.team == swing.team:
			stopped[q] = true
			continue
		var contact := {"attacker":swing.attacker, "target":victim.handle, "attack_id":swing.attack_id,
			"contact_order":contacts.size(), "region":region, "team":swing.team, "guard_facing":facing}
		if owner.projectile:
			contact.merge({"projectile":true, "power":owner.power})
		else:
			contact.charge_bonus = owner.bonus
		contacts.append(contact)
	return R.ok(contacts)
