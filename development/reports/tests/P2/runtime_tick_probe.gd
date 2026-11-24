extends "res://tests/p2/mission/run.gd"

# Measures the existing runtime on its own. It draws no frames and runs no AI.
func run() -> void:
	var core := Core.new("1234567890abcdef")
	var adapter := Adapter.new(root, true)
	for count: int in [500, 1000]:
		var mission := Mission.new(core, adapter, "profile")
		var encounter := spec("custom", [source(0, count)])
		encounter.battle_limit = count
		check(mission.prepare(encounter, SCENE, RULE).ok, "prepare")
		var orders := []
		for i in count:
			orders.append({"source_slot":i, "components":{"type":"human", "team":i % 2}})
		check(mission.apply_deployment(orders).ok, "deployment")
		var samples := PackedInt64Array()
		var inputs := []
		for i in range(0, count, 20):
			inputs.append({"actor_handle":{"index":i,"generation":1},"direction":"left","held":true})
		for tick in range(1, 261):
			var before := Time.get_ticks_usec()
			var report := mission.step_fixed(tick, [] if tick <= 130 else inputs)
			var elapsed := Time.get_ticks_usec() - before
			check(report.ok and report.value.entities.size() == count, "tick")
			if tick % 130 > 10 or tick % 130 == 0:
				samples.append(elapsed)
			if tick % 130 == 0:
				samples.sort()
				print("Mission-only count=%d n=%d inputs=%d tick_us p50=%d p95=%d max=%d" % [
					count, samples.size(), 0 if tick == 130 else inputs.size(), samples[59], samples[113], samples[-1]])
				samples.clear()
		check(mission.dispose().ok, "dispose")
	print("MISSION-ONLY ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
