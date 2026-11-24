extends SceneTree
const Runtime = preload("res://core/runtime.gd")
const Canonical = preload("res://contracts/canonical.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--seed")
	var seed := 241124
	if index >= 0:
		if index + 1 >= args.size() or not args[index + 1].is_valid_int():
			print("P1-HARNESS FAIL invalid seed")
			quit(1)
			return
		seed = args[index + 1].to_int()
	var runtime := Runtime.new("%016x" % seed)
	runtime.open_scope("fixture")
	var stream := runtime.derive_rng("fixture","property")
	var starting := stream.snapshot()
	var trace := []
	for i in 64:
		trace.append(stream.next_u32())
	stream.restore(starting)
	for expected in trace:
		if stream.next_u32() != expected:
			print("P1-HARNESS FAIL seed ", seed)
			quit(1)
			return
	print("P1-HARNESS PASS seed=",seed," draws=64 digest=",Canonical.hash_value(trace).value)
	quit(0)
