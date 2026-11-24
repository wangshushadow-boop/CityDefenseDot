extends "res://mission/combat/melee.gd"
## Authority-side assembly port. Actor rows and fixed ticks are inherited from melee.
const Sweeps = preload("res://mission/combat/field_sweeps.gd")
const MAX_NEIGHBORS := 4
const NEIGHBOR_MM := 8000
const MAX_SOURCES := 16
const SPREAD_TICKS := 15
var _shots := {}
var _pending_spread := {}
var _sampling := {}


func fork():
	var copy = super.fork()
	copy._shots = _shots.duplicate()
	copy._pending_spread = _pending_spread.duplicate()
	return copy


func add_actor(handle: Dictionary, hp: Variant = 100, weapon_slot: Variant = 0, max_targets: Variant = 1) -> Dictionary:
	if not V.integer(weapon_slot,0,0):
		return R.fail("InvalidArgument","weapon_slot")
	return enlist(handle,{"team":0,"role":"infantry","hp":hp,"max_targets":max_targets})


func enlist(handle: Dictionary, profile: Dictionary) -> Dictionary:
	var role: Variant = profile.get("role")
	if not V.integer(profile.get("team"), 0, V.MAX_U32) or typeof(role) != TYPE_STRING or role not in ["infantry","archer","cavalry","mount"]:
		return R.fail("InvalidArgument", "profile")
	for field in ["hp","max_targets","shield","ammo","morale"]:
		var minimum := 1 if field in ["hp","max_targets"] else 0
		var maximum := 100 if field == "morale" else 1000000
		if profile.has(field) and not V.integer(profile[field], minimum, maximum):
			return R.fail("InvalidArgument", field)
	if typeof(profile.get("commander",false)) != TYPE_BOOL:
		return R.fail("InvalidArgument", "commander")
	var armor: Variant = profile.get("armor",{})
	if typeof(armor) != TYPE_DICTIONARY:
		return R.fail("InvalidArgument", "armor")
	for region in armor:
		if region not in ["head","body","limb"] or not V.integer(armor[region], 0, 100000):
			return R.fail("InvalidArgument", "armor")
	var weapons := ["melee"]
	if role == "archer" or profile.has("ranged"):
		var ranged: Variant = profile.get("ranged","bow")
		if typeof(ranged) != TYPE_STRING or not Sweeps.RANGE_PER_TICK.has(ranged):
			return R.fail("InvalidArgument","ranged")
		weapons.append(ranged)
	var result := super.add_actor(handle, profile.get("hp",100), 1 if role == "archer" else 0, profile.get("max_targets",1))
	if not result.ok:
		return result
	_actors[handle.index].merge({"team":profile.team, "role":role, "weapons":weapons, "shield":profile.get("shield",0),
		"ammo":profile.get("ammo",8), "armor":armor.duplicate(), "reload_until":0, "mount_handle":null, "rider_handle":null,
		"morale":profile.get("morale",70), "routing":false, "commander":profile.get("commander",false), "last_spread":-SPREAD_TICKS})
	return R.ok()


func mount(rider: Dictionary, horse: Dictionary) -> Dictionary:
	if _querying:
		return R.fail("InvalidState","collision_query")
	var a := _actor(rider, _actors)
	var b := _actor(horse, _actors)
	if a.is_empty() or b.is_empty():
		return R.fail("NotFound","actor_handle")
	if a.role != "cavalry" or b.role != "mount" or a.team != b.team or a.phase == "Downed" or b.phase == "Downed" or a.routing or b.routing:
		return R.fail("InvalidState", "mount")
	if a.mount_handle != null or b.rider_handle != null:
		return R.fail("Conflict", "mount")
	a = a.duplicate()
	b = b.duplicate()
	a.mount_handle = b.handle
	b.rider_handle = a.handle
	_actors[rider.index] = a
	_actors[horse.index] = b
	return R.ok()


func _unlink(rider: Dictionary, horse: Dictionary, fallen: bool) -> void:
	var a: Dictionary = _actors[rider.index].duplicate()
	var b: Dictionary = _actors[horse.index].duplicate()
	a.mount_handle = null
	b.rider_handle = null
	if fallen and a.phase != "Downed":
		_enter(a, "Stagger", _tick)
	_actors[rider.index] = a
	_actors[horse.index] = b


func dismount(rider: Dictionary) -> Dictionary:
	if _querying:
		return R.fail("InvalidState","collision_query")
	var state := _actor(rider,_actors)
	if state.is_empty():
		return R.fail("NotFound","actor_handle")
	if state.get("mount_handle") == null:
		return R.fail("InvalidState","mount")
	_unlink(rider,state.mount_handle,false)
	return R.ok()


func remove_actor(handle: Dictionary) -> Dictionary:
	if _querying:
		return R.fail("InvalidState","collision_query")
	var state := _actor(handle,_actors)
	if state.get("mount_handle") != null:
		_unlink(handle,state.mount_handle,false)
	elif state.get("rider_handle") != null:
		_unlink(state.rider_handle,handle,true)
	return super.remove_actor(handle)


func has_pending_projectiles() -> bool:
	return not _shots.is_empty()


func _query_active(tick: int, active: Array, states: Dictionary, query: Callable) -> Variant:
	_sampling = states
	var result: Variant = super._query_active(tick, active, states, query)
	_sampling = {}
	return result


