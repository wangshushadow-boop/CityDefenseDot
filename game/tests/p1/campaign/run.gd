extends SceneTree

const Camp = preload("res://campaign/runtime.gd")
const C = preload("res://contracts/canonical.gd")
const V = preload("res://contracts/values.gd")
const R = preload("res://contracts/result.gd")
const Inv = preload("res://shared/inventory/inventory.gd")
const Compiler = preload("res://infrastructure/content/compiler.gd")
const SEED := "0011223344556677"
const CONTENT := {"packages":[{"id":"base","version":"1.0.0"}], "content_hash":"abc12300abc12300abc12300abc12300abc12300abc12300abc12300abc12300"}
const ENCOUNTER := "encounter/00000000-0000-4000-8000-000000000001"
const OTHER_ENCOUNTER := "encounter/00000000-0000-4000-8000-000000000002"
const COIN := {"kind":"currency","id":"base:currency/copper"}
const START := {"locations":{"purse":{"kind":"account","currency":"base:currency/copper"},
	"town":{"kind":"account","currency":"base:currency/copper"}},
	"initial":[{"holder":"purse","resource":COIN,"amount":120},{"holder":"town","resource":COIN,"amount":2}]}
var failures := 0


func expect(ok: bool, tag: String) -> void:
	if not ok:
		printerr("FAIL ", tag)
		failures += 1


func error(reply: Dictionary, code: String) -> bool:
	return not reply.get("ok", true) and reply.get("error",{}).get("code") == code


func pay(amount: int = 1) -> Dictionary:
	return {"src":"purse", "dst":"town", "resource":COIN, "amount":amount, "reason":"fixture", "source_ref":"test"}


func install(camp: Camp, trace: Array) -> void:
	# Two keys in one phase intentionally register in reverse order.
	for entry in [["market","z"],["market","a"],["production","upkeep"],["day_end","observer"]]:
		var planner := func(context: Dictionary):
			trace.append([context.day_id, context.phase, context.key, context.random_u32])
			return R.ok([pay()] if context.key == "upkeep" else [])
		expect(camp.register_phase(entry[0], entry[1], planner).ok, "register phase")


func view_inv(snap: Dictionary) -> Inv:
	var inv := Inv.new()
	expect(inv.restore(snap.inventory).ok, "inventory accepts campaign projection")
	return inv


func daily() -> bool:
	var camp := Camp.new()
	var trace := []
	install(camp,trace)
	expect(camp.create_world(SEED, START, CONTENT).ok, "start campaign")
	var start_view: Dictionary = camp.read_snapshot().value
	var before: Dictionary = camp.save_snapshot().value
	var first := camp.step_until(1440, 4)
	expect(first.ok and first.value.used == 4 and first.value.days_committed.is_empty(), "sliced budget")
	expect(camp.read_snapshot().value == start_view and error(camp.save_snapshot(),"InvalidState"), "no partial day or save")
	expect(error(camp.freeze_for_encounter(ENCOUNTER),"InvalidState"), "freeze only at barrier")
	expect(error(camp.exchange("other",[pay()]),"InvalidState"), "no mid-phase inventory writes")
	expect(error(camp.step_until(18,3),"InvalidState"), "pending boundary cannot be skipped")
	var finished := camp.step_until(1440, 20)
	expect(finished.ok and finished.value.days_committed == [1] and finished.value.reached, "finish first day")
	expect(trace.map(func(row):return row[2]) == ["upkeep","a","z","observer"], "stable planner order once")
	var saved := camp.save_snapshot().value as Dictionary
	var ledger := view_inv(saved)
	expect(ledger.balance("purse").value == 119 and ledger.balance("town").value == 3 and ledger.ledger_for("@camp/day/1").value.size() == 1,"actual ledger day posted once")
	expect(camp.step_until(1440, 4).value.used == 0 and camp.save_snapshot().value == saved, "repeat target never recharges")
	var other := Camp.new()
	var other_trace := []
	install(other, other_trace)
	expect(other.restore(before).ok and other.step_until(1440,40).ok, "unsliced run")
	expect(other.save_snapshot().value == saved and other_trace == trace, "budget independent state plus RNG")
	var plan := camp.prepare_day(2)
	expect(plan.ok and error(camp.commit_day(plan.value.duplicate()),"InvalidState"), "only prepared day token commits")
	expect(camp.commit_day(plan.value).ok and error(camp.commit_day(plan.value),"InvalidState"), "day committed only once")
	expect(other.step_until(2880, 40).ok and camp.save_snapshot().value == other.save_snapshot().value, "explicit prepare and commit equal automatic")
	var reject := Camp.new()
	expect(reject.create_world(SEED, START, CONTENT).ok,"failure world")
	expect(reject.register_phase("production","bad",func(_ctx): return R.ok([pay(900)])).ok, "failing plan registered")
	before = reject.save_snapshot().value
	expect(error(reject.step_until(1440, 20),"InsufficientResource") and reject.save_snapshot().value == before, "failed ledger leaves clock, resources, RNG, revision unchanged")
	expect(error(reject.step_until(15,1),"InvalidState") and reject.restore(before).ok and reject.step_until(15,1).ok,"failed invariant pauses until a verified safe point is restored")
	return true


