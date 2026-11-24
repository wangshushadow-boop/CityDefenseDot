extends SceneTree

const Melee = preload("res://mission/combat/melee.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const Core = preload("res://core/runtime.gd")
const Mission = preload("res://mission/runtime/runtime.gd")
const C = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const A := {"index":0, "generation":1}
const B := {"index":1, "generation":1}
const SCOPE := "p2-combat"
var failures := 0
var adapter: RefCounted
var observed_regions := []


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL ", label)


func attack(handle: Dictionary, phase: String, dir: String) -> Dictionary:
	return {"actor_handle":handle, "input_phase":phase, "direction":dir, "weapon_slot":0, "target_hint":null}


func block(handle: Dictionary, held: bool, direction: String) -> Dictionary:
	return {"actor_handle":handle, "direction":direction, "held":held}


func duel(hp: int = 100) -> RefCounted:
	var sim := Melee.new()
	check(sim.add_actor(A, hp).ok and sim.add_actor(B, hp).ok, "register combatants")
	return sim


func overlap(tick: int, active: Array) -> Dictionary:
	var bodies: Dictionary = adapter.query_sweep_batch([{"from":[-2000,0,0], "to":[2000,0,0]}], {"scope_id":SCOPE, "tick":tick})
	if not bodies.ok:
		return bodies
	var matches := []
	for swing: Dictionary in active:
		for shape: Dictionary in bodies.value:
			if shape.entity_handle == "registered_target":
				observed_regions.append(shape.region)
				matches.append({"attacker":swing.attacker, "attack_id":swing.attack_id, "target":B, "contact_order":shape.fraction_ppm})
	return R.ok(matches)


func fixed_inputs(tick: int, direction: String, guard: bool) -> Array:
	match tick:
		1:
			var intent := attack(A, "start", direction)
			intent.target_hint = B
			return [intent, block(B, true, direction)] if guard else [intent]
		3: return [attack(A, "hold", direction)]
		8: return [attack(A, "release", direction)]
	return []


func replay(render_hz: int, direction: String, guard: bool) -> String:
	var sim := duel()
	var accumulator := 0
	var tick := 0
	var hits := []
	var trace := []
	var contacted := observed_regions.size()
	# A render scheduler can emit zero or several of the same 60 Hz fixed ticks.
	while tick < 14:
		accumulator += 60
		while accumulator >= render_hz and tick < 14:
			accumulator -= render_hz
			tick += 1
			var result: Dictionary = sim.step(tick, fixed_inputs(tick, direction, guard), overlap)
			check(result.ok, "replay step")
			if not result.ok:
				return ""
			for receipt in result.value.receipts:
				check(receipt.ok, "legal player/AI input")
			hits.append_array(result.value.hits)
			trace.append([sim.view(A).value, sim.view(B).value, result.value])
	check(observed_regions.slice(contacted) == ["first","second","first","second"], "two physical bones seen on both active ticks")
	check(hits.size() == 1 and hits[0].blocked == guard, "each swing contacts target only once")
	check(sim.view(B).value.hp == (100 if guard else 86), "charged damage / direction guard")
	check(sim.view(A).value.phase == "Ready", "recovery window completes")
	return C.hash_value(trace).value


func timing() -> void:
	var sim := duel()
	var a: Dictionary = sim.step(1, [attack(A,"start","left"), attack(A,"start","left")])
	check(a.ok and a.value.receipts[0].ok and not a.value.receipts[1].ok, "same tick duplicate press")
	var b: Dictionary = sim.step(2, [attack(A,"cancel","left"), attack(B,"start","right")])
	check(b.value.receipts[0].ok and sim.view(A).value.phase == "Ready", "early cancel")
	sim.step(3, [])
	var c: Dictionary = sim.step(4, [attack(B,"cancel","right"), attack(B,"release","right")])
	check(not c.value.receipts[0].ok and not c.value.receipts[1].ok and sim.view(B).value.phase == "Windup", "late cancel and early release")
	check(not sim.step(4, []).ok and not sim.step(6, []).ok, "stale or skipped tick")
	var forked: RefCounted = sim.fork()
	var bad := attack(A,"start","left")
	bad.erase("actor_handle")
	check(not forked.step(5, [attack(A,"start","up"), bad]).ok and forked.view(A).value.phase == "Ready", "invalid input rolls back entire tick")
	var wrong_slot := attack(B,"release","right")
	wrong_slot.weapon_slot = 1
	var f: Dictionary = forked.step(5, [wrong_slot, attack(B,"release","right")])
	check(not f.value.receipts[0].ok and f.value.receipts[1].ok, "selected weapon slot guard")
	check(sim.view(B).value.phase == "Windup" and forked.view(B).value.phase == "Active", "unpublished tick stays isolated")
	var old := attack({"index":0, "generation":9}, "start", "left")
	var g: Dictionary = sim.step(5, [old, attack(A,"start","unknown")])
	check(not g.value.receipts[0].ok and not g.value.receipts[1].ok, "stale handle and direction")
	check(sim.remove_actor(A).ok and sim.add_actor({"index":0, "generation":2}).ok and not sim.view(A).ok, "retired generation")


func simultaneous() -> void:
	var sim := duel(10)
	sim.step(1, [attack(A,"start","left"), attack(B,"start","right")])
	for tick in [2,3,4]:
		sim.step(tick, [])
	var releases := [attack(A,"release","left"), attack(B,"release","right")]
	var before: Dictionary = sim.view(A)
	var bad: Dictionary = sim.step(5, releases, func(_t, _active): return R.ok([{}]))
	check(not bad.ok and sim.view(A) == before, "failed collision query rolls back release")
	var hit: Dictionary = sim.step(5, releases, func(_t, active):
		var contacts := []
		for swing in active:
			var target := B if swing.attacker == A else A
			contacts.append({"attack_id":swing.attack_id,"attacker":swing.attacker,"target":target,"contact_order":0})
		contacts.reverse()
		return R.ok(contacts))
	check(hit.ok and hit.value.hits.size() == 2 and sim.view(A).value.phase == "Downed" and sim.view(B).value.phase == "Downed", "simultaneous contacts from phase start")


func mission_entry() -> void:
	var mission := Mission.new(Core.new(), adapter, "registered-combat")
	var region := {"id":"test:scene/combat", "simulation_scene":Adapter.DEFAULT_SCENE}
	var rules := {"id":"test:ruleset/duel"}
	var spec := {"schema_version":1,"encounter_id":"encounter/b48883c0-79fb-4cd3-96fe-43bb44dfddbb",
		"reservation_revision":1,"mode":"custom","scene_def_id":region.id,"ruleset_id":rules.id,
		"environment":{},"rng_seed":71,"sides":[],"reserved_sources":[],"battle_limit":2,
		"deployment_constraints":{},"siege_snapshot":null}
	check(mission.prepare(spec, region, rules).ok, "prepare production Mission")
	var actor: Dictionary = mission.allocate_entity(null, {}).value
	var target: Dictionary = mission.allocate_entity(null, {}).value
	var state := Melee.new()
	state.add_actor(actor)
	state.add_actor(target)
	check(mission.register_system("action", {"id":"melee", "run":func(_view, batch): return state.step(batch.source_tick, batch.inputs)}).ok, "register action phase")
	for tick in range(1,6):
		var intents := []
		if tick == 1 or tick == 4:
			var intent := attack(actor, "start" if tick == 1 else "release", "up")
			intent.target_hint = target
			intents.append(intent)
		var result := mission.step_fixed(tick,intents)
		check(result.ok and result.value.system_reports[0].value.tick == tick, "normal Mission step dispatch")
	check(state.view(actor).value.phase == "Active" and state.view(target).value.hp == 100, "unconfirmed target hint never changes hp")
	check(mission.dispose().ok, "release production Mission")


func contact_boundaries() -> void:
	var sim := duel()
	var other := {"index":2, "generation":1}
	sim.add_actor(other)
	sim.step(1, [attack(A,"start","up"), block(B,true,"left")])
	sim.step(2, [])
	sim.step(3, [])
	var original: RefCounted = sim.fork()
	var release := [attack(A,"release","up")]
	var result: Dictionary = sim.step(4, release, func(_tick, active):
		var id: String = active[0].attack_id
		return R.ok([
			{"attacker":A,"attack_id":id,"target":other,"contact_order":2},
			{"attacker":A,"attack_id":"retired","target":B,"contact_order":0},
			{"attacker":A,"attack_id":id,"target":{"index":1,"generation":9},"contact_order":0},
			{"attacker":A,"attack_id":id,"target":B,"contact_order":1}]))
	check(result.ok and result.value.hits.size() == 1 and sim.view(B).value.hp == 90 and sim.view(other).value.hp == 100, "wrong guard direction, stale swing, generation and ordered target cap")
	check(original.view(B).value.hp == 100 and original.view(A).value.phase == "Windup", "damage on fork leaves original untouched")
	var blocked: Dictionary = sim.step(5, [attack(A,"cancel","up"), block(A,true,"up")])
	check(not blocked.value.receipts[0].ok and not blocked.value.receipts[1].ok, "active cannot be cancelled or guarded")
	check(not sim.remove_actor({"index":0.0,"generation":1}).ok and sim.view(A).ok, "invalid numeric handle cannot retire a live combatant")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	adapter = Adapter.new(root, true)
	var scope: Dictionary = adapter.open_scope(SCOPE)
	var region := {"id":"test:scene/regions", "simulation_scene":"res://tests/p2/combat/regions.tscn"}
	check(scope.ok and adapter.load_scene(region, scope.value).ok, "real physics region fixtures")
	await physics_frame
	await physics_frame
	timing()
	simultaneous()
	contact_boundaries()
	mission_entry()
	var digests := []
	for direction: String in Melee.DIRECTIONS:
		var unguarded := replay(30, direction, false)
		var guarded := replay(30, direction, true)
		check(unguarded == replay(144, direction, false) and guarded == replay(144, direction, true) and guarded != unguarded, "identical fixed inputs over distinct render schedules")
		digests.append([unguarded,guarded])
	adapter.release_scope(SCOPE)
	print("P2-COM-001 T-COM-01/T-COM-05 slice errors=", failures, " replay_sha256=", C.hash_value(digests).value)
	var ran: bool = await preload("res://tests/p2/combat/field_cases.gd").new().run(self, adapter, check)
	check(ran, "completed field suite")
	print("P2-COM-002 ", "PASS" if failures == 0 else "FAIL", " errors=", failures)
	quit(1 if failures else 0)
