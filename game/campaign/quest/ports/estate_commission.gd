extends RefCounted
## An estate commission retains the first committed ledger of its term.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const C = preload("res://contracts/canonical.gd")
const Governance = preload("res://campaign/settlement/ports/governance.gd")
const TERM_DAYS := 3
const ACTOR_LOST := "承办人已离任或身故。"
const ISSUER_LOST := "发布者已离任，无法签结这份庄簿。"
const LEDGER_LOST := "未取得约定日期的在任庄簿。"
const TIME_UP := "已过回报期限。"
const KEYS := ["schema_version","status","actor_id","issuer_id","settlement_id","accepted_day",
	"deadline_day","ledger","ledger_hash","ended_day","reason","rewarded"]

static func reward_source(state: Dictionary) -> String:
	if state.is_empty():
		return ""
	return "quest/liuxi/%s/%d" % [state.actor_id, state.accepted_day]

static func _actor_lost(state: Dictionary, facts: Dictionary) -> bool:
	if state.actor_id != facts.player_id:
		return true
	return facts.members.get(state.actor_id, {}).get("life_status") not in ["Healthy", "Wounded", "Captive"]

static func _closed(state: Dictionary, status: String, day: int, reason: String) -> Dictionary:
	var next := state.duplicate(true)
	next.status = status
	next.ended_day = day
	next.reason = reason
	return next

static func reconcile(state: Dictionary, facts: Dictionary) -> Dictionary:
	if state.is_empty() or state.status in ["expired","failed"] or state.rewarded:
		return state
	if _actor_lost(state, facts):
		return _closed(state, "failed", facts.day, ACTOR_LOST)
	if state.status == "completed":
		return state
	if facts.governor_id != state.issuer_id or facts.settlement_id != state.settlement_id:
		return _closed(state, "failed", facts.day, ISSUER_LOST)
	if state.status == "active" and facts.day > state.accepted_day:
		var report: Dictionary = facts.last_report
		if report.get("day") != state.accepted_day+1 or report.get("governor_id") != state.issuer_id:
			return _closed(state, "failed", facts.day, LEDGER_LOST)
		var ready := state.duplicate(true)
		ready.status = "ready"
		ready.ledger = report.duplicate(true)
		ready.ledger_hash = C.hash_value(report).value
		state = ready
	if facts.day > state.deadline_day:
		return _closed(state, "expired", state.deadline_day + 1, TIME_UP)
	return state

static func _speaker(facts: Dictionary) -> Variant:
	var id: Variant = facts.governor_id
	var person: Dictionary = facts.members.get(id, {})
	if facts.settlement_id == null or id == facts.player_id or person.get("life_status") not in ["Healthy","Wounded"]:
		return null
	return {"id":id, "name":person.name, "appearance":person.appearance}

static func _offer(state: Dictionary, day: int) -> bool:
	return day <= V.MAX_INTEGER - TERM_DAYS - 1 and (state.is_empty()
		or (state.status in ["expired","failed"] and day > state.ended_day))

static func _delta(ledger: Dictionary) -> int:
	return ledger.prosperity_after - ledger.prosperity_before

static func _answers(ledger: Dictionary) -> Array:
	var gain := _delta(ledger)
	# A stable layout across reads, with two distinct, nonnegative distractors.
	var options := [gain, 0 if gain > 0 else 1, gain+1 if gain > 0 else 2]
	var first: int = (ledger.day + ledger.prosperity_before) % 3
	return [options[first], options[(first+1)%3], options[(first+2)%3]]

static func view(state: Dictionary, facts: Dictionary) -> Dictionary:
	var speaker: Variant = _speaker(facts)
	var visit: bool = facts.can_visit and speaker != null and V.integer(facts.get("opened_day"),0,facts.day)
	var status: String = state.get("status", "none")
	var original_actor: bool = facts.player_id != null and facts.player_id == state.get("actor_id")
	var report: bool = visit and status == "ready" and original_actor and speaker.id == state.issuer_id and facts.day <= state.deadline_day
	var claim: bool = facts.can_visit and original_actor and status == "completed" and not state.rewarded
	return {"settlement_id":facts.settlement_id, "can_visit":visit, "speaker":speaker, "status":status,
		"actor_id":state.get("actor_id"), "issuer_id":state.get("issuer_id"),
		"accepted_day":state.get("accepted_day"), "deadline_day":state.get("deadline_day"),
		"ledger":state.get("ledger", {}).duplicate(true), "reason":state.get("reason",""),
		"rewarded":state.get("rewarded",false), "can_accept":visit and _offer(state, facts.day),
		"can_report":report, "can_claim":claim, "answers":_answers(state.ledger) if report else []}

