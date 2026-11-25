extends SceneTree
const Camp = preload("res://campaign/runtime.gd")
const R = preload("res://contracts/result.gd")
const Inv = preload("res://shared/inventory/inventory.gd")
const F = preload("res://tests/p1/application/fixture.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		printerr("FAIL ", label)
		failures += 1
	return condition

func write_ok(_snapshot: Dictionary, _receipt: Dictionary) -> Dictionary:
	return R.ok()

func purse(saved: Dictionary) -> int:
	var inv := Inv.new()
	if not inv.restore(saved.inventory).ok:
		return -1
	return inv.balance("purse").value

func exercise() -> void:
	var camp := Camp.new()
	var args := F.options("campchars")
	args.start_def["game_minute"] = 1430
	var started := camp.create_world(args.seed, args.start_def, F.CONTENT)
	if not check(started.ok, "start existing world"):
		return
	var legacy: Dictionary = camp.save_snapshot().value
	check(not legacy.has("characters"), "pre-character snapshot is unchanged")
	check(camp.character_view().value.hero == null, "empty read model")
	check(camp.save_snapshot().value == legacy, "query preserves old save bytes")
	if not check(camp.character_command("create", {}, "create", write_ok).ok, "create"):
		return
	var id: String = camp.character_view().value.player_id
	var sources := [{"hero_id":id, "count":1}]
	check(camp.check_character_sources(sources).ok and not camp.check_character_sources([{"hero_id":"hero/00000000-0000-4000-8000-000000000005", "count":1}]).ok, "only existing fit heroes deploy")
	check(not camp.check_character_sources([{"hero_id":id, "count":2}]).ok, "one hero cannot represent two source slots")
	check(camp.check_character_sources([{"hero_id":null, "count":50},{"hero_id":null, "count":40}]).ok, "ordinary troop sources retain multiplicity")
	var wound := {"hero_id":id, "source":"battle/camp1", "kind":"wound", "severity":40}
	check(camp.character_command("outcome", wound, "wound", write_ok).ok, "injury from authority")
	check(not camp.check_character_sources(sources).ok, "wounded hero cannot be deployed")
	var before: Dictionary = camp.save_snapshot().value
	var old_wounds: int = camp.character_view().value.hero.wounds
	var rejected = func(_proposal, _receipt): return R.fail("Unavailable", "disk")
	check(camp.register_phase("production", "existing", func(_ctx): return R.ok([F.line("purse", "town", 3)])).ok, "register original day planner")
	var receipts := []
	var persist = func(proposal: Dictionary, receipt: Dictionary):
		receipts.append([proposal, receipt])
		return R.ok()
	check(not camp.character_command("rest", {}, "rest", rejected).ok, "failed durable rest")
	check(camp.save_snapshot().value == before and purse(before) == 100, "calendar, inventory and hero rollback together")
	if not check(camp.character_command("rest", {}, "rest", persist).ok, "retry rest"):
		return
	var after: Dictionary = camp.save_snapshot().value
	check(receipts.size() == 1 and receipts[0][0] == after and receipts[0][1].committed_revision == after.revision, "one durable candidate with final world revision")
	check(after.game_minute == 2870 and after.last_committed_day == 1 and purse(after) == 97, "original day phases committed exactly once")
	var id_item: String = camp.character_view().value.gear.profiles.combat.main_hand
	var line := {"src":after.inventory.state.owners[id_item], "dst":"warehouse", "resource":{"kind":"instance", "id":id_item},
		"amount":1, "reason":"wrong-owner", "source_ref":"stale-hook"}
	var snapshot := after.duplicate(true)
	snapshot.inventory.locations["warehouse"] = {"kind":"inventory", "capacity":32}
	var isolated := Camp.new()
	if not check(isolated.restore(snapshot).ok, "existing regular storage remains compatible"):
		return
	check(not isolated.exchange("unapproved-gear", [line], -1, write_ok).ok and isolated.save_snapshot().value == snapshot, "ordinary exchange cannot move hero equipment")
	check(isolated.register_phase("production","wrong-owner",func(_ctx):return R.ok([line])).ok, "register another daily planner")
	check(not isolated.character_command("rest", {}, "rest-bad", write_ok).ok and isolated.save_snapshot().value == snapshot, "rest rejects conflicting daily write without exposing partial state")
	check(not isolated.step_until(2880, 64).ok and isolated.save_snapshot().value == snapshot, "ordinary daily settlement rejects conflicting gear move")
	var healed: int = camp.character_view().value.hero.wounds
	check(healed < old_wounds and healed > 0, "one day of recovery")
	check(camp.step_until(after.game_minute, 32).ok and camp.save_snapshot().value == after, "same boundary cannot heal twice")
	check(camp.step_until(2880, 32).ok and camp.character_view().value.hero.wounds < healed and purse(camp.save_snapshot().value) == 94, "existing step_until performs next daily recovery")
	var ordinary_healing: int = healed - camp.character_view().value.hero.wounds
	check(old_wounds - healed > ordinary_healing, "active rest outheals subsequent ordinary day without leaving a bonus")
	var restored := Camp.new()
	check(restored.restore(after).ok and restored.save_snapshot().value == after, "cold character/INV restoration")
	var invalid := after.duplicate(true)
	invalid.characters.schema_version = 99
	check(not restored.restore(invalid).ok and restored.save_snapshot().value == after, "unknown character version leaves old world")
	invalid = after.duplicate(true)
	invalid.characters = {}
	check(not restored.restore(invalid).ok, "reject malformed empty subtree")
	invalid = after.duplicate(true)
	invalid.erase("characters")
	check(not restored.restore(invalid).ok and restored.save_snapshot().value == after, "missing subtree rejects orphaned character equipment")
	check(restored.restore(legacy).ok and restored.save_snapshot().value == legacy and restored.character_view().value.hero == null, "restore real previous state clears all character ownership")

func _initialize() -> void:
	exercise()
	print("CAMPAIGN_CHARACTER checks=%d failures=%d" % [checks, failures])
	quit(int(failures != 0))
