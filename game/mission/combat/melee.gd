extends RefCounted
## Mission-local, fixed-step melee. Candidates come from authority collision queries.
## A coordinator may advance a fork and publish it only after later phases succeed.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const S = preload("res://contracts/schema.gd")
const DIRECTIONS := ["up", "left", "right", "thrust"]

# Private game tuning in simulation ticks and abstract hit points.
const WINDUP_TICKS := 3
const CANCEL_TICKS := 2
const ACTIVE_TICKS := 2
const RECOVERY_TICKS := 3
const STAGGER_TICKS := 2
const MAX_CHARGE := 4

var _tick := 0
var _actors := {}
var _querying := false


func fork():
	var copy = get_script().new()
	copy._tick = _tick
	copy._actors = _actors.duplicate()
	return copy


func add_actor(handle: Dictionary, hp: Variant = 100, weapon_slot: Variant = 0, max_targets: Variant = 1) -> Dictionary:
	if _querying:
		return R.fail("InvalidState", "collision_query")
	var valid := S.validate_shape("AgentHandle", handle)
	if not valid.ok:
		return valid
	if not V.integer(hp, 1) or not V.integer(weapon_slot, 0, V.MAX_U32) or not V.integer(max_targets, 1, V.MAX_U32):
		return R.fail("InvalidArgument", "combatant")
	if _actors.has(handle.index):
		return R.fail("Conflict", "actor_handle")
	_actors[handle.index] = {"handle":valid.value, "hp":hp, "weapon_slot":weapon_slot, "max_targets":max_targets,
		"phase":"Ready", "since":_tick, "direction":"", "charge":0, "attack_id":"", "hit_set":{}}
	return R.ok()


func _actor(handle: Dictionary, states: Dictionary) -> Dictionary:
	if handle.size() != 2 or not V.integer(handle.get("index"), 0, V.MAX_U32) or not V.integer(handle.get("generation"), 1, V.MAX_U32):
		return {}
	var row: Dictionary = states.get(handle.get("index"), {})
	if row.is_empty() or row.handle != handle:
		return {}
	return row


func remove_actor(handle: Dictionary) -> Dictionary:
	if _querying:
		return R.fail("InvalidState", "collision_query")
	if _actor(handle, _actors).is_empty():
		return R.fail("NotFound", "actor_handle")
	_actors.erase(handle.index)
	return R.ok()


func view(handle: Dictionary) -> Dictionary:
	var state := _actor(handle, _actors)
	if state.is_empty():
		return R.fail("NotFound", "actor_handle")
	var visible := state.duplicate(true)
	visible.erase("hit_set")
	return R.ok(visible)


static func _enter(state: Dictionary, phase: String, tick: int) -> void:
	state.phase = phase
	state.since = tick
	if phase not in ["Active", "Hold", "Windup"]:
		state.attack_id = ""
		state.charge = 0
		state.hit_set = {}


static func _elapsed_phase(state: Dictionary, tick: int) -> String:
	var elapsed: int = tick - state.since
	match state.phase:
		"Windup":
			if elapsed >= WINDUP_TICKS:
				return "Hold"
		"Active":
			if elapsed >= ACTIVE_TICKS:
				return "Recovery"
		"Recovery":
			if elapsed >= RECOVERY_TICKS:
				return "Ready"
		"Stagger":
			if elapsed >= STAGGER_TICKS:
				return "Ready"
	return state.phase


static func _cancel_allowed(state: Dictionary, tick: int) -> bool:
	return state.phase == "Windup" and tick - state.since < CANCEL_TICKS


static func _apply(state: Dictionary, intent: Dictionary, tick: int) -> Dictionary:
	if intent.direction not in DIRECTIONS:
		return R.fail("InvalidArgument", "direction")
	if intent.has("held"):
		if intent.held:
			if state.phase not in ["Ready", "Guard"] and not _cancel_allowed(state, tick):
				return R.fail("InvalidState", "guard")
			state.direction = intent.direction
			_enter(state, "Guard", tick)
		elif state.phase == "Guard":
			_enter(state, "Ready", tick)
		else:
			return R.fail("InvalidState", "guard")
		return R.ok()
	if intent.weapon_slot != state.weapon_slot:
		return R.fail("InvalidArgument", "weapon_slot")
	match intent.input_phase:
		"start":
			if state.phase != "Ready":
				return R.fail("InvalidState", "start")
			state.direction = intent.direction
			_enter(state, "Windup", tick)
		"hold":
			if state.direction != intent.direction or state.phase not in ["Windup", "Hold"]:
				return R.fail("InvalidState", "hold")
		"release":
			if state.direction != intent.direction or state.phase != "Hold":
				return R.fail("InvalidState", "release")
			state.charge = mini(MAX_CHARGE, tick - state.since)
			_enter(state, "Active", tick)
			state.attack_id = "%d:%d:%d" % [tick, state.handle.index, state.handle.generation]
			state.hit_set = {}
		"cancel":
			if not _cancel_allowed(state, tick):
				return R.fail("InvalidState", "cancel")
			_enter(state, "Ready", tick)
		_:
			return R.fail("InvalidArgument", "input_phase")
	return R.ok()


