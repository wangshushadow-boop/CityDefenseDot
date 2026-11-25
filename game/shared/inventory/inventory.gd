extends RefCounted
## Campaign inventory authority. APP calls commit at its single-writer safe point.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const C = preload("res://contracts/canonical.gd")
const HISTORY_PAGE_SIZE := 256

var _locations := {}
var _initial: Array = []
var _state := {"counts": {}, "owners": {}, "reservations": {}, "held": {}, "used": {},
	"ledger": [], "applied": {}, "revision": 0}
var _authorize: Callable
var _ready := false
var _busy := false


static func _id(value: Variant) -> bool:
	return C.Reader.valid_key(value)


static func _resource_key(resource: Variant) -> String:
	if typeof(resource) != TYPE_DICTIONARY:
		return ""
	match resource.get("kind"):
		"currency":
			if resource.size() == 2 and V.def_id(resource.get("id")):
				return "currency:" + resource.id
		"instance":
			if resource.size() == 2 and _id(resource.get("id")):
				return "instance:" + resource.id
		"stock":
			if resource.size() == 4 and V.def_id(resource.get("def_id")) and V.integer(resource.get("quality")) and resource.has("modifier_id"):
				if resource.modifier_id == null or V.def_id(resource.modifier_id):
					return "stock:%s|%d|%s" % [resource.def_id, resource.quality, str(resource.modifier_id)]
	return ""


func _accepts(holder: Variant, resource: Dictionary) -> bool:
	if not _id(holder) or not _locations.has(holder):
		return false
	var location: Dictionary = _locations[holder]
	match location.kind:
		"account": return resource.kind == "currency" and resource.id == location.currency
		"slot": return resource.kind == "instance"
	return resource.kind != "currency"


func initialize(locations: Dictionary, initial: Array, authorize: Callable = Callable()) -> Dictionary:
	if _busy or _ready:
		return R.fail("InvalidState", "initialize")
	var candidate = get_script().new()
	var content := C.encode([locations, initial])
	if not content.ok or locations.is_empty():
		return R.fail("InvalidArgument", "locations")
	for id in locations:
		var spec: Variant = locations[id]
		if not _id(id) or typeof(spec) != TYPE_DICTIONARY:
			return R.fail("InvalidArgument", "location")
		match spec.get("kind"):
			"account":
				if spec.size() != 2 or not V.def_id(spec.get("currency")):
					return R.fail("InvalidArgument", "currency")
			"inventory":
				if spec.size() != 2 or not V.integer(spec.get("capacity")):
					return R.fail("InvalidArgument", "capacity")
			"slot":
				if spec.size() != 1:
					return R.fail("InvalidArgument", "slot")
			_: return R.fail("InvalidArgument", "location.kind")
	candidate._locations = locations.duplicate(true)
	var writes := _writes()
	for row in initial:
		if typeof(row) != TYPE_DICTIONARY or row.size() != 3 or not row.has_all(["holder", "resource", "amount"]):
			return R.fail("InvalidArgument", "initial")
		var key := _resource_key(row.resource)
		if key.is_empty() or not V.integer(row.amount, 1) or not candidate._accepts(row.holder, row.resource):
			return R.fail("InvalidArgument", "initial")
		var checked: Dictionary = candidate._move(writes, null, row.holder, row.resource, key, row.amount)
		if not checked.ok:
			return checked
	var valid: Dictionary = candidate._check_totals(writes)
	if not valid.ok:
		return valid
	_apply_values(candidate._state, writes)
	_locations = candidate._locations
	_state = candidate._state
	_initial = initial.duplicate(true)
	_authorize = authorize
	_ready = true
	return R.ok()


func balance(account: String) -> Dictionary:
	if _locations.get(account, {}).get("kind") != "account":
		return R.fail("NotFound", "account")
	var key: String = "currency:" + _locations[account].currency
	return R.ok(_state.counts.get(account, {}).get(key, 0))


