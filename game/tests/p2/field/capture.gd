extends "res://tests/p2/field_pipeline/run.gd"
## A close infantry engagement verifies a real capture and a wounded reinforcement who avoids capture.
const Brains = preload("res://mission/runtime/field_brains.gd")

func spear_inputs(actor: Dictionary, tick: int) -> Array:
	var view := hud()
	if view.rules.control_mode != "direct":
		return []
	var visual: Dictionary = mission.gateway("field.view", {"projection":"visual"}, token)
	var targets: Array = visual.value.actors.filter(func(row): return row.team == 1 and row.role != "mount")
	if targets.is_empty():
		return []
	var target: Dictionary = targets[0]
	var offset: Vector3 = target.position - view.position
	offset.y = 0
	var facing := offset.normalized()
	var advancing := offset.length() > 1.16
	var commands := [
		{"actor_handle":actor, "desired_direction":[roundi(facing.x * 1000000), 0, roundi(facing.z * 1000000)],
			"speed_fraction":1.0 if advancing else 0.0, "stance":"walk"},
		{"actor_handle":actor, "yaw":roundi(atan2(-facing.x, -facing.z) * 1000000), "pitch":0}
	]
	var phase := ""
	if view.player.phase == "Ready":
		phase = "start"
	elif view.player.phase == "Hold" and tick - view.player.since >= 7:
		phase = "release"
	if not advancing and not phase.is_empty():
		commands.append({"actor_handle":actor, "input_phase":phase, "weapon_slot":0, "direction":"thrust", "target_hint":target.handle})
	return commands

func run() -> void:
	var compiler := Compiler.new()
	var content := compiler.compile(compiler.scan_packages([Compiler.BASE_PACKAGE, "res://content/base/field"]), {})
	if not ok(content, "compile field equipment"):
		quit(1)
		return
	registry = content.value.registry
	adapter = EngineAdapter.new(root, true)
	brain_script = Brains
	var data := battle(["infantry"], [1], 1)
	data.spec.reserved_sources[1].count = 2
	data.spec.reserved_sources[1].source_slot_range = [1, 3]
	data.spec.sides[1].roster_allocations = [{"source_slot_range":[1, 3]}]
	data.scene.field_zones[1].points_mm.append([12000, 0, 0])
	if not await open(data):
		quit(1)
		return
	var opening: Dictionary = mission.step_fixed(1, [])
	if not ok(opening, "opening"):
		mission.dispose()
		quit(1)
		return
	var actor: Dictionary = hud().player_handle
	var enemy: Dictionary = opening.value.entities.filter(func(row): return row.source_slot == 1)[0].handle
	var saw_downed := false
	var hits := 0
	for tick in range(2, 1801):
		var commands := spear_inputs(actor, tick)
		if not commands.is_empty() and not ok(input(tick, commands), "player movement or attack"):
			break
		var step: Dictionary = mission.step_fixed(tick, [])
		if not ok(step, "next fixed step"):
			break
		for report in step.value.system_reports:
			if report.id != "field.combat":
				continue
			for hit in report.value.hits:
				if not hit.blocked and hit.damage > 0 and hit.attacker == actor:
					hits += 1
			for event in report.value.events:
				if event.type == "downed" and event.actor_handle == enemy:
					saw_downed = true
		if hud().rules.outcome != null:
			break
	var outcome: Variant = hud().rules.outcome
	if check(outcome != null, "natural battle result") and ok(mission.request_end(outcome), "end"):
		var result: Dictionary = mission.finalize()
		if ok(result, "final result"):
			var slots: Array = result.value.slot_outcomes
			check(mission.view().spawned_slots == [0, 1, 2] and slots.size() == 3, "reserve actually entered")
			check(result.value.outcome == "victory" and result.value.winner_team_keys == [0], "sole winner")
			check(saw_downed and hits > 0 and slots[1].source_slot_id == 1 and slots[1].wounded and slots[1].end_status == "wounded" and slots[1].captor_team_key == 0, "capture assigned to the victor after a real knockdown")
			check(slots[0].xp == hits and slots[0].end_status == "alive" and slots[0].captor_team_key == null, "survivor earned confirmed hit experience")
			check(slots[2].source_slot_id == 2 and slots[2].wounded and slots[2].end_status == "wounded" and slots[2].captor_team_key == null, "wounded reinforcement avoids capture")
			print("NATURAL_CAPTURE ", JSON.stringify({"tick":result.value.duration_ticks, "player_hits":hits, "slots":slots, "winners":result.value.winner_team_keys}))
	mission.dispose()
	print("FIELD_CAPTURE checks=", checks, " failures=", failed)
	quit(0 if failed == 0 else 1)
