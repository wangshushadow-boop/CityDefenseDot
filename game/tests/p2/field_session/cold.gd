extends "res://tests/p2/results/run.gd"

const Inventory = preload("res://shared/inventory/inventory.gd")
const SLOT := "resume-field"

func recovery_authority(context: Variant, op: String, request: Dictionary) -> Dictionary:
	if is_same(context,login) and op=="session.pending_result" and request.scope_id.begins_with("session/"):
		return R.ok("owner")
	return R.fail("Unauthorized","owner")

func award(_spec: Dictionary,_result: Dictionary) -> Dictionary:
	settlement_calls+=1
	return R.ok([F.line("pool","purse",7)])

func check_saved(pending: bool, purse: int, receipts: int) -> void:
	var snapshot: Dictionary=durable.recover(SLOT).value.snapshot
	var inventory:=Inventory.new()
	require(inventory.restore(snapshot.campaign.inventory),"read saved inventory")
	check(inventory.balance("purse").value==purse and inventory.balance("pool").value==1100-purse,"conserved transfer")
	check((snapshot.session.pending!=null)==pending and snapshot.session.results.size()==receipts,"pending checkpoint and durable receipts")
	check((snapshot.campaign.freeze!=null)==pending,"campaign freeze follows settlement")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:
		quit(2);return
	durable=Store.new(args[1])
	core=Core.new("1234567890abcdef")
	engine=Adapter.new(root,true)
	var app:=F.App.new(durable,func():return F.Camp.new(),fresh,recovery_authority,award)
	match args[0]:
		"write":
			require(app.start_session("sandbox",F.options(SLOT)),"start campaign")
			if not await start_field(battle("campaign"),100,app):
				quit(1);return
			require(app.step_fixed(1,[]),"open field")
			require(rules.request_withdrawal(0,login),"team zero leaves")
			require(rules.request_withdrawal(2,login),"team two leaves")
			require(app.step_fixed(2,[]),"RULES confirms winner")
			require(app.finish_mission(rules.view().outcome),"save pending outcome")
			check_saved(true,100,0)
		"recover":
			require(app.load_session(SLOT,F.CONTENT),"load using only slot and installed content")
			check(app.query().value.state=="Results" and not app.query("mission").ok,"no live Mission in new process")
			var before: int=durable.recover(SLOT).value.snapshot.revision
			check(not app.query("pending_result",{"context":RefCounted.new()}).ok,"foreign reader cannot obtain pending result")
			var recovered: Dictionary=app.query("pending_result",{"context":login})
			if not require(recovered,"owner reads persisted result"):
				quit(1);return
			check(recovered.value.is_read_only() and recovered.value.slot_outcomes.is_read_only(),"recovery view is immutable")
			var receipt: Dictionary=app.route_result(recovered.value)
			check(receipt.ok and app.route_result(recovered.value)==receipt and settlement_calls==1,"stored result routes and replays once")
			check(not app.query("pending_result",{"context":login}).ok,"settled checkpoint is no longer visible")
			var saved: Dictionary=durable.recover(SLOT).value.snapshot
			check(saved.revision==before+1,"one durable revision")
			check_saved(false,107,1)
			require(app.dispose_mission(),"resume campaign map")
		"verify":
			require(app.load_session(SLOT,F.CONTENT),"load settled campaign in third process")
			check(app.query().value.state=="CampaignMap" and not app.query("pending_result",{"context":login}).ok and settlement_calls==0,"no pending work after restart")
			check_saved(false,107,1)
		_:
			quit(2);return
	require(app.close_session(),"clean shutdown")
	print("COLD_FIELD ",args[0]," pid=",OS.get_process_id()," checks=",checks," failures=",failed)
	quit(0 if failed==0 else 1)
