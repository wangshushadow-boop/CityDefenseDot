extends SceneTree
const Store = preload("res://infrastructure/persistence/save_service.gd")
const HASH := "3535353535353535353535353535353535353535353535353535353535353535"
const CONTENT := {"content_hash":HASH,"content_packages":["base@1.0"]}

static func state(reward: int) -> Dictionary:
	return {"world_id":"world-1","content_hash":HASH,"content_packages":["base@1.0"],
		"game_minute":1555200+reward,"revision":10+reward,"rng_states":{"loot":"f321aaaabbbbcccc"},
		"reward":reward,"repositories":{"inventory":{"count":100+reward}}}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var service := Store.new(args[0])
	var slot := args[1]
	var action := args[2]
	var ok := false
	match action:
		"seed":
			var written := service.save_game(slot,state(0))
			ok = written.ok
			if not ok: printerr(written)
		"crash":
			service.fault_point=args[3]
			service.on_injected_fault = func(point):
				var hit := FileAccess.open(args[0].path_join(slot+"-"+point+".hit"),FileAccess.WRITE)
				hit.store_line(point)
				hit.close()
				OS.kill(OS.get_process_id())
			var written := service.commit_critical(slot,state(1),"battle-A")
			printerr("Did not reach crash boundary ",args[3]," ",written)
		"read":
			var loaded := service.load_game(slot,CONTENT)
			var recovered := service.recover(slot)
			var expected := args[3].to_int()
			ok=loaded.ok and loaded.value==state(expected) and recovered.ok and recovered.value.applied_results.size()==expected
			if not ok: printerr("Unexpected recovered state ",loaded)
		"race":
			var contender := args[4]
			var ready := FileAccess.open(args[0].path_join("ready-"+contender),FileAccess.WRITE)
			ready.close()
			var deadline := Time.get_ticks_msec()+10000
			while not FileAccess.file_exists(args[0].path_join("race.go")) and Time.get_ticks_msec()<deadline:
				OS.delay_msec(5)
			var won := service.save_game(slot,state(contender.to_int()),"manual",args[3])
			var done := FileAccess.open(args[0].path_join("done-"+contender),FileAccess.WRITE)
			done.store_string("ok" if won.ok else won.error.code)
			done.close()
			ok=true
		"retry":
			var previous := service.recover(slot)
			var result := service.commit_critical(slot,state(1),"battle-A")
			var again := Store.new(args[0]).commit_critical(slot,state(1),"battle-A")
			ok=result.ok and again.ok and result.value==again.value and previous.ok
			if ok and previous.value.applied_results.has("battle-A"):
				ok=previous.value.manifest.commit_id==result.value.commit_id
			if not ok: printerr(result," ",again)
	print("PERSIST_WORKER ",action," ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