func available(holder: String, resource: Dictionary) -> Dictionary:
	var key := _resource_key(resource)
	if key.is_empty() or not _accepts(holder, resource):
		return R.fail("InvalidArgument", "resource_ref")
	return R.ok(_state.counts.get(holder, {}).get(key, 0) - _state.held.get(holder, {}).get(key, 0))


func owner_of(instance_id: String) -> Dictionary:
	if not _state.owners.has(instance_id):
		return R.fail("NotFound", "instance_id")
	return R.ok(_state.owners[instance_id])


## Isolated projection for cross-repository checks; no balances or ledger history are exposed.
func instance_layout() -> Dictionary:
	return {"locations": _locations.duplicate(true), "owners": _state.owners.duplicate()}


## Used during migration to distinguish issued holders from an older user-defined name.
func has_holder_endowment(holder_prefix: String) -> bool:
	for holder in _locations:
		if not holder.begins_with(holder_prefix):
			continue
		for record in _state.ledger:
			for line in record.request.lines:
				if line.get("reason") == "holder_endowment" and line.get("src") == null and line.get("dst") is String and line.dst.begins_with(holder_prefix) and line.get("source_ref") == record.request.txn_id:
					return true
		return false
	return false


## Campaign creates holders and their starting instances at one durable world commit.
## Endowments only enter newly opened holders and use one recorded issuance transaction.
func fork_with_locations(additions: Dictionary = {}, endowment: Array = [], txn_id: String = "") -> Dictionary:
	if _busy or (not _ready and additions.is_empty()):
		return R.fail("InvalidState", "inventory")
	if _locations.size() + additions.size() > C.MAX_ITEMS:
		return R.fail("InvalidState", "locations")
	for id in additions:
		if _locations.has(id):
			return R.fail("Conflict", "location")
	var candidate = get_script().new()
	if not additions.is_empty():
		var opened: Dictionary = candidate.initialize(additions, [], _authorize)
		if not opened.ok:
			return opened
	if _ready:
		candidate._locations.merge(_locations.duplicate(true))
		candidate._initial = _initial.duplicate(true)
		candidate._state = _state.duplicate(true)
		candidate._authorize = _authorize
		candidate._ready = true
	if not endowment.is_empty():
		if not _id(txn_id) or _state.applied.has(txn_id):
			return R.fail("Conflict", "endowment.txn_id")
		var lines := []
		var issued := {}
		for row in endowment:
			if not row is Dictionary or row.size() != 2 or not additions.has(row.get("holder")) or not _id(row.get("instance_id")):
				return R.fail("InvalidArgument", "endowment")
			lines.append({"src":null, "dst":row.holder, "resource":{"kind":"instance","id":row.instance_id},
				"amount":1, "reason":"holder_endowment", "source_ref":txn_id})
			issued[row.instance_id] = true
		# A consumed instance has no live owner, but its identity still belongs to the ledger.
		for row in _initial:
			if row.resource.kind == "instance" and issued.has(row.resource.id):
				return R.fail("Conflict", "instance.origin")
		for record in _state.ledger:
			for entry in record.entries:
				if entry.get("resource",{}).get("kind") == "instance" and issued.has(entry.resource.id):
					return R.fail("Conflict", "instance.origin")
		candidate._authorize = func(reason, source, _resource, mint): return mint and reason == "holder_endowment" and source == txn_id
		var plan: Dictionary = candidate.prepare_exchange(txn_id, lines)
		if not plan.ok:
			return plan
		var committed: Dictionary = candidate.commit(plan.value)
		if not committed.ok:
			return committed
		candidate._authorize = _authorize
	return R.ok(candidate)


func ledger_for(txn_id: String) -> Dictionary:
	if not _state.applied.has(txn_id):
		return R.fail("NotFound", "txn_id")
	var index: int = _state.applied[txn_id].receipt.committed_revision - 1
	return R.ok(_state.ledger[index].entries.duplicate(true))