static func _contact_less(a: Dictionary, b: Dictionary) -> bool:
	if a.contact_order != b.contact_order:
		return a.contact_order < b.contact_order
	if a.attacker.index != b.attacker.index:
		return a.attacker.index < b.attacker.index
	return a.target.index < b.target.index


static func _contacts(states: Dictionary, candidates: Array) -> Dictionary:
	var ordered := []
	for c in candidates:
		if typeof(c) != TYPE_DICTIONARY or typeof(c.get("attack_id")) != TYPE_STRING or not V.integer(c.get("contact_order")):
			return R.fail("InvalidArgument", "contact")
		for field: String in ["attacker", "target"]:
			if not S.validate_shape("AgentHandle", c.get(field)).ok:
				return R.fail("InvalidArgument", "contact." + field)
		ordered.append(c)
	ordered.sort_custom(_contact_less)
	var damages := {}
	var events := []
	for c: Dictionary in ordered:
		var attacker: Dictionary = states.get(c.attacker.index, {})
		var target: Dictionary = states.get(c.target.index, {})
		if attacker.is_empty() or target.is_empty() or attacker.handle != c.attacker or target.handle != c.target:
			continue
		if attacker.phase != "Active" or attacker.attack_id != c.attack_id or target.phase == "Downed" or c.attacker == c.target:
			continue
		var target_key := "%d:%d" % [c.target.index, c.target.generation]
		if attacker.hit_set.has(target_key) or attacker.hit_set.size() >= attacker.max_targets:
			continue
		# Copy both containers so a rejected candidate tick cannot mutate its parent fork.
		attacker = attacker.duplicate()
		attacker.hit_set = attacker.hit_set.duplicate()
		attacker.hit_set[target_key] = true
		states[c.attacker.index] = attacker
		var blocked: bool = target.phase == "Guard" and target.direction == attacker.direction
		var damage: int = 0 if blocked else 10 + attacker.charge
		if damage > 0:
			damages[c.target.index] = damages.get(c.target.index, 0) + damage
		events.append({"attack_id":attacker.attack_id, "attacker":attacker.handle, "target":target.handle,
			"blocked":blocked, "damage":damage})
	return R.ok({"damages":damages, "events":events})


func step(tick: Variant, intents: Array, query_contacts: Callable = Callable()) -> Dictionary:
	if _querying:
		return R.fail("InvalidState", "collision_query")
	if not V.integer(tick, 1) or tick != _tick + 1:
		return R.fail("StaleVersion", "tick")
	# Structural errors reject the tick; an illegal action receives a rejection
	# receipt and cannot stall other actors' fixed-step clocks.
	var next := _actors.duplicate()
	for index in next:
		var state: Dictionary = next[index]
		var phase := _elapsed_phase(state, tick)
		if phase != state.phase:
			state = state.duplicate()
			_enter(state, phase, tick)
			next[index] = state
	var receipts := []
	for intent in intents:
		if typeof(intent) != TYPE_DICTIONARY:
			return R.fail("InvalidArgument", "intent")
		var kind := "BlockIntent" if intent.has("held") else "AttackIntent"
		var validated := S.validate_shape(kind, intent)
		if not validated.ok:
			return validated
		var state := _actor(intent.actor_handle, next)
		if state.is_empty():
			receipts.append(R.fail("NotFound", "actor_handle"))
			continue
		state = state.duplicate()
		var receipt := _apply(state, validated.value, tick)
		if receipt.ok:
			next[intent.actor_handle.index] = state
		receipts.append(receipt)
	var candidates := []
	if not query_contacts.is_null():
		if not query_contacts.is_valid():
			return R.fail("Unavailable", "collision_query")
		var active := []
		for state: Dictionary in next.values():
			if state.phase == "Active":
				active.append({"attacker":state.handle, "attack_id":state.attack_id, "direction":state.direction})
		active.sort_custom(func(a, b): return a.attacker.index < b.attacker.index)
		if not active.is_empty():
			_querying = true
			var result: Variant = query_contacts.call(tick, active)
			_querying = false
			if typeof(result) != TYPE_DICTIONARY or typeof(result.get("ok")) != TYPE_BOOL:
				return R.fail("InvalidArgument", "collision_query")
			if not result.ok:
				return result if typeof(result.get("error")) == TYPE_DICTIONARY else R.fail("Unavailable", "collision_query")
			if typeof(result.get("value")) != TYPE_ARRAY:
				return R.fail("InvalidArgument", "collision_query")
			candidates = result.value
	var contacts := _contacts(next, candidates)
	if not contacts.ok:
		return contacts
	# All contact eligibility was sampled before any simultaneous damage.
	for index in contacts.value.damages:
		var state: Dictionary = next[index].duplicate()
		state.hp = maxi(0, state.hp - contacts.value.damages[index])
		_enter(state, "Downed" if state.hp == 0 else "Stagger", tick)
		next[index] = state
	_actors = next
	_tick = tick
	return R.ok({"tick":_tick, "receipts":receipts, "hits":contacts.value.events})
