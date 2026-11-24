extends RefCounted
## Read-only rows from the current Mission tick. Only the composition root supplies
## these projections. Decision layers receive own state and observed enemy contacts.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const CELL := 12.0
const EXAMINED := 48
const MAX_RADIUS := 48.0
const MAX_CONTACTS := 12

var actors := {}
var teams := {}
var formations := {}
var urgent := {}
var _order: Array[Dictionary] = []
var _slots := {}
var _positions := PackedVector3Array()
var _camp := PackedInt32Array()
var _ids := PackedInt64Array()
var _cells: Array[Vector2i] = []
var _owned := {}
var _status := {}
var _grid := {}
var _by_observer := {}
var _by_team := {}
var _by_formation := {}
var _contacts := {}
var _sense_cache := {}
var _visibility := {}
var _cache_epoch := -1
var _threat_until := {}
var _formation_revisions := {}
var _team_scout := {}
var _formation_scout := {}
static var _offsets: Array[Vector2i] = []
var examined := 0
var rays := 0
var cache_hits := 0
var los_us := 0
var scouts := 0

func _init() -> void:
	if not _offsets.is_empty():
		return
	for x in range(-4,5):
		for z in range(-4,5):
			_offsets.append(Vector2i(x,z))
	_offsets.sort_custom(func(a,b):
		if a.length_squared() == b.length_squared():
			return a < b
		return a.length_squared() < b.length_squared())

static func handle_ok(h: Variant) -> bool:
	return typeof(h) == TYPE_DICTIONARY and h.size() == 2 and V.integer(h.get("index"),0,V.MAX_U32) and V.integer(h.get("generation"),1,V.MAX_U32)

static func cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x/CELL),floori(p.z/CELL))

func build(units: Array) -> Dictionary:
	var camps := {}
	for u in units:
		if typeof(u) != TYPE_DICTIONARY or not handle_ok(u.get("handle")) or not V.integer(u.get("formation_id"),0,V.MAX_U32):
			return R.fail("InvalidArgument","ai_unit")
		var team: Variant = u.get("team_key")
		if not (V.integer(team,0,V.MAX_U32) or (typeof(team) == TYPE_STRING and not team.is_empty())):
			return R.fail("InvalidArgument","team_key")
		if typeof(u.get("position")) != TYPE_VECTOR3 or not u.position.is_finite() or typeof(u.get("role")) != TYPE_STRING or u.role.is_empty():
			return R.fail("InvalidArgument","ai_pose")
		if not V.integer(u.get("control_revision")) or not V.integer(u.get("order_revision")) or typeof(u.get("urgent",false)) != TYPE_BOOL:
			return R.fail("InvalidArgument","ai_revision")
		var id: int = u.handle.index
		var group: int = u.formation_id
		if actors.has(id):
			return R.fail("Conflict","actor_index")
		if formations.has(group):
			var leader: Dictionary = formations[group][0]
			if leader.team_key != team or leader.control_revision != u.control_revision or leader.order_revision != u.order_revision:
				return R.fail("Conflict","formation_state")
		var handle: Dictionary = u.handle.duplicate()
		handle.make_read_only()
		var own := {"handle":handle,"team_key":team,"formation_id":group,"role":u.role,
			"control_revision":u.control_revision,"order_revision":u.order_revision}
		for field in ["hp","morale","ammo"]:
			if u.has(field):
				if not V.integer(u[field]):
					return R.fail("InvalidArgument",field)
				own[field] = u[field]
		own.make_read_only()
		actors[id] = own
		if u.get("urgent",false):
			urgent[id] = handle
		_slots[id] = _order.size()
		_order.append(own)
		_positions.append(u.position)
		if not camps.has(team):
			camps[team] = camps.size()
		_camp.append(camps[team])
		_ids.append(id)
		if not teams.has(team):
			teams[team] = []
		if not formations.has(group):
			formations[group] = []
			if not _formation_revisions.has(team):
				_formation_revisions[team] = {}
			var pair := [u.control_revision,u.order_revision]
			pair.make_read_only()
			_formation_revisions[team][group] = pair
		teams[team].append(own)
		formations[group].append(own)
		var bucket := cell(u.position)
		_cells.append(bucket)
		if not _grid.has(bucket):
			_grid[bucket] = []
		_grid[bucket].append(_slots[id])
	for rows: Array in teams.values():
		rows.make_read_only()
	for rows: Array in formations.values():
		rows.make_read_only()
	for revisions: Dictionary in _formation_revisions.values():
		revisions.make_read_only()
	return R.ok()