func step_field(tick: Variant, intents: Array, poses: Dictionary, sweep: Callable, morale_events: Array = []) -> Dictionary:
	if _querying:
		return R.fail("InvalidState","collision_query")
	var morale := {}
	for event in morale_events:
		if typeof(event) != TYPE_DICTIONARY or typeof(event.get("actor_handle")) != TYPE_DICTIONARY or not V.integer(event.get("delta"),-100,100):
			return R.fail("InvalidArgument","morale_event")
		var state := _actor(event.actor_handle,_actors)
		if state.is_empty():
			return R.fail("NotFound","morale_event")
		morale[state.handle.index] = clampi(morale.get(state.handle.index,0) + event.delta,-100,100)
	var flights := _shots.duplicate()
	var events := []
	var result := step(tick, intents, func(t, active): return Sweeps.collect(t,active,_sampling,poses,sweep,flights,events))
	if not result.ok:
		return result
	_shots = flights
	var downed := {}
	for hit: Dictionary in result.value.hits:
		var victim: Dictionary = _actors[hit.target.index]
		if hit.get("shield_broken",false):
			events.append({"type":"shield_broken", "actor_handle":victim.handle})
		if hit.damage <= 0:
			continue
		morale[victim.handle.index] = int(morale.get(victim.handle.index,0)) - mini(20,hit.damage)
		if victim.phase == "Downed" and not downed.has(victim.handle.index):
			downed[victim.handle.index] = true
			events.append({"type":"downed", "actor_handle":victim.handle})
			if victim.mount_handle != null or victim.rider_handle != null:
				var rider: Dictionary = victim.handle if victim.mount_handle != null else victim.rider_handle
				var horse: Dictionary = victim.handle if victim.rider_handle != null else victim.mount_handle
				_unlink(rider,horse,victim.rider_handle != null)
				events.append({"type":"dismounted","actor_handle":rider,"mount_handle":horse})
	_resolve_morale(tick, morale, downed, poses, events)
	result.value["events"] = events.duplicate(true)
	result.value["projectiles"] = flights.size()
	return result


func _change_morale(index: int, delta: int, events: Array) -> bool:
	var state: Dictionary = _actors[index]
	if state.phase == "Downed" or state.role == "mount":
		return false
	var value := clampi(state.morale + delta, 0, 100)
	var routing: bool = value <= 25 or (state.routing and value < 55)
	if state.morale == value and state.routing == routing:
		return false
	var changed: bool = state.routing != routing
	state = state.duplicate()
	state.morale = value
	state.routing = routing
	if changed:
		if routing:
			_enter(state,"Ready",_tick)
		events.append({"type":"routed" if routing else "regrouped", "actor_handle":state.handle, "morale":value})
	_actors[index] = state
	return changed and routing


func _resolve_morale(tick: int, morale: Dictionary, downed: Dictionary, poses: Dictionary, events: Array) -> void:
	if tick % 60 == 0:
		for state: Dictionary in _actors.values():
			if not state.routing and state.morale != 70:
				var index: int = state.handle.index
				morale[index] = morale.get(index,0) + signi(70-state.morale)
	var sources := {}
	var affected := morale.keys()
	affected.sort()
	for index in affected:
		if _change_morale(index,morale[index],events):
			sources[index] = true
	for index in _pending_spread:
		var state: Dictionary = _actors.get(index,{})
		if state.get("handle") == _pending_spread[index] and (state.routing or state.phase == "Downed"):
			sources[index] = true
	_pending_spread = {}
	sources.merge(downed)
	if sources.is_empty():
		return
	# Index allies once when a loss or routing transition actually occurs.
	var grid := {}
	var positions := {}
	for index in poses:
		var pose: Variant = poses[index]
		if not _actors.has(index) or typeof(pose) != TYPE_DICTIONARY or not Sweeps.vector(pose.get("position_mm"),1000000000):
			continue
		var pos := Sweeps.v3(pose.position_mm)
		positions[index] = pos
		var cell := Vector2i(floori(pos.x / NEIGHBOR_MM), floori(pos.z / NEIGHBOR_MM))
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(index)
	var ordered := sources.keys()
	ordered.sort()
	for index in ordered.slice(MAX_SOURCES):
		_pending_spread[index] = _actors[index].handle
	for index in ordered.slice(0, MAX_SOURCES):
		if not positions.has(index):
			continue
		var source: Dictionary = _actors[index]
		var pos: Vector3 = positions[index]
		var cell := Vector2i(floori(pos.x / NEIGHBOR_MM), floori(pos.z / NEIGHBOR_MM))
		var nearby := []
		for dx in range(-1,2):
			for dz in range(-1,2):
				nearby.append_array(grid.get(cell + Vector2i(dx,dz),[]))
		nearby.sort()
		var count := 0
		for other in nearby:
			var ally: Dictionary = _actors[other]
			if other == index or ally.team != source.team or ally.role == "mount" or ally.phase == "Downed" or tick-ally.last_spread < SPREAD_TICKS:
				continue
			if pos.distance_squared_to(positions[other]) > NEIGHBOR_MM*NEIGHBOR_MM:
				continue
			ally = ally.duplicate()
			ally.last_spread = tick
			_actors[other] = ally
			if _change_morale(other,-12 if source.commander else -6,events):
				_pending_spread[other] = ally.handle
			events.append({"type":"morale_spread","actor_handle":ally.handle,"source":source.handle})
			count += 1
			if count == MAX_NEIGHBORS:
				break