func creation() -> bool:
	var first := Camp.new()
	var second := Camp.new()
	var reordered := START.duplicate(true)
	reordered.initial.reverse()
	var compiler := Compiler.new()
	var resolved := compiler.resolve_packages(compiler.scan_packages([Compiler.BASE_PACKAGE]),1)
	if not resolved.ok:
		return false
	var built := compiler.compile(resolved.value,{})
	if not built.ok:
		return false
	expect(first.create_world(SEED, START, built.value).ok and second.create_world(SEED, reordered, built.value).ok, "deterministic fixture from compiled base package")
	var snap := first.save_snapshot().value as Dictionary
	expect(V.typed_id(snap.world_id,"world"), "generated world scope is a stable typed UUID")
	expect(C.hash_value(snap).value == C.hash_value(second.save_snapshot().value).value, "canonical initial hash independent of iteration order")
	var different := Camp.new()
	expect(different.create_world("0000000000000002",START,built.value).ok and different.save_snapshot().value.world_id != snap.world_id,"seed changes world")
	var empty := Camp.new()
	expect(empty.create_world(SEED,{},CONTENT).ok and empty.step_until(4321,48).value.reached, "empty world crosses all days")
	expect(empty.save_snapshot().value.last_committed_day == 3,"no skipped days")
	expect(error(empty.step_until(4322.25,5),"InvalidArgument") and error(empty.step_until(4322,1.75),"InvalidArgument"),"fractional clock and budget rejected")
	var broken := snap.duplicate(true)
	broken.rng_states.worldgen.state = "0000000000000000"
	expect(not first.restore(broken).ok and first.save_snapshot().value == snap,"bad RNG restore atomic")
	broken = snap.duplicate(true)
	broken["future_required"] = "unknown"
	expect(error(first.restore(broken),"InvalidArgument") and first.save_snapshot().value == snap,"unknown snapshot field rejected")
	var public_view: Dictionary = first.read_snapshot({"observer":"player"}).value
	public_view.game_minute = 40
	expect(not public_view.has("inventory") and not public_view.has("rng_states") and first.read_snapshot().value.game_minute == 0, "detached public projection")
	var trace := []
	var trace2 := []
	install(first, trace)
	install(second, trace2)
	expect(first.step_until(1440,24).ok, "advance stream before save")
	var encoded := C.encode(first.save_snapshot().value)
	expect(second.restore(C.decode(encoded.value).value).ok, "cold restore")
	trace.clear()
	expect(first.step_until(4320,50).ok and second.step_until(4320,50).ok and trace == trace2 and first.save_snapshot().value == second.save_snapshot().value,"continued RNG and clock after restore")
	return true


