extends "res://tests/p4/governor_campaign/run.gd"
## Checks that the real campaign publishes the estate ledger, commission and XP together.

func exercise() -> void:
	var camp := Camp.new()
	var setup := F.options("estate-visit")
	setup.start_def["game_minute"] = 3 * DAY + DAY - 10
	if not check(camp.create_world(setup.seed, setup.start_def, F.CONTENT).ok, "start sandbox"): return
	var original: Dictionary = camp.save_snapshot().value
	check(not original.has("estate_commission") and camp.character_view().value.visit.speaker == null, "old world has no visitor or journal")
	if not check(camp.character_command("create", {"culture":"river"}, "birth", accept).ok, "create household"): return
	if not check(camp.character_command("governor_open", {}, "estate", accept).ok, "open estate"): return
	var info: Dictionary = camp.character_view().value
	var issuer: String = info.heirs[0].id
	var actor: String = info.player_id
	var estate := {"settlement_id":info.governance.settlement_id}
	var target := {"hero_id":issuer, "settlement_id":info.governance.settlement_id}
	check(not camp.character_command("visit_accept", target, "absent", accept).ok, "absent governor cannot give work")
	if not check(camp.character_command("governor_assign", target, "post", accept).ok, "appoint issuer"): return
	var legacy: Dictionary = camp.save_snapshot().value
	check(not legacy.has("estate_commission") and camp.character_view().value.visit.speaker.id == issuer, "governor resolves from the saved household")
	check(not camp.character_command("visit_accept", target, "disk-fail", refuse).ok and camp.save_snapshot().value == legacy, "rejected write leaves no commission")
	if not check(camp.character_command("visit_accept", target, "take", accept).ok, "accept at day three"): return
	var active: Dictionary = camp.save_snapshot().value
	check(active.estate_commission.status == "active" and active.estate_commission.accepted_day == 3, "accept captures actor, issuer and clock")
	var frozen: Dictionary = camp.freeze_for_encounter(F.ENCOUNTER).value
	check(not camp.character_command("visit_claim", {}, "while-frozen", accept).ok and camp.release_freeze(frozen).ok, "encounter freezes commission actions")
	check(camp.restore(active).ok and camp.step_until(4*DAY, 1).ok and camp.character_view().value.visit.status == "active", "partial day cannot publish the ledger")
	check(camp.step_until(4*DAY, 32).ok, "finish first day")
	var due: Dictionary = camp.character_view().value
	var ledger: Dictionary = due.governance.last_report
	if not check(due.visit.status == "ready" and due.visit.ledger == ledger and ledger.day == 4, "publish actual first day report"): return
	var ready: Dictionary = camp.save_snapshot().value
	var submitted := target.duplicate()
	submitted["answer"] = ledger.prosperity_after - ledger.prosperity_before
	var wrong := submitted.duplicate()
	wrong.answer += 1
	check(not camp.character_command("visit_report", wrong, "mistake", accept).ok and camp.save_snapshot().value == ready, "wrong account is not acknowledged")
	var cold := Camp.new()
	if not check(cold.restore(active).ok, "load active from new runtime"): return
	var token := cold.prepare_day(4)
	check(token.ok and cold.commit_day(token.value).ok and cold.save_snapshot().value == ready, "explicit day commit equals stepped day")
	check(cold.restore(active).ok and cold.character_command("practice", {"skill":"stewardship","answer":0}, "bell", accept).ok and cold.character_view().value.visit.ledger == ledger, "cross-midnight practice pins the same report")
	check(camp.character_command("rest", {}, "next", accept).ok and camp.character_view().value.visit.ledger == ledger and camp.character_view().value.governance.last_report.day == 5, "later real day cannot overwrite the promised account")
	if not check(camp.character_command("visit_report", submitted, "report", accept).ok, "submit original ledger after next day"): return
	var signed: Dictionary = camp.save_snapshot().value
	check(signed.estate_commission.status == "completed" and not signed.estate_commission.rewarded, "signature and reward separate")
	check(camp.character_command("governor_dismiss", estate, "release", accept).ok, "issuer leaves after signing")
	var awaiting: Dictionary = camp.save_snapshot().value
	var skill: Dictionary = camp.character_view().value.hero.skills.stewardship.duplicate()
	var forged := {"hero_id":actor, "kind":"skill", "skill":"stewardship", "amount":60, "source":"quest/liuxi/not-a-reward"}
	check(not camp.character_command("outcome", forged, "intrusion", accept).ok and camp.save_snapshot().value == awaiting, "reserved award cannot enter through general outcomes")
	check(not camp.character_command("visit_claim", {}, "write-failure", refuse).ok and camp.save_snapshot().value == awaiting, "failed reward write publishes neither XP nor quest flag")
	if not check(camp.character_command("visit_claim", {}, "claim", accept).ok, "issuer has left but signed reward remains collectible"): return
	var paid: Dictionary = camp.save_snapshot().value
	check(paid.estate_commission.rewarded and camp.character_view().value.hero.skills.stewardship != skill and paid.inventory == awaiting.inventory, "real character skill changes with unchanged inventory")
	check(not camp.character_command("visit_claim", {}, "claim-again", accept).ok and camp.save_snapshot().value == paid, "second claim cannot repeat learning")
	check(cold.restore(paid).ok and cold.character_view().value == camp.character_view().value, "accepted compact world round trips")
	for invalid in [{}, null, [], {"schema_version":2}]:
		var broken := paid.duplicate(true)
		broken["estate_commission"] = invalid
		check(not cold.restore(broken).ok and cold.save_snapshot().value == paid, "invalid optional repository rejected atomically")
	var missing := paid.duplicate(true)
	missing.erase("estate_commission")
	check(not cold.restore(missing).ok, "orphan XP receipt cannot become legacy archive")
	var unearned := paid.duplicate(true)
	unearned.characters = awaiting.characters
	check(not cold.restore(unearned).ok, "claimed flag requires an actual corresponding hero receipt")
	check(cold.restore(ready).ok and cold.character_command("governor_dismiss", estate, "vacate", accept).ok, "dismiss original issuer")
	check(cold.character_view().value.visit.status == "failed" and not cold.character_command("visit_report", submitted, "late-office", accept).ok, "retired authority cannot sign old work")
	check(cold.restore(ready).ok and cold.character_command("retire", {"heir_id":issuer}, "succession", accept).ok and cold.character_view().value.visit.status == "failed", "new head cannot take over the former head's task")
	check(cold.restore(signed).ok and cold.character_command("retire", {"heir_id":issuer}, "signed-succession", accept).ok and not cold.character_command("visit_claim", {}, "heir-claim", accept).ok, "new head cannot claim former head's experience")
	check(cold.restore(active).ok and cold.step_until(7*DAY, 256).ok and cold.character_view().value.visit.status == "expired", "first day after deadline expires even after multi-day skip")
	var stale := cold.save_snapshot().value as Dictionary
	stale.estate_commission = active.estate_commission
	check(not cold.restore(stale).ok, "stale active task cannot enter a later world day")
	check(cold.restore(legacy).ok and cold.save_snapshot().value == legacy and cold.character_view().value.visit.status == "none", "P4 estate survives without retroactive commission")
	check(cold.restore(original).ok and cold.save_snapshot().value == original, "world predating characters remains readable")

func _initialize() -> void:
	exercise()
	print("ESTATE_CAMPAIGN checks=%d failures=%d" % [checks, failures])
	quit(int(failures != 0))
