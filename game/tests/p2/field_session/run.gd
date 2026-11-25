extends "res://tests/p2/results/run.gd"

const Form = preload("res://mission/formation/ports/field_formation.gd")
var app: RefCounted
var form: RefCounted
var other := RefCounted.new()
var calls := {}
var admitted := {}
var sampled := {}
var retry_view := false

func authorize(context: Variant, operation: String, _command: Dictionary) -> Dictionary:
	if operation.begins_with("field."):
		if is_same(context,login):
			return R.ok("player")
		if is_same(context,other):
			return R.ok("visitor")
	return R.fail("Unauthorized","principal")

func field_gateway(op: String, payload: Dictionary, context: Variant) -> Dictionary:
	calls[op] = calls.get(op,0)+1
	if payload.scope_id != scope or not is_same(context,login):
		return R.fail("Unauthorized","scope")
	var live: Dictionary=mission.view()
	if op=="field.view":
		if retry_view:
			check(not app.dispatch(command("recursive",{"type":"field.withdraw"}),login).ok,"query callback cannot mutate Session")
		return R.ok({"scope_id":scope,"revision":live.tick,"projection":payload.projection})
	if payload.revision!=live.tick:
		return R.fail("StaleVersion","revision")
	match op:
		"field.input":
			if payload.batch.source_tick!=live.tick+1 or payload.batch.control_revision!=0 or not payload.batch.inputs.all(func(i):return i.actor_handle=={"index":0,"generation":1}):
				return R.fail("Unauthorized","input")
			admitted=payload.batch
			return R.ok()
		"field.order":
			return form.issue_order(payload.order,context,payload.get("revisions",0))
		"field.withdraw":
			return rules.request_withdrawal(0,context)
		"field.downed":
			return rules.request_downed_mode(0,payload.mode,context)
		"field.deploy":
			return mission.apply_deployment(payload.placements)
	return R.fail("NotFound","operation")

func command(id: String, payload: Dictionary) -> Dictionary:
	return {"command_id":id,"scope_id":scope,"actor_ref":"player","expected_revision":mission.view().tick,
		"issued_tick":null,"sequence":null,"payload":payload}

func queue_input(_context: Dictionary, batch: Dictionary) -> Dictionary:
	if not admitted.is_empty():
		if batch.source_tick!=admitted.source_tick:
			return R.fail("Conflict","fixture.stale_input")
		sampled=admitted
	return R.ok()

func new_app() -> RefCounted:
	return F.App.new(durable,func():return F.Camp.new(),fresh,authorize,func(_s,_r):return R.ok([]),
		func(_r):network_receipts+=1;return R.ok(),field_gateway)