static func plan(state: Dictionary, op: String, args: Dictionary, facts: Dictionary) -> Dictionary:
	var options := view(state, facts)
	if op == "visit_claim":
		if not args.is_empty():
			return R.fail("InvalidArgument", "visit.claim")
		if not options.can_claim:
			return R.fail("InvalidState", "visit.claim")
		var claimed := state.duplicate(true)
		claimed.rewarded = true
		return R.ok(claimed)
	if op not in ["visit_accept","visit_report"]:
		return R.fail("InvalidArgument", "visit.operation")
	var needed := ["settlement_id","hero_id"] if op == "visit_accept" else ["settlement_id","hero_id","answer"]
	if args.size()!=needed.size() or not args.has_all(needed):
		return R.fail("InvalidArgument", "visit.args")
	if not options.can_visit or args.hero_id != options.speaker.id or args.settlement_id != facts.settlement_id:
		return R.fail("Unauthorized", "visit.speaker")
	if op == "visit_accept":
		if not options.can_accept:
			return R.fail("InvalidState", "visit.offer")
		return R.ok({"schema_version":1, "status":"active", "actor_id":facts.player_id,
			"issuer_id":facts.governor_id, "settlement_id":facts.settlement_id,
			"accepted_day":facts.day, "deadline_day":facts.day+TERM_DAYS,
			"ledger":{}, "ledger_hash":"", "ended_day":null, "reason":"", "rewarded":false})
	if not options.can_report:
		return R.fail("InvalidState", "visit.report")
	if not V.integer(args.answer) or args.answer != _delta(state.ledger):
		return R.fail("InvalidArgument", "visit.answer")
	return R.ok(_closed(state, "completed", facts.day, ""))

static func _ledger_valid(ledger: Dictionary, state: Dictionary, facts: Dictionary) -> bool:
	if ledger.is_empty():
		return state.ledger_hash==""
	var day: int = state.accepted_day+1
	if day>facts.day or ledger.get("governor_id")!=state.issuer_id:
		return false
	var digest := C.hash_value(ledger)
	if not digest.ok or digest.value!=state.ledger_hash:
		return false
	if not Governance.validate_daily_report(ledger,day,facts.opened_day,facts.members[state.issuer_id]).ok:
		return false
	var latest: Dictionary = facts.last_report
	if latest.get("day")==day:
		return latest==ledger
	if latest.get("day")==day+1:
		return latest.prosperity_before==ledger.prosperity_after and latest.loyalty_before==ledger.loyalty_after
	return true

static func validate(state: Dictionary, facts: Dictionary) -> Dictionary:
	if state.is_empty():
		return R.ok()
	if not V.integer(state.get("schema_version"),1,1):
		return R.fail("StaleVersion", "visit.schema_version")
	if state.size()!=KEYS.size() or not state.has_all(KEYS) or not state.rewarded is bool or not state.ledger is Dictionary:
		return R.fail("InvalidArgument", "visit.fields")
	if not V.typed_id(state.settlement_id,"settlement") or state.settlement_id!=facts.settlement_id:
		return R.fail("InvalidArgument", "visit.settlement_id")
	for id in [state.actor_id,state.issuer_id]:
		if not V.typed_id(id,"hero") or not facts.members.has(id):
			return R.fail("InvalidArgument", "visit.person")
	if not V.integer(facts.get("opened_day"),0,facts.day) or state.actor_id==state.issuer_id or not V.integer(state.accepted_day,facts.opened_day,mini(facts.day,V.MAX_INTEGER-TERM_DAYS-1)):
		return R.fail("InvalidArgument", "visit.origin")
	var deadline: int = state.accepted_day+TERM_DAYS
	if not V.integer(state.deadline_day,deadline,deadline):
		return R.fail("InvalidArgument", "visit.deadline")
	var ledger: Dictionary = state.ledger
	if not _ledger_valid(ledger,state,facts):
		return R.fail("InvalidArgument", "visit.ledger")
	if state.rewarded and state.status!="completed":
		return R.fail("InvalidState", "visit.rewarded")
	match state.status:
		"active","ready":
			if state.reason!="" or state.ended_day!=null or _actor_lost(state,facts) or facts.governor_id!=state.issuer_id:
				return R.fail("InvalidState", "visit.active")
			if facts.day>deadline or (state.status=="active" and (not ledger.is_empty() or state.accepted_day!=facts.day)) or (state.status=="ready" and ledger.is_empty()):
				return R.fail("InvalidState", "visit.stage")
		"completed":
			if state.reason!="" or ledger.is_empty() or not V.integer(state.ended_day,ledger.day,mini(deadline,facts.day)) or (not state.rewarded and _actor_lost(state,facts)):
				return R.fail("InvalidState", "visit.completion")
		"expired":
			if ledger.is_empty() or state.reason!=TIME_UP or not V.integer(state.ended_day,deadline+1,mini(deadline+1,facts.day)):
				return R.fail("InvalidState", "visit.expiry")
		"failed":
			if state.reason not in [ACTOR_LOST,ISSUER_LOST,LEDGER_LOST] or not V.integer(state.ended_day,state.accepted_day,facts.day):
				return R.fail("InvalidState", "visit.failure")
			if not ledger.is_empty() and state.ended_day<ledger.day:
				return R.fail("InvalidState", "visit.failure_day")
			if state.reason==ACTOR_LOST and not _actor_lost(state,facts):
				return R.fail("InvalidState", "visit.actor")
			if state.reason!=ACTOR_LOST and state.ended_day>deadline and state.reason!=LEDGER_LOST:
				return R.fail("InvalidState", "visit.failure_day")
		_:
			return R.fail("InvalidArgument", "visit.status")
	return R.ok()