func prepare_exchange(txn_id: String, lines: Array, expected_revision: Variant = -1) -> Dictionary:
	if _busy or not _ready:
		return R.fail("InvalidState", "prepare")
	_busy = true
	var request := {"txn_id": txn_id, "lines": lines, "expected_revision": expected_revision}
	var checked := _evaluate(request)
	_busy = false
	if not checked.ok:
		return checked
	return R.ok({"base_revision": _state.revision, "request": request.duplicate(true)})


func prepare_transfer(txn_id: String, src: String, dst: String, resource: Dictionary, qty: Variant,
		reason: String, source_ref: String, expected_revision: Variant = -1) -> Dictionary:
	if not V.integer(qty, 1):
		return R.fail("InvalidArgument", "amount")
	return prepare_exchange(txn_id, [{"src": src, "dst": dst, "resource": resource, "amount": qty,
		"reason": reason, "source_ref": source_ref}], expected_revision)


func mint_or_burn(txn_id: String, holder: String, resource: Dictionary, qty: Variant, is_mint: Variant,
		reason: String, source_id: String) -> Dictionary:
	if not V.integer(qty, 1) or typeof(is_mint) != TYPE_BOOL:
		return R.fail("InvalidArgument", "mint_or_burn")
	return prepare_exchange(txn_id, [{"src": null if is_mint else holder, "dst": holder if is_mint else null,
		"resource": resource, "amount": qty, "reason": reason, "source_ref": source_id}])


func reserve(txn_id: String, reservation_id: String, holder: String, resource: Dictionary, qty: Variant,
		owner: String, expiry: Variant = null) -> Dictionary:
	if not V.integer(qty, 1):
		return R.fail("InvalidArgument", "amount")
	return prepare_exchange(txn_id, [{"op": "reserve", "reservation_id": reservation_id, "holder": holder,
		"resource": resource, "amount": qty, "owner": owner, "expiry": expiry}])


func release(txn_id: String, reservation_id: String, owner: String) -> Dictionary:
	return prepare_exchange(txn_id, [{"op": "release", "reservation_id": reservation_id, "owner": owner}])


static func _writes() -> Dictionary:
	return {"counts": {}, "held": {}, "used": {}, "owners": {}, "reservations": {}, "entries": []}


# Only touched balances get an entry. Negative intermediate balances are checked after netting all legs.
func _add(writes: Dictionary, bucket: String, holder: String, key: String, amount: int) -> bool:
	if not writes[bucket].has(holder):
		writes[bucket][holder] = {}
	var row: Dictionary = writes[bucket][holder]
	var current: int = row.get(key, _state[bucket].get(holder, {}).get(key, 0))
	var value := current + amount
	row[key] = value
	return V.integer(value, -V.MAX_INTEGER)


func _leg(writes: Dictionary, holder: String, key: String, amount: int) -> bool:
	var used: int = writes.used.get(holder, _state.used.get(holder, 0)) + amount
	writes.used[holder] = used
	return V.integer(used, -V.MAX_INTEGER) and _add(writes, "counts", holder, key, amount)


func _move(writes: Dictionary, src: Variant, dst: Variant, resource: Dictionary, key: String, amount: int) -> Dictionary:
	if resource.kind == "instance":
		var id: String = resource.id
		if amount != 1 or writes.owners.has(id) or _state.owners.get(id) != src:
			return R.fail("Conflict", "instance.owner")
		writes.owners[id] = dst
	if src != null and not _leg(writes, src, key, -amount):
		return R.fail("InvalidArgument", "amount.overflow")
	if dst != null and not _leg(writes, dst, key, amount):
		return R.fail("InvalidArgument", "amount.overflow")
	return R.ok()


