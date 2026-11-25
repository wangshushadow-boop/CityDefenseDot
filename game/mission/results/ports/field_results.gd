extends RefCounted
## Consume the Mission's source bindings and the reports committed in its fixed tick.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const S = preload("res://contracts/schema.gd")
const C = preload("res://contracts/canonical.gd")
const Sources = preload("res://contracts/field_sources.gd")

var _scope := ""
var _spec: Dictionary
var _owners: RefCounted
var _sources: Array
var _last_tick := 0
var _facts := {}
# Retain only the source of each human generation for projectiles already in flight.
var _bindings := {}
var _action_rows: Variant
var _ending_rows: Array
var _entered: Array
var _decision: Variant
var _candidate := {}
var _final := {}

func open(initial: Dictionary) -> Dictionary:
	if not _scope.is_empty() or initial.get("phase") != "Deployment" or initial.get("tick") != 0:
		return R.fail("InvalidState","results.open")
	if typeof(initial.get("mission_id")) != TYPE_STRING or initial.mission_id.is_empty():
		return R.fail("InvalidArgument","mission_id")
	var index := Sources.build(initial.get("encounter_spec"))
	if not index.ok:
		return index
	var encounter: Dictionary = initial.encounter_spec
	if encounter.mode not in ["campaign","custom","multiplayer"] or encounter.siege_snapshot != null:
		return R.fail("InvalidArgument","field_results.mode")
	var total := 0
	var heroes := {}
	for source in encounter.reserved_sources:
		total += source.count
		if source.hero_id != null:
			if heroes.has(source.hero_id):
				return R.fail("Conflict","reserved_sources.hero_id")
			heroes[source.hero_id] = true
	if total > C.MAX_ITEMS:
		return R.fail("InvalidArgument","slot_outcomes.count")
	_scope = initial.mission_id
	_spec = encounter
	_owners = index.value
	_sources = encounter.reserved_sources.duplicate()
	_sources.sort_custom(func(a,b): return a.source_slot_range[0] < b.source_slot_range[0])
	return R.ok()

func _check_tick(context: Dictionary, batch: Dictionary) -> Dictionary:
	if _scope.is_empty() or _decision != null or not _final.is_empty():
		return R.fail("InvalidState","field_results")
	if context.get("mission_id") != _scope or batch.get("mission_id") != _scope:
		return R.fail("NotFound","mission_id")
	if context.get("tick") != _last_tick or batch.get("source_tick") != _last_tick + 1:
		return R.fail("StaleVersion","tick")
	return R.ok()

static func _key(handle: Variant) -> String:
	if not handle is Dictionary or not V.integer(handle.get("index"),0,V.MAX_U32) or not V.integer(handle.get("generation"),1,V.MAX_U32):
		return ""
	return "%d/%d" % [handle.index,handle.generation]

static func _live(rows: Array, handle: Dictionary) -> Dictionary:
	var i := rows.bsearch_custom(handle.index,func(row,index): return row.handle.index < index)
	if i < rows.size() and rows[i].handle == handle:
		return rows[i]
	return {}

func _edit(slot: int) -> Dictionary:
	if not _candidate.facts.has(slot):
		_candidate.facts[slot] = _facts.get(slot,{}).duplicate()
	return _candidate.facts[slot]

