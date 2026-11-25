extends "res://tests/p3/session_character/run.gd"

func exercise() -> void:
	var slot := "governor"
	store = Store.new("user://governor-session-"+str(OS.get_process_id()))
	app = App.new(store,func(): return Camp.new(),func(_mode): return null,authorize)
	if not check(app.start_session("sandbox",F.options(slot)).ok,"start actual disk-backed sandbox"): return
	bind_current()
	check(not app.dispatch(command("premature","governor_open",{}),player).ok,"requires existing household")
	if not check(app.dispatch(command("create","create",{}),player).ok,"existing character entry"): return
	var open := command("open","governor_open",{})
	check(not app.dispatch(open,referee).ok,"referee cannot appoint")
	var bad := open.duplicate(true)
	bad.scope_id = "world/elsewhere"
	check(not app.dispatch(bad,player).ok,"different world refused")
	var initial: Dictionary = store.recover(slot).value.snapshot
	store.fault_point = "before_marker"
	check(not app.dispatch(open,player).ok and not query_character().value.governance.established,"failed open unpublished")
	check(store.recover(slot).value.snapshot==initial,"failed open preserves the actual previous save")
	store.fault_point = ""
	var receipt: Dictionary = app.dispatch(open,player)
	if not check(receipt.ok and app.dispatch(open,player)==receipt,"open is replayable"): return
	var model: Dictionary = query_character().value
	var governor: String = model.heirs[0].id
	var choose := command("assign","governor_assign",{"settlement_id":model.governance.settlement_id,"hero_id":governor})
	store.fault_point = "after_marker"
	var ack: Dictionary = app.dispatch(choose,player)
	store.fault_point = ""
	# Save service reconciles ambiguous completion from durable data; retry returns the exact recorded revision.
	check(query_character().value.governance.governor_id==governor, "durable appointment after marker")
	var replay: Dictionary = app.dispatch(choose,player)
	check(replay.ok and (not ack.ok or ack==replay), "acknowledged assignment replay")
	var changed := choose.duplicate(true)
	changed.payload.args.hero_id = model.player_id
	check(app.dispatch(changed,player).error.code=="Conflict","same ID different appointment refused")
	var before: Dictionary = query_character().value
	var advance := command("next","rest",{})
	store.fault_point = "before_marker"
	check(not app.dispatch(advance,player).ok and query_character().value==before, "failed day publishes no governance or character changes")
	store.fault_point = ""
	if not check(app.dispatch(advance,player).ok,"normal day reaches governance"): return
	var after: Dictionary = query_character().value
	check(after.governance.last_report==before.governance.next_report,"preview equals realized daily report")
	if not reopen(slot): return
	check(query_character().value==after and app.dispatch(choose,player)==replay,"cold restart preserves governance and prior receipt")
	check(not app.dispatch(command("forged","governor_assign",{"settlement_id":after.governance.settlement_id,"hero_id":governor,"leadership":999}),player).ok,"client cannot write officer skills")

func _initialize() -> void:
	exercise()
	print("GOVERNOR_SESSION checks=%d failures=%d" % [checks,failures])
	quit(int(failures!=0))
