extends SceneTree
const Camp = preload("res://campaign/runtime.gd")
const R = preload("res://contracts/result.gd")
const F = preload("res://tests/p1/application/fixture.gd")
const PARTY := "party/00000000-0000-4000-8000-000000000010"
const DAY := 1440

var checks := 0
var failures := 0

func check(result: bool, label: String) -> bool:
	checks += 1
	if not result:
		failures += 1
		printerr("FAIL ", label)
	return result

func accept(_snapshot: Dictionary, _receipt: Dictionary) -> Dictionary:
	return R.ok()

func refuse(_snapshot: Dictionary, _receipt: Dictionary) -> Dictionary:
	return R.fail("Unavailable", "disk")

func exercise() -> void:
	var camp := Camp.new()
	var setup := F.options("governance")
	setup.start_def["game_minute"] = 3 * DAY + 1430
	var created := camp.create_world(setup.seed, setup.start_def, F.CONTENT)
	if not check(created.ok, "create campaign: %s" % str(created.get("error", {}))):
		return
	var untouched: Dictionary = camp.save_snapshot().value
	check(not camp.character_command("governor_open", {}, "no-family", accept).ok, "no holding before family")
	check(not camp.character_view().value.governance.established and camp.save_snapshot().value == untouched, "queries and refused opening preserve old world")
	if not check(camp.character_command("create", {"culture":"river"}, "new-family", accept).ok, "create existing household"):
		return
	var legacy: Dictionary = camp.save_snapshot().value
	check(not legacy.has("governance"), "old character save retains its shape before opening")
	check(not camp.character_command("governor_open", {}, "failed-opening", refuse).ok and camp.save_snapshot().value == legacy, "failed opening rolls back")
	if not check(camp.character_command("governor_open", {}, "opening", accept).ok, "take charge of manor"):
		return
	var view: Dictionary = camp.character_view().value
	var vacant: Dictionary = view.governance
	var cousin: String = view.heirs[0].id
	var assign := {"settlement_id":vacant.settlement_id, "hero_id":cousin}
	var manor := {"settlement_id":vacant.settlement_id}
	var slot := [{"count":1, "hero_id":cousin}]
	check(vacant.established and vacant.governor_id == null and vacant.last_day == 3 and vacant.last_report.is_empty(), "opening starts today without retrospective yields")
	var opening: Dictionary = camp.save_snapshot().value
	check(not camp.character_command("governor_assign", assign, "failed-post", refuse).ok and camp.save_snapshot().value == opening, "durability is required before appointment")
	if not check(camp.character_command("governor_assign", assign, "post", accept).ok, "appoint family member"):
		return
	var in_office: Dictionary = camp.save_snapshot().value
	var before_settlement: Dictionary = camp.character_view().value.governance
	check(not camp.check_character_sources(slot).ok and camp.check_character_sources([{"count":1,"hero_id":view.player_id}]).ok, "incumbent cannot deploy, player still can")
	check(not camp.character_command("governor_dismiss", manor, "failed-dismiss", refuse).ok and camp.save_snapshot().value == in_office, "failed dismissal preserves incumbent")
	check(not camp.character_command("rest", {}, "failed-day", refuse).ok and camp.save_snapshot().value == in_office, "failed day rolls back office, figures and time together")
	var branch := Camp.new()
	check(branch.restore(opening).ok and branch.step_until(4 * DAY, 32).ok, "parallel vacant day from same world")
	var empty_day: Dictionary = branch.character_view().value.governance
	check(empty_day.prosperity == 501 and empty_day.loyalty == 499, "vacant day applies only the base")
	check(camp.step_until(4 * DAY, 1).ok and camp.character_view().value.governance == before_settlement, "partial budget leaves the last committed day visible")
	check(camp.step_until(4 * DAY, 32).ok, "complete pending day")
	var result: Dictionary = camp.character_view().value.governance
	var candidate: Dictionary
	for entry in result.candidates:
		if entry.id == cousin:
			candidate = entry
	check(not candidate.is_empty() and result.prosperity == empty_day.prosperity + 1 + candidate.stewardship and result.loyalty == empty_day.loyalty + 1 + candidate.leadership, "actual incumbent skills change both daily totals")
	check(result.last_report.day == 4 and result.last_report.governor_id == cousin, "report identifies acting governor")
	var day_four: Dictionary = camp.save_snapshot().value
	check(camp.step_until(4 * DAY, 32).ok and camp.save_snapshot().value == day_four, "same minute cannot settle twice")
	var cold := Camp.new()
	check(cold.restore(day_four).ok and cold.character_view().value.governance == result, "cold restore preserves the projected holding")
	check(cold.character_command("governor_dismiss", manor, "dismiss", accept).ok and cold.check_character_sources(slot).ok, "dismissal releases deployment slot")
	check(cold.character_view().value.governance.last_report == result.last_report, "dismiss does not rewrite history")
	check(cold.character_command("governor_assign", assign, "again", accept).ok, "reappoint former governor")
	var frozen: Dictionary = cold.freeze_for_encounter(F.ENCOUNTER).value
	check(not cold.character_command("governor_dismiss", manor, "frozen", accept).ok and cold.release_freeze(frozen).ok, "cannot change offices during encounter freeze")
	var joined := {"hero_id":cousin,"source":"council/depart","kind":"join","location":PARTY}
	var before_join: Dictionary = cold.save_snapshot().value
	check(not cold.character_command("outcome", joined, "failed-join", refuse).ok and cold.save_snapshot().value == before_join, "failed departure preserves location and post")
	check(cold.character_command("outcome", joined, "join", accept).ok and cold.character_view().value.governance.governor_id == null, "moving away vacates office immediately")
	check(not cold.character_command("governor_assign", assign, "absent", accept).ok, "absent family member cannot be appointed")
	check(cold.restore(day_four).ok, "return to in-office save")
	var captured := {"hero_id":cousin,"source":"battle/captured","kind":"capture","location":PARTY}
	check(cold.character_command("outcome", captured, "capture", accept).ok and cold.character_view().value.governance.governor_id == null, "capture vacates without a clock tick")
	check(cold.restore(day_four).ok and cold.character_command("outcome", {"hero_id":cousin,"source":"battle/dead","kind":"death"}, "death", accept).ok and cold.character_view().value.governance.governor_id == null, "terminal governor leaves no assignment")
	check(cold.restore(day_four).ok and cold.character_command("retire", {"heir_id":cousin}, "succession", accept).ok, "succession while heir governs")
	var inherited: Dictionary = cold.character_view().value
	check(inherited.player_id == cousin and inherited.governance.governor_id == null and inherited.governance.owner_clan_id == result.owner_clan_id and inherited.governance.last_report == result.last_report, "new family leader keeps holding and prior history, vacates governor role")
	check(cold.restore(day_four).ok and cold.character_command("retire", {"heir_id":""}, "ending", accept).ok and cold.character_view().value.governance.governor_id == null, "ending the career vacates office")
	for bad in [{}, null, [], {"schema_version":99}]:
		var broken := day_four.duplicate(true)
		broken.governance = bad
		check(not cold.restore(broken).ok, "reject present empty, wrong type or future governance")
	for bad in [{"governor_id":view.player_id}, {"governor_id":"hero/00000000-0000-4000-8000-000000000006"}, {"owner_clan_id":"clan/00000000-0000-4000-8000-000000000006"}, {"last_day":5}]:
		var broken := day_four.duplicate(true)
		broken.governance.merge(bad, true)
		check(not cold.restore(broken).ok, "reject forged or stale holding field %s" % str(bad.keys()))
	check(cold.restore(legacy).ok and not cold.character_view().value.governance.established and cold.save_snapshot().value == legacy, "restoring pre-governance archive removes prior holding")
	check(cold.restore(untouched).ok and cold.save_snapshot().value == untouched, "pre-character archive survives")
	var split := Camp.new()
	check(split.restore(in_office).ok, "restore prior to day boundary")
	var prepared: Dictionary = split.prepare_day(4)
	check(prepared.ok and split.commit_day(prepared.value).ok and split.save_snapshot().value == day_four, "explicit prepare/commit agrees with budgeted stepping")
	check(not split.commit_day(prepared.value).ok and split.save_snapshot().value == day_four, "old plan rejected without repeat settlement")
	check(split.restore(in_office).ok and split.character_command("practice", {"skill":"stewardship","answer":0}, "practice", accept).ok and split.character_view().value.governance.last_report == result.last_report, "practice crossing midnight uses the same settlement")
	check(split.restore(in_office).ok and split.character_command("rest", {}, "overnight", accept).ok and split.character_view().value.governance == result, "rest reaches same governance totals as normal calendar")

func _initialize() -> void:
	exercise()
	print("GOVERNOR_CAMPAIGN checks=%d failures=%d" % [checks, failures])
	quit(int(failures != 0))