func freeze_and_trade() -> bool:
	var camp := Camp.new()
	expect(camp.create_world(SEED, START, CONTENT).ok and camp.step_until(17,1).ok,"advance to visit")
	expect(error(camp.freeze_for_encounter("enc-1"),"InvalidArgument"),"typed encounter id")
	var frozen := camp.freeze_for_encounter(ENCOUNTER)
	expect(frozen.ok and camp.freeze_for_encounter(ENCOUNTER) == frozen and error(camp.freeze_for_encounter(OTHER_ENCOUNTER),"Conflict"),"same freeze token")
	var checkpoint := camp.save_snapshot().value as Dictionary
	expect(error(camp.step_until(23,100),"InvalidState") and camp.read_snapshot().value.game_minute == 17,"frozen clock")
	expect(camp.restore(checkpoint).ok and error(camp.release_freeze({}),"StaleVersion") and camp.release_freeze(frozen.value).ok,"restored freeze token")
	expect(camp.step_until(23,1).ok and camp.read_snapshot().value.game_minute == 23,"explicit return time")
	var before := camp.save_snapshot().value as Dictionary
	var capture := []
	var persist := func(snapshot: Dictionary, receipt: Dictionary):
		capture.append(snapshot.duplicate(true))
		expect(camp.read_snapshot().value.revision == before.revision and error(camp.dispose(),"InvalidState"),"old clock during durable call")
		expect(view_inv(snapshot).ledger_for(receipt.txn_id).ok,"candidate contains real receipt")
		return R.fail("Unavailable","disk") if capture.size() == 1 else R.ok()
	expect(error(camp.exchange("trade", [pay(2)], 0, persist), "Unavailable") and camp.save_snapshot().value == before,"whole trade failure atomic")
	var receipt := camp.exchange("trade",[pay(2)],0,persist)
	expect(receipt.ok and camp.save_snapshot().value == capture[1],"publish after acknowledged world candidate")
	expect(camp.exchange("trade",[pay(2)],0,persist) == receipt and capture.size() == 2 and camp.save_snapshot().value == capture[1],"retry does not persist or advance revision")
	var cold := Camp.new()
	expect(cold.restore(capture[1]).ok and cold.exchange("trade",[pay(2)],0,persist) == receipt,"restart retry preserved")
	expect(error(cold.exchange("trade",[pay(3)],0),"Conflict"),"changed payload")
	expect(cold.dispose().ok and not cold.read_snapshot().ok and not cold.create_world(SEED,{},CONTENT).ok,"disposed world")
	return true


func seed_slice() -> bool:
	for n in range(1,21):
		var camp := Camp.new()
		var seed_hex := "%016x" % n
		expect(camp.create_world(seed_hex,START,CONTENT).ok,"seeded campaign")
		var daily_transfer := func(ctx: Dictionary): return R.ok([pay(1 + ctx.random_u32 % 3)])
		expect(camp.register_phase("supply_payroll","ledger_fixture",daily_transfer).ok,"seed ledger fixture")
		for day in range(1,11):
			expect(camp.step_until(day*Camp.DAY,12).ok,"seeded day")
			var state: Dictionary = camp.save_snapshot().value
			var inv := view_inv(state)
			var purse: int = inv.balance("purse").value
			var town: int = inv.balance("town").value
			expect(purse >= 0 and town >= 0 and purse+town == 122 and inv.ledger_for("@camp/day/"+str(day)).ok, "bounded seed ledger conservation")
	return true


func _initialize() -> void:
	for suite in [["T-CAMP-01",daily],["T-CAMP-03",creation],["P1-CAMP-FREEZE-TRADE",freeze_and_trade],["P1-CAMP-20-SEED-SLICE",seed_slice]]:
		var before := failures
		expect(suite[1].call() == true, suite[0] + " completed")
		if before == failures:
			print("PASS ",suite[0])
	quit(0 if failures == 0 else 1)