func advance(tick: int, epoch: int, changed_nav: bool, points: PackedVector3Array, events: Array, changes: Array) -> Dictionary:
	if points.size() != _order.size():
		return R.fail("InvalidArgument","roster_positions")
	for p in points:
		if not p.is_finite():
			return R.fail("InvalidArgument","roster_position")
	var signals := {}
	for h in events:
		if not handle_ok(h) or not actors.has(h.index) or actors[h.index].handle!=h:
			return R.fail("NotFound","urgent_handle")
		signals[h.index] = actors[h.index].handle
	var updates := {}
	for change in changes:
		if typeof(change)!=TYPE_DICTIONARY or not handle_ok(change.get("handle")) or not actors.has(change.handle.index) or actors[change.handle.index].handle!=change.handle:
			return R.fail("NotFound","state_handle")
		var patch: Dictionary = _status.get(change.handle.index,{}).duplicate()
		for key in change:
			if key == "handle":
				continue
			if key not in ["hp","ammo","morale"] or not V.integer(change[key]):
				return R.fail("InvalidArgument","state_change")
			patch[key] = change[key]
		if updates.has(change.handle.index):
			return R.fail("Conflict","state_handle")
		updates[change.handle.index] = patch
	for i in points.size():
		var next := cell(points[i])
		var old := _cells[i]
		if next != old:
			_grid[old].erase(i)
			if _grid[old].is_empty():
				_grid.erase(old)
			if not _grid.has(next):
				_grid[next] = []
			_grid[next].append(i)
			_cells[i] = next
	_positions = points.duplicate()
	_status.merge(updates,true)
	urgent = signals
	_owned.clear()
	_contacts.clear()
	_sense_cache.clear()
	_by_observer.clear()
	_by_formation.clear()
	_by_team.clear()
	if epoch < 0 or epoch != _cache_epoch or changed_nav:
		_visibility.clear()
		_threat_until.clear()
	_cache_epoch = epoch
	examined = 0
	rays = 0
	cache_hits = 0
	los_us = 0
	scouts = 0
	return R.ok()

func team_revisions(team: Variant) -> Dictionary:
	return _formation_revisions[team]

func next_scout(subject: Variant, team: bool) -> Dictionary:
	var members: Array = (teams if team else formations)[subject]
	var cursors: Dictionary = _team_scout if team else _formation_scout
	var i: int = cursors.get(subject,0)
	cursors[subject] = (i+1)%members.size()
	scouts += 1
	return members[i].handle

func threatened(group: int, tick: int) -> bool:
	return _threat_until.get(group,-1) >= tick

func high_priority(id: int, tick: int) -> bool:
	var member: Dictionary = actors[id]
	return threatened(member.formation_id,tick) and _status.get(id,member).get("hp",member.get("hp",100)) <= 35

func _own(row: Dictionary) -> Dictionary:
	var id: int = row.handle.index
	if not _owned.has(id):
		var view := row.duplicate()
		view.position = _positions[_slots[id]]
		view.urgent = urgent.has(id)
		if _status.has(id):
			view.merge(_status[id],true)
		view.make_read_only()
		_owned[id] = view
	return _owned[id]

func resolve(h: Dictionary) -> Dictionary:
	var row: Dictionary = actors.get(h.get("index"),{})
	if not handle_ok(h) or row.is_empty() or row.handle.generation != h.generation:
		return R.fail("NotFound","actor_handle")
	return R.ok(_own(row))

func _contact(own: Dictionary) -> Dictionary:
	var id: int = own.handle.index
	if not _contacts.has(id):
		var public_row := {"handle":own.handle,"team_key":own.team_key,"formation_id":own.formation_id,
			"role":own.role,"position":_positions[_slots[id]]}
		public_row.make_read_only()
		_contacts[id] = public_row
	return _contacts[id]

func seen_by(actor: int, enemy: Dictionary) -> bool:
	return handle_ok(enemy) and _by_observer.get(actor,{}).get(enemy.index) == enemy

