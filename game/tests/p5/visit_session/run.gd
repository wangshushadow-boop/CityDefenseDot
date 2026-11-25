extends "res://tests/p3/session_character/run.gd"

func exercise() -> void:
	var slot := "visit"
	store = Store.new("user://visit-session-"+str(OS.get_process_id()))
	app = App.new(store,func():return Camp.new(),func(_mode):return null,authorize)
	if not check(app.start_session("sandbox",F.options(slot)).ok,"create actual session"): return
	bind_current()
	if not check(app.dispatch(command("create","create",{}),player).ok and app.dispatch(command("open","governor_open",{}),player).ok,"establish family estate"): return
	var m: Dictionary=query_character().value
	var person := {"hero_id":m.heirs[0].id,"settlement_id":m.governance.settlement_id}
	if not check(app.dispatch(command("appoint","governor_assign",person),player).ok,"real serving governor"): return
	var offer := command("accept","visit_accept",person)
	check(not app.dispatch(offer,referee).ok,"officer cannot impersonate visitor")
	var prior: Dictionary=store.recover(slot).value.snapshot
	store.fault_point="before_marker"
	check(not app.dispatch(offer,player).ok and store.recover(slot).value.snapshot==prior,"uncommitted acceptance leaves old physical slot intact")
	store.fault_point=""
	var accepted: Dictionary=app.dispatch(offer,player)
	if not check(accepted.ok and app.dispatch(offer,player)==accepted,"acceptance replay returns exact receipt"): return
	check(not app.dispatch(command("too-soon","visit_report",person),player).ok,"no reply without a daybook")
	if not check(app.dispatch(command("rest","rest",{}),player).ok,"advance a real campaign day"): return
	var v: Dictionary=query_character().value.visit
	var reply := person.duplicate()
	reply["answer"]=v.ledger.prosperity_after-v.ledger.prosperity_before
	if not check(app.dispatch(command("return","visit_report",reply),player).ok,"governor signs the real result"): return
	var claim:=command("fee","visit_claim",{})
	var signed: Dictionary=query_character().value
	store.fault_point="before_marker"
	check(not app.dispatch(claim,player).ok and query_character().value==signed,"failed write leaves task and skill untouched")
	store.fault_point="after_marker"
	check(not app.dispatch(claim,player).ok,"lost acknowledgement reported")
	store.fault_point=""
	var paid: Dictionary=query_character().value
	check(paid.visit.rewarded and paid.hero.skills.stewardship!=signed.hero.skills.stewardship,"both claim and learning survived one commit")
	var ack: Dictionary=app.dispatch(claim,player)
	check(ack.ok and query_character().value==paid,"lost ACK retried without another reward")
	if not reopen(slot): return
	check(app.dispatch(claim,player)==ack and query_character().value==paid,"real disk reopen reproduces original claim")
	check(not app.dispatch(command("second","visit_claim",{}),player).ok,"second ID cannot claim again")

func _initialize() -> void:
	exercise()
	print("VISIT_SESSION checks=%d failures=%d" % [checks,failures])
	quit(int(failures!=0))