func run() -> void:
	core=Core.new("1234567890abcdef")
	engine=Adapter.new(root,true)
	durable=Store.new(ProjectSettings.globalize_path("user://field-session-"+Crypto.new().generate_random_bytes(8).hex_encode()))
	app=new_app()
	if not require(app.start_session("sandbox",F.options("field-campaign")),"start campaign"):
		quit(1); return
	if not await start_field(battle("campaign"),100,app):
		quit(1); return
	form=Form.new(scope,func(ctx):return authorize(ctx,"field.order",{}),func(_i,_p):return true)
	require(form.add_formation(0,0,"player",[{"index":0,"generation":1}]),"real owned FORM")
	require(mission.register_system("input",{"id":"fixture.input","run":queue_input,
		"commit":func():admitted={},"rollback":func():sampled={}}),"register input probe")
	retry_view=true
	for projection in ["hud","visual","camera","input"]:
		var q: Dictionary=app.query("field",{"context":login,"projection":projection})
		check(q.ok and q.value.projection==projection and q.value.scope_id==scope,"projection "+projection)
	retry_view=false
	check(not app.query("field",{"context":RefCounted.new(),"projection":"hud"}).ok,"unknown token")
	check(not app.query("field",{"context":other,"projection":"hud"}).ok,"trusted gateway visibility rejects visitor")
	check(not app.query("field",{"context":login,"projection":"all"}).ok,"unknown projection")
	var act := {"actor_handle":{"index":0,"generation":1},"desired_direction":[1000000,0,0],"speed_fraction":0.625,"stance":"walk"}
	var batch := {"mission_id":scope,"source_tick":1,"control_revision":0,"inputs":[act]}
	var move:=command("walk",{"type":"field.input","batch":batch})
	var invalid: Dictionary=move.duplicate(true)
	invalid.payload.batch.inputs[0].actor_handle.index=1
	check(not app.dispatch(invalid,login).ok,"gateway enforces actor binding")
	check(not app.step_fixed(1,[act]).ok and mission.view().tick==0,"unchecked direct inputs rejected")
	var accepted: Dictionary=app.dispatch(move,login)
	check(accepted.ok and S.validate_shape("CommandReceipt",accepted.value).ok and admitted.inputs[0].speed_fraction==0.625,"native fractional control admitted")
	var visits: int=calls["field.input"]
	var wire_move:=move.duplicate(true)
	wire_move.payload.batch.inputs[0].speed_fraction=625000
	check(app.dispatch(wire_move,login)==accepted and calls["field.input"]==visits,"canonical fixed-point input replays native receipt")
	var bad_wire:=wire_move.duplicate(true)
	bad_wire.payload.batch.inputs[0].speed_fraction=1000001
	check(not app.dispatch(bad_wire,login).ok,"out-of-range wire fraction")
	check(app.dispatch(move,login)==accepted and calls["field.input"]==visits,"replay idempotent")
	check(not app.dispatch(move,other).ok,"same command denied under other credential")
	invalid=move.duplicate(true)
	invalid.actor_ref="visitor"
	check(not app.dispatch(invalid,other).ok,"same ID under changed actor conflicts")
	invalid=move.duplicate(true)
	invalid.payload.batch.inputs[0].speed_fraction=0.125
	check(not app.dispatch(invalid,login).ok,"changed content conflicts")
	invalid=move.duplicate(true)
	invalid.scope_id="foreign"
	check(not app.dispatch(invalid,login).ok,"scope mismatch")
	var order := {"mission_id":scope,"issuer_id":"player","order_id":"hold-1","client_sequence":1,"issued_tick":1,
		"formation_ids":[0],"order_type":"hold","target_position":null,"target_formation_id":null,"parameters":{}}
	var order_cmd:=command("formation",{"type":"field.order","order":order,"revisions":{0:0}})
	check(app.dispatch(order_cmd,login).ok and form.advance(1).ok and form.view(0).value.active==order,"real formation command with native integer revision key")
	var wire_order:=order_cmd.duplicate(true)
	wire_order.payload.revisions={"0":0}
	var issue_calls:int=calls["field.order"]
	check(app.dispatch(wire_order,login).ok and calls["field.order"]==issue_calls,"canonical formation keys replay native receipt")
	wire_order.payload.revisions={0:0,"0":0}
	check(not app.dispatch(wire_order,login).ok,"ambiguous revision keys rejected")
	var early := {"outcome":"withdrawn","winner_team_keys":["0"],"objective_results":[]}
	check(not app.finish_mission(early).ok and mission.view().phase=="Deployment","early outcome cannot freeze live Mission")
	check(app.dispatch(command("deploy",{"type":"field.deploy","placements":[]}),login).ok,"route deployment to authoritative Mission")
	check(not app.dispatch(command("down",{"type":"field.downed","mode":"delegate"}),login).ok,"RULES rejects downed action during normal control")
	check(app.step_fixed(1,[]).ok and sampled.source_tick==1 and sampled.inputs==[act],"admitted input consumed on normal server step")
	check(app.dispatch(move,login)==accepted,"lost ACK after tick returns exact accepted receipt")
	var stale:=command("new-old",{"type":"field.withdraw"})
	stale.expected_revision=0
	check(not app.dispatch(stale,login).ok,"gateway rejects stale command")
	require(app.dispatch(command("withdraw",{"type":"field.withdraw"}),login),"approved team withdraw")
	require(app.step_fixed(2,[]),"real three-sided field keeps going")
	check(rules.view().outcome==null,"remaining two sides continue")
	require(rules.request_withdrawal(2,login),"third side leaves")
	require(app.step_fixed(3,[]),"rules publish real winner")
	var decision: Dictionary=rules.view().outcome
	var wrong:=decision.duplicate(true)
	wrong.winner_team_keys=[0]
	check(decision.winner_team_keys==["0"] and not app.finish_mission(wrong).ok and mission.view().phase=="Running","typed winner cannot be substituted")
	durable.fault_point="before_marker"
	check(not app.finish_mission(decision).ok and app.query().value.state=="Recovery","failed save retains immutable result")
	check(not app.finish_mission(wrong).ok,"recovery rejects wrong typed winner")
	durable.fault_point=""
	var done: Dictionary=app.finish_mission(decision)
	if not require(done,"retry exact outcome"):
		quit(1);return
	check(done.value.winner_team_keys==["0"] and app.finish_mission(done.value)==done,"full result retry")
	check(not app.finish_mission(wrong).ok and not app.finish_mission({"outcome":decision.outcome}).ok,"results rejects wrong/partial decision")
	require(app.close_session(),"close pending durable battle")
	app=new_app()
	require(app.load_session("field-campaign",F.CONTENT),"cold field result recovery")
	check(app.finish_mission(done.value)==done and not app.finish_mission(wrong).ok,"cold retry verifies stored whole result")
	var altered: Dictionary=done.value.duplicate(true)
	altered.winner_team_keys=[0]
	check(not app.finish_mission(altered).ok and not app.route_result(altered).ok,"changed typed winner with original digest rejected")
	var forged:=rehash(altered)
	check(not app.finish_mission(forged).ok and not app.route_result(forged).ok,"changed typed winner with new digest rejected")
	require(app.route_result(done.value),"cold route verified result")
	require(app.dispose_mission(),"return to campaign")
	check(not app.dispatch(move,login).ok and not app.query("field",{"context":login,"projection":"input"}).ok,"released field has no command/view access")
	var old_scope:=scope
	if await start_field(battle("custom"),100,app):
		check(scope!=old_scope and not app.dispatch(move,login).ok,"old scope cannot replay into another live Mission")
		check(app.query("field",{"context":login,"projection":"hud"}).value.scope_id==scope,"fresh scope visible")
		require(app.dispose_mission(),"discard new custom battle")
	require(app.close_session(),"close")
	print("FIELD_SESSION checks=",checks," failures=",failed)
	quit(0 if failed==0 else 1)