func _reservation(writes: Dictionary, line: Dictionary) -> Dictionary:
	var id: Variant = line.get("reservation_id")
	if not _id(id) or not _id(line.get("owner")):
		return R.fail("InvalidArgument", "reservation")
	var previous: Variant = writes.reservations.get(id, _state.reservations.get(id))
	if line.op == "release":
		if line.size() != 3:
			return R.fail("InvalidArgument", "release")
		if previous == null:
			return R.fail("NotFound", "reservation_id")
		if previous.owner != line.owner:
			return R.fail("Unauthorized", "owner")
		writes.reservations[id] = null
		_add(writes, "held", previous.holder, _resource_key(previous.resource), -previous.amount)
		return R.ok()
	if previous != null:
		return R.fail("Conflict", "reservation_id")
	if line.size() != 7 or not line.has_all(["resource", "holder", "amount", "expiry"]):
		return R.fail("InvalidArgument", "reserve")
	var key := _resource_key(line.resource)
	if key.is_empty() or not _accepts(line.holder, line.resource) or not V.integer(line.amount, 1):
		return R.fail("InvalidArgument", "reserve")
	if line.expiry != null and not V.integer(line.expiry):
		return R.fail("InvalidArgument", "expiry")
	writes.reservations[id] = line
	if not _add(writes, "held", line.holder, key, line.amount):
		return R.fail("InvalidArgument", "amount.overflow")
	return R.ok()


func _line(writes: Dictionary, line: Variant, txn_id: String, index: int, historical: bool) -> Dictionary:
	if typeof(line) != TYPE_DICTIONARY:
		return R.fail("InvalidArgument", "line")
	if line.get("op") in ["reserve", "release"]:
		return _reservation(writes, line)
	if line.size() != 6 or not line.has_all(["src", "dst", "resource", "amount", "reason", "source_ref"]):
		return R.fail("InvalidArgument", "line")
	var key := _resource_key(line.resource)
	if key.is_empty() or not V.integer(line.amount, 1) or not _id(line.reason) or not _id(line.source_ref):
		return R.fail("InvalidArgument", "line")
	if line.src == line.dst:
		return R.fail("InvalidArgument", "holder")
	for holder in [line.src, line.dst]:
		if holder != null and not _accepts(holder, line.resource):
			return R.fail("InvalidArgument", "holder")
	if (line.src == null or line.dst == null) and not historical:
		if not _authorize.is_valid():
			return R.fail("Unauthorized", "reason")
		var grant: Variant = _authorize.call(line.reason, line.source_ref, line.resource.duplicate(true), line.src == null)
		if typeof(grant) != TYPE_BOOL or not grant:
			return R.fail("Unauthorized", "reason")
	var moved := _move(writes, line.src, line.dst, line.resource, key, line.amount)
	if moved.ok:
		var entry: Dictionary = line.duplicate(true)
		entry["txn_id"] = txn_id
		entry["line_id"] = index
		writes.entries.append(entry)
	return moved


static func _within_map_limit(current: Dictionary, updates: Dictionary, erase_zero: bool = false) -> bool:
	if current.size() + updates.size() <= C.MAX_ITEMS:
		return true
	var count := current.size()
	for key in updates:
		var exists_after: bool = updates[key] != null and (not erase_zero or updates[key] != 0)
		count += int(exists_after) - int(current.has(key))
	return count <= C.MAX_ITEMS


func _check_totals(writes: Dictionary) -> Dictionary:
	for bucket in ["owners", "reservations"]:
		if not _within_map_limit(_state[bucket], writes[bucket]):
			return R.fail("InvalidState", "snapshot." + bucket)
	for holder in writes.used:
		var location: Dictionary = _locations[holder]
		var limit: int = 1 if location.kind == "slot" else location.get("capacity", V.MAX_INTEGER)
		if writes.used[holder] > limit:
			return R.fail("Conflict" if location.kind == "slot" else "InsufficientResource", "capacity")
	for bucket in ["counts", "held"]:
		for holder in writes[bucket]:
			if not _within_map_limit(_state[bucket].get(holder, {}), writes[bucket][holder], true):
				return R.fail("InvalidState", "snapshot." + bucket)
			for key in writes[bucket][holder]:
				var total: int = writes.counts.get(holder, {}).get(key, _state.counts.get(holder, {}).get(key, 0))
				var held: int = writes.held.get(holder, {}).get(key, _state.held.get(holder, {}).get(key, 0))
				if total < held or held < 0:
					return R.fail("InsufficientResource", "available")
	return R.ok()


