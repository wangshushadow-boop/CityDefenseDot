extends SceneTree
const App = preload("res://application/game_session.gd")
const F = preload("res://tests/p1/application/fixture.gd")
const Camp = preload("res://campaign/runtime.gd")
const Store = preload("res://infrastructure/persistence/save_service.gd")
const Inv = preload("res://shared/inventory/inventory.gd")
const R = preload("res://contracts/result.gd")
const Canon = preload("res://contracts/canonical.gd")

var checks := 0
var failures := 0
var app: RefCounted
var store: RefCounted
var scope := ""
var session_id := ""
var player := RefCounted.new()
var referee := RefCounted.new()

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ",label)
	return condition

func authorize(token: Variant, op: String, request: Dictionary) -> Dictionary:
	if request.get("scope_id") != scope or request.get("session_id") != session_id:
		return R.fail("Unauthorized", "session")
	if is_same(token, player):
		return R.ok("player") # Attempting to use this overly broad issuer for outcome must still fail.
	if is_same(token, referee) and op == "character.outcome":
		return R.ok("character.authority")
	return R.fail("Unauthorized", "identity")

func query_character() -> Dictionary:
	return app.query("character", {"context":player})

func command(id: String, op: String, args: Dictionary, actor: String = "player") -> Dictionary:
	return {"command_id":id, "expected_revision":app.query("campaign").value.revision, "issued_tick":null,
		"sequence":null, "scope_id":scope, "actor_ref":actor, "payload":{"type":"character."+op, "args":args}}

func bind_current() -> void:
	scope = app.query("campaign").value.world_id
	session_id = app.query().value.session_id
	player = RefCounted.new()

func reopen(slot: String) -> bool:
	if not check(app.close_session().ok and app.load_session(slot, F.CONTENT).ok, "close and load actual saved world"):
		return false
	bind_current()
	return true