func observe_combat(context: Dictionary, batch: Dictionary, combat: Dictionary) -> Dictionary:
	var tick := _check_tick(context,batch)
	if not tick.ok:
		return tick
	if not _candidate.is_empty() or combat.get("tick") != batch.source_tick or not combat.get("hits") is Array or not combat.get("events") is Array:
		return R.fail("InvalidArgument","combat.report")
	var rows: Array = context.entities
	_candidate = {"action_rows":rows,"bindings":{},"facts":{},"ready":false}
	if not is_same(rows,_action_rows):
		for row in rows:
			if row.source_slot != null:
				var key := _key(row.handle)
				if not _bindings.has(key):
					_candidate.bindings[key] = row.source_slot
	var attackers := {}
	for hit in combat.hits:
		if not hit is Dictionary or _key(hit.get("target")).is_empty() or _key(hit.get("attacker")).is_empty() or not V.integer(hit.get("damage")) or not hit.get("blocked") is bool:
			return R.fail("InvalidArgument","combat.hit")
		var victim := _live(rows,hit.target)
		if victim.is_empty():
			return R.fail("NotFound","combat.target")
		if hit.blocked or hit.damage == 0 or victim.source_slot == null:
			continue
		var fact := _edit(victim.source_slot)
		fact["wounded"] = true
		var attacker_key := _key(hit.attacker)
		var shooter: Variant = _candidate.bindings.get(attacker_key,_bindings.get(attacker_key))
		var hostile_team: Variant = null
		if shooter != null:
			var owner: Dictionary = _owners.team_for_slot(shooter)
			if not owner.ok:
				return owner
			if not is_same(owner.value,victim.components.team_key):
				hostile_team = owner.value
				var credit := _edit(shooter)
				credit["xp"] = int(credit.get("xp",0)) + 1
		elif _live(rows,hit.attacker).is_empty():
			return R.fail("NotFound","combat.attacker")
		# COM applies simultaneous damage together. Mixed origins give no exclusive claim.
		var slot: int = victim.source_slot
		if not attackers.has(slot):
			attackers[slot] = hostile_team
		elif not is_same(attackers[slot],hostile_team):
			attackers[slot] = null
	for event in combat.events:
		if not event is Dictionary:
			return R.fail("InvalidArgument","combat.event")
		if event.get("type") != "downed":
			continue
		if _key(event.get("actor_handle")).is_empty():
			return R.fail("InvalidArgument","combat.actor_handle")
		var victim := _live(rows,event.actor_handle)
		if victim.is_empty():
			return R.fail("NotFound","combat.actor_handle")
		if victim.source_slot != null:
			var fact := _edit(victim.source_slot)
			fact["wounded"] = true
			fact["downed"] = true
			fact["attacker_team"] = attackers.get(victim.source_slot)
	return R.ok()

func stage_snapshot(context: Dictionary, batch: Dictionary, rule_report: Dictionary) -> Dictionary:
	var tick := _check_tick(context,batch)
	if not tick.ok:
		return tick
	if _candidate.is_empty() or _candidate.ready:
		return R.fail("InvalidState","results.snapshot")
	var matched := false
	for report in context.get("phase_reports",[]):
		if report.id == "field.rules" and report.phase == "objectives" and report.value == rule_report:
			matched = true
			break
	if not matched or not rule_report.get("slot_events") is Array or not rule_report.get("retire_handles") is Array or rule_report.slot_events.size() != rule_report.retire_handles.size():
		return R.fail("Conflict","results.field_rules")
	for i in rule_report.slot_events.size():
		var event: Dictionary = rule_report.slot_events[i]
		var row := _live(_candidate.action_rows,rule_report.retire_handles[i])
		if row.is_empty() or row.source_slot == null or row.source_slot != event.get("source_slot_id") or event.get("end_status") not in ["withdrawn","wounded"]:
			return R.fail("Conflict","results.retire_source")
		var fact := _edit(row.source_slot)
		if fact.has("exit"):
			return R.fail("Conflict","results.duplicate_exit")
		fact["exit"] = event.end_status
		if event.end_status == "wounded":
			fact["wounded"] = true
	_candidate["ending_rows"] = context.entities
	_candidate["entered"] = context.spawned_slots
	_candidate["decision"] = rule_report.outcome
	_candidate.ready = true
	return R.ok()

func commit() -> void:
	if _candidate.is_empty() or not _candidate.ready:
		return
	_bindings.merge(_candidate.bindings)
	_facts.merge(_candidate.facts,true)
	_action_rows = _candidate.action_rows
	_ending_rows = _candidate.ending_rows
	_entered = _candidate.entered
	_decision = _candidate.decision
	_last_tick += 1
	_candidate = {}

func rollback() -> void:
	_candidate = {}

