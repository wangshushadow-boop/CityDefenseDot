extends RefCounted
## SET owns the family estate and its daily account. Campaign supplies CHR facts.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const ESTATE_NAME := "柳溪庄"
const INITIAL := 500
const LIMIT := 1000
const PROSPERITY_BASE := 1
const LOYALTY_BASE := -1
const STATE_KEYS := ["schema_version", "settlement_id", "owner_clan_id", "governor_id",
	"opened_day", "last_day", "prosperity", "loyalty", "last_report"]

static func _estate_id(world: String) -> String:
	var bits := (world + "/settlement/liuxi").sha256_text()
	return "settlement/%s-%s-4%s-%s%s-%s" % [bits.left(8), bits.substr(8, 4),
		bits.substr(13, 3), "89ab"[bits.substr(16, 1).hex_to_int() % 4],
		bits.substr(17, 3), bits.substr(20, 12)]

static func _member(facts: Dictionary, id: Variant) -> Dictionary:
	if id != null:
		for person in facts.get("members", []):
			if person.id == id:
				return person
	return {}

static func plan(state: Dictionary, op: String, args: Dictionary, world: String, day: int, facts: Dictionary) -> Dictionary:
	if not facts.get("can_manage", false) or not V.typed_id(facts.get("clan_id"), "clan"):
		return R.fail("Unauthorized", "governance.manager")
	if op == "governor_open":
		if not args.is_empty() or world.is_empty() or not V.integer(day):
			return R.fail("InvalidArgument", "governance.open")
		if not state.is_empty():
			return R.fail("Conflict", "governance.established")
		return R.ok({"schema_version":1, "settlement_id":_estate_id(world), "owner_clan_id":facts.clan_id,
			"governor_id":null, "opened_day":day, "last_day":day,
			"prosperity":INITIAL, "loyalty":INITIAL, "last_report":{}})
	if op not in ["governor_assign", "governor_dismiss"]:
		return R.fail("InvalidArgument", "governance.operation")
	if state.is_empty():
		return R.fail("NotFound", "governance.estate")
	if state.owner_clan_id != facts.clan_id:
		return R.fail("Unauthorized", "governance.owner")
	if not V.typed_id(args.get("settlement_id"), "settlement") or args.settlement_id != state.settlement_id or state.settlement_id != _estate_id(world):
		return R.fail("InvalidArgument", "governance.settlement_id")
	if day != state.last_day:
		return R.fail("StaleVersion", "governance.day")
	var next_id: Variant = null
	if op == "governor_assign":
		if args.size() != 2 or not V.typed_id(args.get("hero_id"), "hero"):
			return R.fail("InvalidArgument", "governance.hero_id")
		next_id = args.hero_id
		if not _member(facts, next_id).get("eligible", false):
			return R.fail("InvalidState", "governance.eligibility")
	elif args.size() != 1:
		return R.fail("InvalidArgument", "governance.dismiss")
	if next_id == state.governor_id:
		return R.fail("Conflict", "governance.appointment")
	var next := state.duplicate(true)
	next.governor_id = next_id
	return R.ok(next)

static func reconcile(state: Dictionary, facts: Dictionary) -> Dictionary:
	if state.get("governor_id") == null or _member(facts, state.governor_id).get("eligible", false):
		return state
	var next := state.duplicate(true)
	next.governor_id = null
	return next

static func _report(day: int, id: Variant, prosperity: int, loyalty: int, prosperity_bonus: int, loyalty_bonus: int) -> Dictionary:
	return {"day":day, "governor_id":id,
		"prosperity_before":prosperity, "prosperity_base":PROSPERITY_BASE, "prosperity_bonus":prosperity_bonus,
		"prosperity_after":clampi(prosperity + PROSPERITY_BASE + prosperity_bonus, 0, LIMIT),
		"loyalty_before":loyalty, "loyalty_base":LOYALTY_BASE, "loyalty_bonus":loyalty_bonus,
		"loyalty_after":clampi(loyalty + LOYALTY_BASE + loyalty_bonus, 0, LIMIT)}

static func _forecast(state: Dictionary, day: int, facts: Dictionary) -> Dictionary:
	var member := _member(facts, state.governor_id)
	var serving: bool = member.get("eligible", false)
	return _report(day, state.governor_id if serving else null, state.prosperity, state.loyalty,
		1 + member.stewardship if serving else 0, 1 + member.leadership if serving else 0)