func exercise() -> void:
	var args := OS.get_cmdline_user_args()
	var using_legacy := args.size() == 1
	var slot := "legacy" if using_legacy else "new"
	store = Store.new(args[0] if using_legacy else "user://character-"+str(OS.get_process_id()))
	app = App.new(store, func(): return Camp.new(), func(_mode): return null, authorize)
	var loaded: Dictionary = app.load_session(slot,F.CONTENT) if using_legacy else app.start_session("sandbox", F.options(slot))
	if not check(loaded.ok, "load existing old world or start fresh"):
		return
	bind_current()
	check(not app.query("character", {}).ok and not app.query("character", {"context":referee}).ok, "owner-only read projection")
	var empty: Dictionary = query_character()
	if not check(empty.ok and empty.value.hero == null and empty.value.world_id == scope, "uncreated hero in existing world"):
		return
	check(Canon.encode(empty.value).ok, "empty character screen is a canonical read model")
	var old: Dictionary = store.recover(slot).value.snapshot
	check(not old.campaign.has("characters"), "legacy campaign keeps old save shape")
	var create := command("actor-create", "create", {})
	var stale := create.duplicate(true)
	stale.expected_revision = null
	check(not app.dispatch(stale,player).ok, "unspecified character revision refused")
	stale.scope_id = "world/other"
	check(not app.dispatch(stale,player).ok, "foreign world refused")
	check(not app.dispatch(create,referee).ok, "unauthorised creation")
	store.fault_point = "before_marker"
	check(not app.dispatch(create,player).ok and query_character().value.hero == null, "pre-marker IO fault publishes no hero or gear")
	check(store.recover(slot).value.snapshot == old, "recover previous save")
	store.fault_point = ""
	var receipt: Dictionary = app.dispatch(create,player)
	if not check(receipt.ok, "create after failed durable write"):
		return
	check(app.dispatch(create,player) == receipt, "duplicate creation returns exact receipt")
	var changed := create.duplicate(true)
	changed.payload.args = {"name":"different"}
	check(app.dispatch(changed,player).error.code == "Conflict", "conflicting replay refused")
	var model: Dictionary = query_character().value
	check(Canon.encode(model).ok, "created hero, equipment and exercises are canonical data")
	var hero: String = model.hero.id
	var dup := F.spec("campaign", app.query("campaign").value.revision + 1)
	dup.reserved_sources[0].hero_id = hero
	dup.reserved_sources[0].troop_def_id = null
	var another: Dictionary = dup.reserved_sources[0].duplicate(true)
	another.source_slot_range = [2,3]
	dup.reserved_sources.append(another)
	var prior := app.query("campaign").value as Dictionary
	var twice: Dictionary = app.prepare_mission(dup,F.SCENE,F.RULE)
	check(not twice.ok and twice.error.field == "reserved_sources.hero_id" and app.query("campaign").value == prior, "duplicate hero on distinct source slots refused before checkpoint")
	var stale_token := player
	if not reopen(slot):
		return
	check(not app.query("character", {"context":stale_token}).ok and query_character().value.hero.id == hero and app.dispatch(create, player) == receipt, "fresh token and persisted receipt")
	var world := app.query("campaign").value as Dictionary
	var blocked := {"hero_id":hero, "source":"mission/test-hit", "kind":"wound", "severity":40}
	var hurt := command("outcome", "outcome", blocked, "character.authority")
	check(not app.dispatch(hurt,player).ok, "player cannot administer battle outcomes")
	var escalation := hurt.duplicate(true)
	escalation.actor_ref = "player"
	check(not app.dispatch(escalation,player).ok, "outcome requires trusted authoritative role")
	if not check(app.dispatch(hurt,referee).ok and query_character().value.hero.wounds == 40, "trusted authority applies legitimate injury"):
		return
	var spec := F.spec("campaign", app.query("campaign").value.revision + 1)
	spec.reserved_sources[0].hero_id = hero
	spec.reserved_sources[0].troop_def_id = null
	var denied: Dictionary = app.prepare_mission(spec,F.SCENE,F.RULE)
	check(not denied.ok and denied.error.field == "character.deployment" and app.query().value.state == "CampaignMap", "wounded hero denied before battle reservation")
	var same_fact := command("outcome-retry", "outcome", blocked, "character.authority")
	check(app.dispatch(same_fact,referee).ok and query_character().value.hero.wounds == 40, "separate command ID reusing same source cannot wound twice")
	var rest := command("actor-rest", "rest", {})
	store.fault_point = "after_marker"
	check(not app.dispatch(rest,player).ok, "post-marker loss is signalled to caller")
	store.fault_point = ""
	var healed: Dictionary = query_character().value
	check(healed.game_minute == world.game_minute+1440 and healed.hero.wounds < 40, "committed hero and clock recover in memory after ambiguous ACK")
	var rr: Dictionary = app.dispatch(rest,player)
	check(rr.ok and rr.value.committed_revision == healed.revision and query_character().value == healed, "ACK retry cannot advance extra day")
	if not reopen(slot):
		return
	check(query_character().value == healed and app.dispatch(rest,player) == rr, "cold rest and receipt match original")
	var disk: Dictionary = store.recover(slot).value.snapshot
	var old_inv := Inv.new()
	var new_inv := Inv.new()
	check(old_inv.restore(old.campaign.inventory).ok and new_inv.restore(disk.campaign.inventory).ok and old_inv.balance("purse") == new_inv.balance("purse"), "pre-character stock and balance preserved")
	for key in old.session.commands:
		check(old.session.commands[key] == disk.session.commands.get(key), "old trade receipt preserved")
	if using_legacy:
		check(old.session.commands.size() == 1 and new_inv.balance("purse").value == 98, "archived build actually traded before character upgrade")

func _initialize() -> void:
	exercise()
	print("SESSION_CHARACTER checks=%d failures=%d" % [checks, failures])
	quit(int(failures != 0))