func _evaluate(request: Dictionary, historical: bool = false, base_revision: int = -1) -> Dictionary:
	if request.size() != 3 or not _id(request.get("txn_id")) or not C.is_json_array(request.get("lines")) or request.lines.is_empty() or not V.integer(request.get("expected_revision"), -1):
		return R.fail("InvalidArgument", "request")
	var digest := C.hash_value(request)
	if not digest.ok:
		return digest
	request = request.duplicate(true)
	var existing: Variant = _state.applied.get(request.txn_id)
	if existing != null:
		if digest.value != existing.digest:
			return R.fail("Conflict", "txn_id")
		return R.ok({"replay": existing.receipt})
	if base_revision != -1 and base_revision != _state.revision:
		return R.fail("StaleVersion", "base_revision")
	if request.expected_revision != -1 and request.expected_revision != _state.revision:
		return R.fail("StaleVersion", "expected_revision")
	if _state.revision >= V.MAX_INTEGER:
		return R.fail("InvalidState", "revision")
	var writes := _writes()
	for i in request.lines.size():
		var checked := _line(writes, request.lines[i], request.txn_id, i, historical)
		if not checked.ok:
			return checked
	var valid := _check_totals(writes)
	if not valid.ok:
		return valid
	var receipt := {"txn_id": request.txn_id, "committed_revision": _state.revision + 1}
	return R.ok({"writes": writes, "record": {"request": request, "entries": writes.entries},
		"fact": {"digest": digest.value, "receipt": receipt}})


static func _apply_values(state: Dictionary, writes: Dictionary) -> void:
	for bucket in ["counts", "held"]:
		for holder in writes[bucket]:
			var row: Dictionary = state[bucket].get(holder, {})
			for key in writes[bucket][holder]:
				var value: int = writes[bucket][holder][key]
				if value == 0:
					row.erase(key)
				else:
					row[key] = value
			if row.is_empty():
				state[bucket].erase(holder)
			else:
				state[bucket][holder] = row
	for bucket in ["used", "owners", "reservations"]:
		for key in writes[bucket]:
			var value: Variant = writes[bucket][key]
			if value == null or (bucket == "used" and value == 0):
				state[bucket].erase(key)
			else:
				state[bucket][key] = value


static func _publish(state: Dictionary, change: Dictionary) -> void:
	_apply_values(state, change.writes)
	state.revision = change.fact.receipt.committed_revision
	state.applied[change.fact.receipt.txn_id] = change.fact
	state.ledger.append(change.record)


## The durable callback persists its isolated candidate and receipt in APP's transaction.
## A failed callback, or dropping a prepared plan, leaves every live fact untouched.
func commit(plan: Dictionary, durable: Callable = Callable()) -> Dictionary:
	if _busy or not _ready:
		return R.fail("InvalidState", "commit")
	if plan.size() != 2 or not V.integer(plan.get("base_revision")) or typeof(plan.get("request")) != TYPE_DICTIONARY:
		return R.fail("InvalidArgument", "plan")
	_busy = true
	var checked := _commit(plan, durable)
	_busy = false
	return checked


func _commit(plan: Dictionary, durable: Callable) -> Dictionary:
	# Validate before copying to reject noncanonical/cyclic data.
	var checked := _evaluate(plan.request, false, plan.base_revision)
	if not checked.ok:
		return checked
	var change: Dictionary = checked.value
	if change.has("replay"):
		return R.ok(change.replay.duplicate(true))
	change = change.duplicate(true)
	if durable != Callable():
		if not durable.is_valid():
			return R.fail("Unavailable", "durable")
		var candidate_state := _state.duplicate(true)
		_publish(candidate_state, change.duplicate(true))
		var candidate := _export(candidate_state)
		var ack: Variant = durable.call(candidate, change.fact.receipt.duplicate(true))
		if typeof(ack) != TYPE_DICTIONARY or typeof(ack.get("ok")) != TYPE_BOOL:
			return R.fail("Unavailable", "durable")
		if not ack.ok:
			return ack if typeof(ack.get("error")) == TYPE_DICTIONARY else R.fail("Unavailable", "durable")
	_publish(_state, change)
	return R.ok(change.fact.receipt.duplicate(true))