static func daily(state: Dictionary, day: int, facts: Dictionary) -> Dictionary:
	if state.is_empty():
		return R.ok({})
	if not V.integer(day, 1) or day != state.last_day + 1:
		return R.fail("StaleVersion", "governance.day")
	if state.owner_clan_id != facts.get("clan_id"):
		return R.fail("InvalidState", "governance.owner")
	var report := _forecast(state, day, facts)
	var next := state.duplicate(true)
	next.governor_id = report.governor_id
	next.prosperity = report.prosperity_after
	next.loyalty = report.loyalty_after
	next.last_day = day
	next.last_report = report
	return R.ok(next)

static func validate(state: Dictionary, world: String, day: int, facts: Dictionary) -> Dictionary:
	if state.is_empty():
		return R.ok()
	if not V.integer(state.get("schema_version"), 1, 1):
		return R.fail("StaleVersion", "governance.schema_version")
	if state.size() != STATE_KEYS.size() or not state.has_all(STATE_KEYS):
		return R.fail("InvalidArgument", "governance.fields")
	if state.settlement_id != _estate_id(world) or not V.typed_id(state.owner_clan_id, "clan") or state.owner_clan_id != facts.get("clan_id"):
		return R.fail("InvalidArgument", "governance.owner")
	if state.governor_id != null and (not V.typed_id(state.governor_id, "hero") or not _member(facts, state.governor_id).get("eligible", false)):
		return R.fail("InvalidState", "governance.governor_id")
	if not V.integer(state.last_day, day, day) or not V.integer(state.opened_day, 0, day):
		return R.fail("InvalidArgument", "governance.day")
	if not V.integer(state.prosperity, 0, LIMIT) or not V.integer(state.loyalty, 0, LIMIT) or not state.last_report is Dictionary:
		return R.fail("InvalidArgument", "governance.condition")
	var report: Dictionary = state.last_report
	if state.opened_day == day:
		if report.is_empty() and state.prosperity == INITIAL and state.loyalty == INITIAL:
			return R.ok()
		return R.fail("InvalidArgument", "governance.genesis")
	var verified := validate_daily_report(report, day, state.opened_day, _member(facts, report.get("governor_id")))
	if not verified.ok:
		return verified
	if state.prosperity != report.prosperity_after or state.loyalty != report.loyalty_after:
		return R.fail("InvalidArgument", "governance.report")
	return R.ok()

## Historical users retain the account exactly as SET calculated it, including the bounds.
static func validate_daily_report(report: Dictionary, day: int, opened_day: int, historical_member: Dictionary) -> Dictionary:
	if day <= opened_day:
		return R.fail("InvalidArgument", "governance.report_day")
	var id: Variant = report.get("governor_id")
	if id != null and (not V.typed_id(id, "hero") or not V.integer(historical_member.get("stewardship")) or not V.integer(historical_member.get("leadership"))):
		return R.fail("InvalidArgument", "governance.report_governor")
	if not V.integer(report.get("prosperity_before"), 0, LIMIT) or not V.integer(report.get("loyalty_before"), 0, LIMIT):
		return R.fail("InvalidArgument", "governance.report_before")
	if opened_day + 1 == day and (report.prosperity_before != INITIAL or report.loyalty_before != INITIAL):
		return R.fail("InvalidArgument", "governance.first_day")
	var lower := 0 if id == null else 1
	# The P3 household retains former office-holders. Learned skills and perks can increase after a report.
	var max_prosperity: int = 0 if id == null else 1 + historical_member.stewardship
	var max_loyalty: int = 0 if id == null else 1 + historical_member.leadership
	if not V.integer(report.get("prosperity_bonus"), lower, max_prosperity) or not V.integer(report.get("loyalty_bonus"), lower, max_loyalty):
		return R.fail("InvalidArgument", "governance.report_bonus")
	var expected := _report(day, id, report.prosperity_before, report.loyalty_before, report.prosperity_bonus, report.loyalty_bonus)
	if report != expected:
		return R.fail("InvalidArgument", "governance.report")
	return R.ok()

static func view(state: Dictionary, world: String, day: int, facts: Dictionary) -> Dictionary:
	var established := not state.is_empty()
	return {"established":established, "can_manage":facts.get("can_manage", false),
		"opened_day":state.get("opened_day"),
		"settlement_id":state.get("settlement_id", _estate_id(world)), "name":ESTATE_NAME,
		"owner_clan_id":state.get("owner_clan_id"), "governor_id":state.get("governor_id"),
		"candidates":facts.get("members", []).duplicate(true),
		"prosperity":state.get("prosperity", 0), "loyalty":state.get("loyalty", 0),
		"last_day":state.get("last_day", day), "last_report":state.get("last_report", {}).duplicate(true),
		"next_report":_forecast(state, day + 1, facts) if established else {}}