func group_view(subject: Variant, team_view: bool, stamp: Dictionary) -> Dictionary:
	var members: Array = (teams if team_view else formations).get(subject,[])
	if members.is_empty():
		return R.fail("NotFound","ai_subject")
	var own := []
	for row in members:
		own.append(_own(row))
	own.make_read_only()
	var enemies := Dictionary((_by_team if team_view else _by_formation).get(subject,{})).values()
	enemies.make_read_only()
	var result := {"own_units":own,"visible_enemies":enemies,"stamp":stamp}
	result.make_read_only()
	return R.ok(result)

func sense(me: Dictionary, radius: float, limit: int, stamp: Dictionary, visible: Callable) -> Dictionary:
	if not is_finite(radius) or radius <= 0 or radius > MAX_RADIUS or limit < 1 or limit > MAX_CONTACTS:
		return R.fail("InvalidArgument","perception_range")
	var id: int = me.handle.index
	var prior: Variant = _sense_cache.get(id)
	if prior != null and prior.radius == radius and prior.limit == limit:
		cache_hits += 1
		return R.ok(prior.view)
	var self_slot: int = _slots[id]
	var own_camp := _camp[self_slot]
	var position := _positions[self_slot]
	var near := _cells[self_slot]
	var reach := ceili(radius/CELL)
	var radius_squared := radius*radius
	var ally_slots: Array[int] = []
	var ally_distances := PackedFloat64Array()
	var opponents: Array[int] = []
	var opponent_distances := PackedFloat64Array()
	var scanned := 0
	for offset in _offsets:
		if absi(offset.x)>reach or absi(offset.y)>reach:
			continue
		var bucket: Variant = _grid.get(near+offset)
		if bucket == null:
			continue
		var size: int = bucket.size()
		# Rotate dense buckets and reserve candidates for neighbouring cells.
		var first: int = (stamp.tick+id) % size if size > 16 else 0
		for n in mini(mini(size,16),EXAMINED-scanned):
			var index: int = bucket[(first+n)%size]
			scanned += 1
			var d := position.distance_squared_to(_positions[index])
			if index == self_slot or d > radius_squared:
				continue
			var friendly := _camp[index] == own_camp
			var list: Array[int] = ally_slots if friendly else opponents
			var distances: PackedFloat64Array = ally_distances if friendly else opponent_distances
			var bound := limit if friendly else 2*limit
			if list.size() == bound and d > distances[-1]:
				continue
			var slot := distances.bsearch(d)
			while slot < list.size() and distances[slot]==d and _ids[list[slot]] < _ids[index]:
				slot += 1
			if slot == bound:
				continue
			if list.size() == bound:
				list.pop_back()
				distances.resize(bound-1)
			list.insert(slot,index)
			distances.insert(slot,d)
		if scanned >= EXAMINED:
			break
	examined += scanned
	var enemies := []
	var allies := []
	for index in ally_slots:
		allies.append(_contact(_order[index]))
	var pairs: Dictionary = _visibility.get_or_add(id,{})
	for index in opponents:
		var other: Dictionary = _order[index]
		var target_id := _ids[index]
		var target := _positions[index]
		var pair: Variant = pairs.get(target_id)
		var clear := false
		if pair != null and stamp.tick-pair.tick <= 12 and pair.a==position and pair.b==target:
			cache_hits += 1
			clear = pair.clear
		else:
			rays += 1
			var start := Time.get_ticks_usec()
			var outcome: Variant = visible.call(position,target)
			los_us += Time.get_ticks_usec()-start
			clear = typeof(outcome)==TYPE_BOOL and outcome
			if pairs.size() >= 2*MAX_CONTACTS and pair == null:
				pairs.clear()
			pairs[target_id] = {"a":position,"b":target,"clear":clear,"tick":stamp.tick}
		if clear:
			var public_row := _contact(other)
			enemies.append(public_row)
			_by_observer.get_or_add(id,{})[target_id] = other.handle
			_by_team.get_or_add(me.team_key,{})[target_id] = public_row
			_by_formation.get_or_add(me.formation_id,{})[target_id] = public_row
			_threat_until[me.formation_id] = stamp.tick+12
			if enemies.size() == limit:
				break
	allies.make_read_only()
	enemies.make_read_only()
	var result := {"self":me,"nearby_allies":allies,"visible_enemies":enemies,"stamp":stamp}
	result.make_read_only()
	_sense_cache[id] = {"radius":radius,"limit":limit,"view":result}
	return R.ok(result)