func snapshot() -> Dictionary:
	return _export(_state.duplicate(true))


# The in-memory ID index stays flat. Only an isolated save projection is packed.
func _export(state: Dictionary, keep_legacy_flat: bool = false) -> Dictionary:
	if state.ledger.size() > HISTORY_PAGE_SIZE and not keep_legacy_flat:
		var pages := []
		for first in range(0, state.ledger.size(), HISTORY_PAGE_SIZE):
			var records: Array = state.ledger.slice(first, first + HISTORY_PAGE_SIZE)
			var facts := {}
			for record in records:
				var id: String = record.request.txn_id
				facts[id] = state.applied[id]
			pages.append({"ledger": records, "applied": facts})
		# Bound the page directory too when an archive outgrows one canonical array.
		while pages.size() > C.MAX_ITEMS:
			var groups := []
			for first in range(0, pages.size(), C.MAX_ITEMS):
				groups.append(pages.slice(first, first + C.MAX_ITEMS))
			pages = groups
		state.erase("ledger")
		state.erase("applied")
		state["history_pages"] = pages
	return {"schema_version": 1, "locations": _locations.duplicate(true), "initial": _initial.duplicate(true),
		"state": state}


func _replay_records(records: Array) -> Dictionary:
	for record in records:
		if typeof(record) != TYPE_DICTIONARY or typeof(record.get("request")) != TYPE_DICTIONARY:
			return R.fail("InvalidArgument", "ledger")
		var checked := _evaluate(record.request, true)
		if not checked.ok:
			return checked
		if checked.value.has("replay"):
			return R.fail("Conflict", "ledger")
		_publish(_state, checked.value)
	return R.ok()


func _replay_pages(pages: Array) -> Dictionary:
	if pages.is_empty():
		return R.fail("InvalidArgument", "history_pages")
	for page in pages:
		var replayed: Dictionary
		if C.is_json_array(page):
			replayed = _replay_pages(page)
		elif typeof(page) == TYPE_DICTIONARY and C.is_json_array(page.get("ledger")) and page.ledger.size() <= HISTORY_PAGE_SIZE and typeof(page.get("applied")) == TYPE_DICTIONARY:
			replayed = _replay_records(page.ledger)
		else:
			return R.fail("InvalidArgument", "history_pages")
		if not replayed.ok:
			return replayed
	return R.ok()


## Restore is a trusted load path. PERSIST checks the container and replay verifies derived facts.
func restore(saved: Dictionary, authorize: Callable = Callable()) -> Dictionary:
	if _busy:
		return R.fail("InvalidState", "restore")
	if not V.integer(saved.get("schema_version"), 1, 1):
		return R.fail("StaleVersion", "schema_version")
	if not C.encode(saved).ok or typeof(saved.get("locations")) != TYPE_DICTIONARY or not C.is_json_array(saved.get("initial")) or typeof(saved.get("state")) != TYPE_DICTIONARY:
		return R.fail("InvalidArgument", "snapshot")
	var rebuilt = get_script().new()
	var checked: Dictionary = rebuilt.initialize(saved.locations, saved.initial,
		_authorize if authorize == Callable() else authorize)
	if not checked.ok:
		return checked
	var flat: bool = not saved.state.has("history_pages")
	if flat and C.is_json_array(saved.state.get("ledger")):
		checked = rebuilt._replay_records(saved.state.ledger)
	elif not flat and C.is_json_array(saved.state.history_pages):
		checked = rebuilt._replay_pages(saved.state.history_pages)
	else:
		return R.fail("InvalidArgument", "history")
	if not checked.ok:
		return checked
	if rebuilt._export(rebuilt._state.duplicate(true), flat) != saved:
		return R.fail("Conflict", "snapshot")
	_locations = rebuilt._locations
	_initial = rebuilt._initial
	_state = rebuilt._state
	_authorize = rebuilt._authorize
	_ready = true
	return R.ok()
