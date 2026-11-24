extends SceneTree
const Store = preload("res://infrastructure/persistence/save_service.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const Inv = preload("res://shared/inventory/inventory.gd")
const F = preload("res://tests/p1/application/fixture.gd")
const C = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const Book = preload("res://application/receipt_book.gd")
var failures := 0
var store: RefCounted
var adapter: RefCounted
var network_calls := 0

func _initialize() -> void:
	run.call_deferred()

func expect(value: bool, title: String) -> void:
	if not value:
		printerr("FAIL ",title)
		failures+=1

func group(id: String, before: int) -> void:
	print(id," PASS" if before==failures else " FAIL")

func new_session() -> RefCounted:
	return F.make_session(root,store,adapter,func(_result): network_calls+=1; return R.ok())

func funds(slot: String) -> Array:
	var saved: Dictionary=store.recover(slot)
	if not saved.ok:
		return []
	var inv:=Inv.new()
	if not inv.restore(saved.value.snapshot.campaign.inventory).ok:
		return []
	return [inv.balance("purse").value,inv.balance("pool").value]

func play(app: RefCounted, mode: String) -> Dictionary:
	var revision:=1
	if mode=="campaign":
		revision=app.query("campaign").value.revision+1
	var prepared: Dictionary=app.prepare_mission(F.spec(mode,revision),F.SCENE,F.RULE)
	expect(prepared.ok,"prepare "+mode+" "+str(prepared))
	if not prepared.ok: return {}
	expect(app.step_fixed(1,[]).ok,"real fixed tick")
	var result: Dictionary=app.finish_mission({"outcome":"withdrawn"})
	expect(result.ok,"real finalize "+str(result))
	return result.value if result.ok else {}

func transaction(point: String) -> void:
	var slot := point
	var app:=new_session()
	expect(app.start_session("sandbox",F.options(slot)).ok,"create "+slot)
	var world: Dictionary=app.query("campaign").value
	var cmd:=F.command(world,"trade")
	var rejected: Dictionary=app.dispatch(cmd,"not-authenticated")
	expect(not rejected.ok,"authorization required")
	var committed: Dictionary=app.dispatch(cmd,"local-token")
	expect(committed.ok and app.dispatch(cmd,"local-token")==committed,"replay precedes stale revision")
	cmd.payload.lines[0].amount=5
	expect(app.dispatch(cmd,"local-token").error.code=="Conflict","same ID different command")
	cmd.payload.lines[0].src="pool"
	expect(app.dispatch(cmd,"local-token").error.code=="Unauthorized","replay never bypasses actor grant")
	var result:=play(app,"campaign")
	expect(not result.is_empty() and not app.dispose_mission().ok,"unfinished settlement protected")
	if result.is_empty():
		app.close_session()
		return
	var checked: Dictionary=store.recover(slot)
	expect(checked.value.snapshot.session.pending.result==result and funds(slot)==[98,1000],"checkpoint then durable pending before reward")
	store.fault_point=point
	var first: Dictionary=app.route_result(result)
	expect(not first.ok,"injected fault "+point)
	store.fault_point=""
	app.close_session()
	app=new_session()
	expect(app.load_session(slot,F.CONTENT).ok,"cold game session")
	var current: Dictionary=app.query("session").value
	if point=="after_marker":
		expect(current.state=="CampaignMap" and funds(slot)==[105,993],"new marker already awarded")
	else:
		expect(current.state=="Results" and funds(slot)==[98,1000],"old marker preserves pending outcome")
	var replay: Dictionary=app.route_result(result)
	expect(replay.ok and replay==app.route_result(result),"same result returns original receipt "+str(replay))
	var changed:=result.duplicate(true)
	changed.erase("integrity_hash")
	changed.stats["extra"]=1
	changed["integrity_hash"]=C.hash_value(changed).value
	expect(app.route_result(changed).error.code=="Conflict","different content with same result id")
	expect(funds(slot)==[105,993],"exactly once award/transfer")
	var final: Dictionary=store.recover(slot).value.snapshot
	expect(final.session.commands.size()==1 and final.session.results.size()==1 and final.session.pending==null,"one command and one settlement persisted atomically")
	app.close_session()

func run() -> void:
	store=Store.new(ProjectSettings.globalize_path("user://app-"+Crypto.new().generate_random_bytes(8).hex_encode()))
	adapter=Adapter.new(root,true)
	var before:=failures
	for point in ["before_write","before_marker","after_marker"]:
		transaction(point)
	group("T-APP-01 / AT-10-SLICE",before)
	before=failures
	var app:=new_session()
	expect(app.load_session("after_marker",F.CONTENT).ok,"load previous campaign before custom")
	var disk: Dictionary=store.recover("after_marker").value
	var hash_value:=C.hash_value(disk.snapshot).value as String
	for mode in ["custom","multiplayer"]:
		var result:=play(app,mode)
		if result.is_empty(): continue
		expect(result.encounter_id==null and app.route_result(result).ok and app.route_result(result).ok,"alternate result routed")
		expect(not app.dispatch(F.command({"world_id":"foreign","revision":0},"bad"),"local-token").ok,"no campaign commands")
		expect(app.dispose_mission().ok,"alternate release")
		expect(app.query().value.state=="CampaignMap" and C.hash_value(store.recover("after_marker").value.snapshot).value==hash_value,"no campaign writes")
	expect(network_calls==1,"authenticated match sink once")
	group("T-APP-02",before)
	before=failures
	var old: Dictionary=app.query("campaign").value
	var bad_scene := {"id":F.SCENE.id,"simulation_scene":"res://does-not-exist.tscn"}
	expect(not app.prepare_mission(F.spec("campaign",old.revision+1),bad_scene,F.RULE).ok,"scene failure")
	expect(app.query().value.state=="CampaignMap" and app.query("campaign").value==old,"freeze rolled back")
	expect(adapter.counts()=={"scopes":0,"requests":0,"leases":0},"all resources released")
	expect(store.recover("after_marker").value.snapshot.session.pending==null,"checkpoint reservation released durably")
	var recovered_campaign := new_session()
	expect(recovered_campaign.start_session("sandbox",F.options("pending-outcome")).ok,"open pending outcome")
	var wanted:=F.spec("campaign",recovered_campaign.query("campaign").value.revision+1)
	expect(recovered_campaign.prepare_mission(wanted,F.SCENE,F.RULE).ok,"open actual arena")
	store.fault_point="before_marker"
	expect(not recovered_campaign.finish_mission({"outcome":"withdrawn"}).ok,"fail durable recording after actual finalize")
	expect(recovered_campaign.query().value.state=="Recovery" and not recovered_campaign.dispose_mission().ok and not recovered_campaign.close_session().ok,"retain finalized outcome despite dispose or close")
	store.fault_point=""
	var recorded: Dictionary=recovered_campaign.finish_mission({"outcome":"withdrawn"})
	expect(recorded.ok and recovered_campaign.close_session().ok,"replay finalize and persist before close")
	recovered_campaign=new_session()
	expect(recovered_campaign.load_session("pending-outcome",F.CONTENT).ok and recovered_campaign.query().value.state=="Results","cold recovery has original pending result")
	expect(recovered_campaign.route_result(recorded.value).ok and funds("pending-outcome")==[107,993],"award recorded outcome once")
	recovered_campaign.close_session()
	var count: Array=[0]
	var missing_once:=func():
		count[0]+=1
		return null if count[0]==1 else F.Camp.new()
	var recoverable:=F.App.new(store,missing_once,Callable(),Callable())
	expect(not recoverable.start_session("sandbox",F.options("factory")).ok and recoverable.query().value.state=="Frontend","unavailable campaign factory leaves clean retry")
	expect(recoverable.start_session("sandbox",F.options("factory")).ok and recoverable.close_session().ok,"same session retries creation")
	count[0]=0
	expect(not recoverable.load_session("factory",F.CONTENT).ok and recoverable.query().value.state=="Frontend","missing load factory resets phase")
	expect(recoverable.load_session("factory",F.CONTENT).ok and recoverable.close_session().ok,"same session retries load")
	var no_builder:=func(mode: String): return F.Mission.new(F.Core.new(),adapter,mode)
	var unavailable:=F.App.new(store,func(): return F.Camp.new(),no_builder,F.authorize)
	expect(unavailable.start_session("sandbox",F.options("no-builder")).ok,"no-builder baseline")
	for teardown in ["dispose","close"]:
		var unused: Dictionary=unavailable.query("campaign").value
		expect(unavailable.prepare_mission(F.spec("campaign",unused.revision+1),F.SCENE,F.RULE).ok,"real scope for no-builder case")
		var unavailable_result:=unavailable.finish_mission({"outcome":"withdrawn"})
		expect(not unavailable_result.ok and unavailable_result.error.code=="Unavailable","no authoritative result produced")
		var cleanup:=unavailable.dispose_mission() if teardown=="dispose" else unavailable.close_session()
		expect(cleanup.ok and adapter.counts()=={"scopes":0,"requests":0,"leases":0},"release without result "+teardown)
	expect(unavailable.load_session("no-builder",F.CONTENT).ok and unavailable.query().value.state=="CampaignMap","abandoned checkpoint cold recovery")
	unavailable.close_session()
	group("T-APP-03",before)
	app.close_session()
	before=failures
	for mode in ["story","sandbox"]:
		app=new_session()
		expect(app.start_session(mode,F.options(mode)).ok,"launch "+mode)
		var view: Dictionary=app.query().value
		expect(view.state=="CampaignMap" and view.rules.campaign and view.rules.main_story==(mode=="story"),"registered "+mode+" rules")
		app.close_session()
	group("T-APP-04-SLICE",before)
	print("APP_CHECKS errors=",failures)
	quit(1 if failures else 0)
