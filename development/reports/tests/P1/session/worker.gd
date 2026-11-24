extends SceneTree

const Session = preload("res://application/game_session.gd")
const Camp = preload("res://campaign/runtime.gd")
const Inv = preload("res://shared/inventory/inventory.gd")
const Mission = preload("res://mission/runtime/runtime.gd")
const Core = preload("res://core/runtime.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const Store = preload("res://infrastructure/persistence/save_service.gd")
const Codec = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const Fixture = preload("res://tests/p1/application/fixture.gd")

const COIN := {"kind":"currency","id":"base:currency/copper"}
const START := {"locations":{"payer":{"kind":"account","currency":"base:currency/copper"},
	"reserve":{"kind":"account","currency":"base:currency/copper"}},"initial":[
	{"holder":"payer","resource":COIN,"amount":100},{"holder":"reserve","resource":COIN,"amount":1}]}
const EMPTY_ENGINE := {"scopes":0,"leases":0,"requests":0}
var adapter: Adapter
var core := Core.new("0000000000000041", 0)
var folder: String
var slot: String
var failed := false


func _initialize() -> void:
	run.call_deferred()


func expect(condition: bool, label: String, detail: Variant = null) -> bool:
	if not condition:
		printerr("FAIL ", label, " ", detail)
		failed = true
	return condition


func mission_factory(mode: String) -> Mission:
	return Mission.new(core, adapter, mode, Fixture.build)


# The result builder and reward policy are test inputs; Session, the SceneTree
# and Mission simulation, CAMP/INV, and every save and reload are production.
func settlement(_spec: Dictionary, result: Dictionary) -> Dictionary:
	var transfer: Dictionary = Fixture.line("payer","reserve",1)
	transfer["source_ref"] = result.result_id
	return R.ok([transfer])


func new_session(store: Store) -> Session:
	return Session.new(store, func(): return Camp.new(), mission_factory,
		Fixture.authorize, settlement)


func start(s: Session) -> bool:
	var opts: Dictionary = Fixture.options(slot).duplicate(true)
	opts["start_def"] = START
	var reply := s.start_session("sandbox", opts)
	return expect(reply.ok, "start sandbox", reply)


func enter(s: Session, cycle: int) -> bool:
	var map := s.query("campaign")
	if not expect(map.ok, "query campaign", map):
		return false
	var spec: Dictionary = Fixture.spec("campaign", map.value.revision + 1).duplicate(true)
	spec["encounter_id"] = "encounter/00000000-0000-4000-8000-%012x" % cycle
	var ready := s.prepare_mission(spec, Fixture.SCENE, Fixture.RULE)
	if not expect(ready.ok, "prepare Mission", ready):
		return false
	var counts := adapter.counts()
	if not expect(counts.scopes == 1 and counts.leases >= 1, "engine holds the Mission scene", counts):
		return false
	var tick := s.step_fixed(1, [])
	return expect(tick.ok, "step Mission", tick)


func finish(s: Session) -> Dictionary:
	var reply := s.finish_mission({"outcome":"withdrawn"})
	if not expect(reply.ok, "finish Mission", reply):
		return {}
	return reply.value


func account_snapshot(store: Store, starting: bool, expected_count: int) -> Dictionary:
	var opened := store.recover(slot)
	if not expect(opened.ok, "reopen from storage", opened):
		return {}
	var saved: Dictionary = opened.value.snapshot
	var ledger := Inv.new()
	var restored := ledger.restore(saved.campaign.inventory)
	if not expect(restored.ok, "restore inventory", restored):
		return {}
	var payer := ledger.balance("payer")
	var reserve := ledger.balance("reserve")
	if not expect(payer.ok and reserve.ok and payer.value == 100-expected_count and reserve.value == 1+expected_count,
			"durable currency in both accounts", [payer, reserve, expected_count]):
		return {}
	if not expect(saved.session.results.size() == expected_count, "durable result receipts",
			[saved.session.results.size(), expected_count]):
		return {}
	if starting:
		if not expect(saved.session.pending is Dictionary and not saved.session.pending.is_empty() and
				saved.campaign.freeze != null, "pending result and frozen encounter checkpoint"):
			return {}
	return {"data":saved,"commit":opened.value.manifest.commit_id,"source":opened.value.source}


func crash_case() -> void:
	var store := Store.new(folder)
	var s := new_session(store)
	if not start(s) or not enter(s, 1):
		return
	var prebattle := account_snapshot(store, true, 0)
	if prebattle.is_empty() or not expect(prebattle.data.session.pending.result == null,
			"prebattle checkpoint predates Mission completion"):
		return
	print("SESSION_CHECKPOINT commit=",prebattle.commit," payer=100 reserve=1 result_count=0")
	var result := finish(s)
	if result.is_empty() or account_snapshot(store,true,0).is_empty():
		return
	# The sender retains the actual result it has not received a receipt for.
	var packet := FileAccess.open(folder.path_join(slot + ".packet"), FileAccess.WRITE)
	packet.store_buffer(Codec.encode(result).value)
	packet.close()
	store.fault_point = slot
	store.on_injected_fault = func(point):
		var hit := FileAccess.open(folder.path_join(slot + ".hit"), FileAccess.WRITE)
		hit.store_line(point)
		hit.close()
		OS.kill(OS.get_process_id())
	var unexpected := s.route_result(result)
	expect(false, "fault point returned", unexpected)


func inspect_retry(action: String) -> void:
	var store := Store.new(folder)
	var s := new_session(store)
	var cold := s.load_session(slot, Fixture.CONTENT)
	if not expect(cold.ok, "load Session in fresh process", cold):
		return
	var was_pending := action == "retry" and slot != "after_marker"
	var old := account_snapshot(store, was_pending, 0 if was_pending else 1)
	var packet := Codec.decode(FileAccess.get_file_as_bytes(folder.path_join(slot + ".packet")))
	if old.is_empty() or not expect(packet.ok, "recover sender packet", packet):
		return
	var receipt := s.route_result(packet.value)
	if not expect(receipt.ok, "resubmit canonical result", receipt):
		return
	var now := account_snapshot(store,false,1)
	if now.is_empty():
		return
	var fact: Dictionary = now.data.session.results.values()[0]
	expect(fact.receipt == receipt.value and receipt.value.command_id == packet.value.result_id,
		"original accepted receipt", receipt)
	if not was_pending:
		expect(now.commit == old.commit and now.data == old.data, "replay changed a committed generation")
	var again := s.route_result(packet.value)
	expect(again == receipt and store.recover(slot).value.manifest.commit_id == now.commit,
		"second replay changed receipt or save")
	var closed := s.close_session("qa")
	expect(closed.ok, "close recovered Session", closed)
	print("SESSION_RETRY point=", slot, " action=", action, " pending_before=", was_pending,
		" source_before=", old.source, " payer=99 reserve=2 result_count=1 receipt_revision=", receipt.value.committed_revision)


func one_cycle(s: Session, store: Store, index: int) -> bool:
	if not enter(s,index):
		return false
	var result := finish(s)
	if result.is_empty():
		return false
	var routed := s.route_result(result)
	if not expect(routed.ok, "cycle settlement", routed):
		return false
	var closed := s.dispose_mission()
	if not expect(closed.ok, "release Mission", closed):
		return false
	if not expect(adapter.counts() == EMPTY_ENGINE, "release scopes, requests, leases", adapter.counts()):
		return false
	var disk := account_snapshot(store,false,index)
	if disk.is_empty():
		return false
	var copy := new_session(Store.new(folder))
	var loaded := copy.load_session(slot,Fixture.CONTENT)
	if not expect(loaded.ok and copy.query("campaign") == s.query("campaign"), "reload latest Session",loaded):
		return false
	var released := copy.close_session("qa-reopen")
	return expect(released.ok, "close reloaded Session", released)


func measure() -> Dictionary:
	return {"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_bytes":OS.get_static_memory_usage(),"engine":adapter.counts()}


func warmup(store: Store) -> bool:
	var test_slot := slot
	slot += "_warm"
	var local := new_session(store)
	var ok := start(local) and one_cycle(local,store,1)
	var released := local.close_session("qa-warmup")
	slot = test_slot
	return ok and expect(released.ok, "close warmup Session", released)


func cycles() -> void:
	var store := Store.new(folder)
	if not warmup(store):
		return
	# The engine's first full idle frame completes one-time object creation.
	# Compare both ends at the same point following two idle frame boundaries.
	await process_frame
	await process_frame
	var baseline := measure()
	print("SESSION_BASELINE ", JSON.stringify(baseline))
	var s := new_session(store)
	if not start(s):
		return
	var children := root.get_child_count()
	for index in range(1,51):
		var time := Time.get_ticks_msec()
		if not one_cycle(s,store,index):
			return
		await process_frame
		if not expect(root.get_child_count() == children, "scene tree child count", index):
			return
		var snapshot := measure()
		snapshot["cycle"] = index
		snapshot["elapsed_ms"] = Time.get_ticks_msec()-time
		print("SESSION_CYCLE ", JSON.stringify(snapshot))
	var closed := s.close_session("qa-finished")
	expect(closed.ok, "close 50-cycle Session", closed)
	s = null
	await process_frame
	await process_frame
	var after := measure()
	print("SESSION_AFTER_CLOSE ", JSON.stringify(after))
	expect(after.nodes == baseline.nodes and after.orphans == baseline.orphans and after.engine == EMPTY_ENGINE
		and after.resources == baseline.resources and after.objects == baseline.objects,
		"post-close node, object, resource and lease baseline", [baseline, after])


func run() -> void:
	var args := OS.get_cmdline_user_args()
	folder = args[0]
	slot = args[1]
	adapter = Adapter.new(root, true)
	match args[2]:
		"crash": crash_case()
		"cycles": await cycles()
		"retry", "inspect": inspect_retry(args[2])
		_: expect(false, "unknown action")
	print("SESSION_END ",args[2]," ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