func build_result(ending: Dictionary, outcome: Dictionary) -> Dictionary:
	if not _candidate.is_empty() or _decision == null or ending.get("phase") not in ["Ending","Finalizing"]:
		return R.fail("InvalidState","results.finalize")
	if ending.get("mission_id") != _scope or ending.get("encounter_spec") != _spec or ending.get("tick") != _last_tick or outcome != _decision or ending.get("entities") != _ending_rows or ending.get("spawned_slots") != _entered:
		return R.fail("Conflict","results.ending")
	if not _final.is_empty():
		return R.ok(_final)
	var deployed := {}
	var live := {}
	for slot in _entered:
		deployed[slot] = true
	for row in _ending_rows:
		if row.source_slot != null:
			live[row.source_slot] = true
	var totals := {}
	for side in _spec.sides:
		totals[side.team_key] = {"team_key":side.team_key,"reserved":0,"entered":0,"alive":0,"wounded":0,"dead":0,"captured":0,
			"withdrawn":0,"not_spawned":0,"wounded_total":0,"capture_candidates":0,"xp":0}
	var slots := []
	var heroes := []
	var claims := []
	var winners: Array = outcome.winner_team_keys
	var campaign: bool = _spec.mode == "campaign"
	for source in _sources:
		for slot in range(source.source_slot_range[0],source.source_slot_range[1]):
			var fact: Dictionary = _facts.get(slot,{})
			var wounded: bool = fact.get("wounded",false)
			var status := "not_spawned"
			var captor: Variant = null
			if deployed.has(slot):
				if not live.has(slot) and not fact.has("exit") and not fact.get("downed",false):
					return R.fail("Conflict","results.missing_terminal")
				status = fact.get("exit","wounded" if wounded else "alive")
				if fact.get("downed",false) and not fact.has("exit") and fact.get("attacker_team") in winners:
					captor = fact.attacker_team
			var row := {"source_slot_id":slot,"end_status":status,"wounded":wounded,"captor_team_key":captor,"xp":fact.get("xp",0)}
			slots.append(row)
			var team: Variant = _owners.team_for_slot(slot).value
			var count: Dictionary = totals[team]
			count.reserved += 1
			count.entered += int(deployed.has(slot))
			count[status] += 1
			count.wounded_total += int(wounded)
			count.capture_candidates += int(captor != null)
			count.xp += row.xp
			if source.hero_id != null:
				var hero := row.duplicate()
				hero["hero_id"] = source.hero_id
				heroes.append(hero)
			if campaign and captor != null:
				claims.append({"source_slot_id":slot,"loadout_snapshot_id":source.loadout_snapshot_id,"claimant_team_key":captor})
	var result := {"schema_version":1,"result_id":"result/"+_scope,"mission_id":_scope,"duration_ticks":_last_tick,
		"encounter_id":_spec.encounter_id if campaign else null,"reservation_revision":_spec.reservation_revision if campaign else null,
		"outcome":outcome.outcome,"winner_team_keys":winners,"objective_results":outcome.objective_results,"slot_outcomes":slots,
		"hero_outcomes":heroes,"loot_claims":claims,"reward_intents":[],"siege_changes":null,"stats":{"teams":totals.values()}}
	var digest := C.hash_value(result)
	if not digest.ok:
		return digest
	result["integrity_hash"] = digest.value
	var checked := S.validate_shape("MissionResult",result)
	if checked.ok:
		_final = checked.value
	return checked

## Use at a receipt boundary, including modes without a campaign encounter identity.
static func validate_source_coverage(spec: Dictionary, result: Dictionary) -> Dictionary:
	var sources := Sources.build(spec)
	if not sources.ok:
		return sources
	var checked := S.validate_shape("MissionResult",result)
	if not checked.ok:
		return checked
	var campaign: bool = spec.mode == "campaign"
	if result.encounter_id != (spec.encounter_id if campaign else null):
		return R.fail("Conflict","encounter_id")
	if result.reservation_revision != (spec.reservation_revision if campaign else null):
		return R.fail("StaleVersion","reservation_revision")
	var teams := {}
	for side in spec.sides:
		teams[side.team_key] = true
	var winners := {}
	for team in result.winner_team_keys:
		if not teams.has(team) or winners.has(team):
			return R.fail("Conflict","winner_team_keys")
		winners[team] = true
	var count := 0
	var heroes := {}
	for source in spec.reserved_sources:
		count += source.count
		if source.hero_id != null:
			if heroes.has(source.hero_id):
				return R.fail("Conflict","reserved_sources.hero_id")
			heroes[source.hero_id] = source.source_slot_range[0]
	if count != result.slot_outcomes.size():
		return R.fail("Conflict","slot_outcomes.count")
	var slots := {}
	for row in result.slot_outcomes:
		var owner: Dictionary = sources.value.team_for_slot(row.source_slot_id)
		if not owner.ok:
			return R.fail("Conflict","slot_outcomes.source_slot_id")
		if row.captor_team_key != null and (not row.wounded or row.end_status != "wounded" or is_same(row.captor_team_key,owner.value) or not winners.has(row.captor_team_key)):
			return R.fail("Conflict","slot_outcomes.captor_team_key")
		slots[row.source_slot_id] = row
	for hero in result.hero_outcomes:
		if not hero is Dictionary or not heroes.has(hero.get("hero_id")) or heroes[hero.hero_id] != hero.get("source_slot_id"):
			return R.fail("Conflict","hero_outcomes.hero_id")
		var row: Dictionary = slots[hero.source_slot_id]
		for field in row:
			if not hero.has(field) or not is_same(hero[field],row[field]):
				return R.fail("Conflict","hero_outcomes."+field)
		heroes.erase(hero.hero_id)
	if not heroes.is_empty():
		return R.fail("Conflict","hero_outcomes")
	return checked
