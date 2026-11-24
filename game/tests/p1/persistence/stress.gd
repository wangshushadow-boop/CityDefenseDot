extends SceneTree
const Store = preload("res://infrastructure/persistence/save_service.gd")
const F = preload("res://tests/p1/persistence/worker.gd")

func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("user://p1-save-stress-"+Crypto.new().generate_random_bytes(6).hex_encode())
	var timings := []
	for i in 50:
		var snapshot := F.state(i)
		var start := Time.get_ticks_usec()
		var receipt := Store.new(dir).save_game("loop",snapshot)
		var loaded := Store.new(dir).load_game("loop",F.CONTENT)
		timings.append((Time.get_ticks_usec()-start)/1000)
		if not receipt.ok or not loaded.ok or loaded.value!=snapshot:
			printerr("FAIL save/reopen cycle ",i)
			quit(1)
			return
	timings.sort()
	print("PERSIST_50_SAVE_REOPENS PASS p95_ms=",timings[47]," max_ms=",timings[49])
	quit(0)
