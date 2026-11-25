extends SceneTree
## Runs against the archived 650adc4 game to generate a real pre-character campaign save.
const F = preload("res://tests/p1/application/fixture.gd")
const Store = preload("res://infrastructure/persistence/save_service.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var store := Store.new(args[0])
	var session = F.make_session(root, store)
	var started: Dictionary = session.start_session("sandbox", F.options("legacy"))
	var traded: bool = started.ok and session.dispatch(F.command(session.query("campaign").value, "old-trade"), "local-token").ok
	var saved := store.recover("legacy")
	var clean: bool = traded and saved.ok and not saved.value.snapshot.campaign.has("characters") and session.close_session().ok
	print("LEGACY_CHARACTER_FIXTURE ", "PASS" if clean else "FAIL")
	quit(int(not clean))
