extends SceneTree

const Q = preload("res://campaign/quest/ports/estate_commission.gd")
const C = preload("res://contracts/canonical.gd")
const H := "hero/00000000-0000-4000-8000-000000000001"
const G := "hero/00000000-0000-4000-8000-000000000002"
const FIEF := "settlement/00000000-0000-4000-8000-000000000003"
const TARGET := {"settlement_id":FIEF, "hero_id":G}
var checks := 0
var failures := 0

func ck(ok: bool, label: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
	return ok

func facts(day: int = 7) -> Dictionary:
	return {"world_id":"world/liuxi", "day":day, "player_id":H, "can_visit":true, "settlement_id":FIEF,
		"governor_id":G, "opened_day":1, "last_report":{}, "members":{
			H:{"name":"温知","life_status":"Healthy","appearance":"reed"},
			G:{"name":"石安","life_status":"Healthy","appearance":"pine","stewardship":10,"leadership":4}}}

func ledger(day: int, before := 550, prior_loyalty := 500) -> Dictionary:
	return {"day":day,"governor_id":G, "prosperity_before":before,"prosperity_base":1,"prosperity_bonus":11,
		"prosperity_after":mini(1000,before+12),"loyalty_before":prior_loyalty,
		"loyalty_base":-1,"loyalty_bonus":5,"loyalty_after":prior_loyalty+4}

func submit(state: Dictionary, answer: Variant, f: Dictionary) -> Dictionary:
	var args := TARGET.duplicate()
	args["answer"]=answer
	return Q.plan(state,"visit_report",args,f)

func bad_field(state: Dictionary, key: String, value: Variant, f: Dictionary) -> void:
	var bad:=state.duplicate(true)
	bad[key]=value
	ck(not Q.validate(bad,f).ok,"reject corrupt "+key+" = "+str(value))

func exercise() -> void:
	var f:=facts()
	var offered:=Q.view({},f)
	ck(Q.validate({},f).ok and C.encode(offered).ok and offered.status=="none" and offered.actor_id==null,"legacy optional repository and canonical empty journal")
	ck(offered.speaker=={"id":G,"name":"石安","appearance":"pine"} and offered.can_accept,"actual governor projected")
	ck(Q.reward_source({})=="","empty source")
	ck(not Q.plan({},"visit_report",TARGET,f).ok and not Q.plan({},"visit_claim",{},f).ok,"unaccepted stage")
	var removed:=f.duplicate(true)
	removed.governor_id=null
	ck(Q.view({},removed).speaker==null and not Q.plan({},"visit_accept",TARGET,removed).ok,"vacated office rejects stale dialogue")
	ck(not Q.plan({},"visit_accept",{"settlement_id":FIEF,"hero_id":H},f).ok,"different speaker")
	ck(not Q.plan({},"visit_accept",{"settlement_id":"other","hero_id":G},f).ok,"different estate")
	ck(not Q.plan({},"visit_accept",{"settlement_id":FIEF,"hero_id":G,"xp":99},f).ok,"untrusted field")
	var tomorrow:=f.duplicate(true)
	tomorrow.can_visit=false
	ck(not Q.view({},tomorrow).can_visit and not Q.plan({},"visit_accept",TARGET,tomorrow).ok,"visiting permission enforced")
	var start:=Q.plan({},"visit_accept",TARGET,f)
	if not ck(start.ok,"accept"):return
	var active: Dictionary=start.value
	ck(Q.validate(active,f).ok and active.accepted_day==7 and active.deadline_day==10,"accept pins actor and deadline")
	ck(active.get("ledger_hash")=="","commission has no receipt before first ledger")
	ck(not Q.plan(active,"visit_accept",TARGET,f).ok and not Q.view(active,f).can_report,"already pending")
	ck(Q.reconcile(active,f)==active and Q.reconcile(active,tomorrow)==active,"same day and temporary absence keep commission")
	var no_officer:=Q.reconcile(active,removed)
	ck(no_officer.status=="failed" and not no_officer.reason.is_empty() and Q.validate(no_officer,removed).ok,"issuer lost with recoverable reason")
	ck(not Q.view(no_officer,f).can_accept,"cannot farm new commissions same day")
	var day8:=facts(8)
	day8.last_report=ledger(8,997)
	ck(Q.view(no_officer,day8).can_accept and Q.plan(no_officer,"visit_accept",TARGET,day8).ok,"next day may accept another commission after failure")
	var ready:=Q.reconcile(active,day8)
	ck(active.status=="active" and ready.status=="ready" and Q.validate(ready,day8).ok,"normal first day locks record without altering original")
	ck(ready.get("ledger_hash")==C.hash_value(day8.last_report).value,"first committed ledger stores a canonical receipt")
	var cold: Dictionary=C.decode(C.encode(ready).value).value
	ck(cold==ready and Q.validate(cold,day8).ok,"canonical cold roundtrip")
	var model:=Q.view(ready,day8)
	ck(model.can_report and model.answers.size()==3 and model.answers.has(3) and not model.answers.has(12),"use capped actual increase")
	ck(model.answers[0]!=model.answers[1] and model.answers[1]!=model.answers[2] and model.answers[2]!=model.answers[0],"distinct choices")
	model.ledger.clear()
	model.speaker.name="篡改"
	ck(not ready.ledger.is_empty() and day8.members[G].name=="石安","read model detached")
	ck(not submit(ready,12,day8).ok and submit(ready,12,day8).error.field=="visit.answer","wrong response cannot claim theoretical change")
	ck(not submit(ready,3.0,day8).ok and not submit(ready,true,day8).ok,"canonical integer answer only")
	var day9:=facts(9)
	day9.last_report=ledger(9,1000,504)
	ck(Q.reconcile(ready,day9)==ready and Q.view(ready,day9).answers==Q.view(ready,day8).answers,"later day cannot replace chosen ledger")
	var altered:=ready.duplicate(true)
	altered.ledger.prosperity_before=998
	ck(not Q.validate(altered,day9).ok,"historical edit consistent with cap and following day still breaks original hash")
	var disconnected:=day9.duplicate(true)
	disconnected.last_report=ledger(9,990,504)
	ck(not Q.validate(ready,disconnected).ok,"next day's opening prosperity must match the retained closing balance")
	disconnected.last_report=ledger(9,1000,503)
	ck(not Q.validate(ready,disconnected).ok,"next day's opening loyalty must match the retained closing balance")
	var earlier:=day9.duplicate(true)
	earlier.opened_day=8
	ck(not Q.validate(ready,earlier).ok,"commission cannot predate family estate")
	var sick:=day9.duplicate(true)
	sick.members[H].life_status="Wounded"
	sick.can_visit=false
	ck(Q.reconcile(ready,sick)==ready and not submit(ready,3,sick).ok,"temporary wounds retain deadline but prevent visit")
	var captured:=sick.duplicate(true)
	captured.members[H].life_status="Captive"
	ck(Q.reconcile(ready,captured)==ready,"captivity does not end an open commission")
	var completion:=submit(ready,3,day9)
	if not ck(completion.ok,"sign correct response"):return
	var signed: Dictionary=completion.value
	ck(signed.status=="completed" and not signed.rewarded and Q.validate(signed,day9).ok,"signed receipt independently claimable")
	ck(not submit(signed,3,day9).ok,"cannot sign twice")
	var lost:=day9.duplicate(true)
	lost.governor_id=null
	lost.members[G].life_status="Dead"
	ck(Q.reconcile(signed,lost)==signed and Q.view(signed,lost).can_claim,"signed receipt remains claimable after issuer death")
	ck(not Q.plan(signed,"visit_claim",{},sick).ok and not Q.plan(signed,"visit_claim",{"amount":9},lost).ok,"cannot collect while wounded or choose award")
	var succession:=lost.duplicate(true)
	succession.player_id=null
	succession.can_visit=false
	succession.members[H].life_status="Retired"
	var forfeit:=Q.reconcile(signed,succession)
	ck(forfeit.status=="failed" and Q.validate(forfeit,succession).ok and not Q.view(forfeit,succession).can_claim,"signed personal reward cannot pass to successor")
	var claim:=Q.plan(signed,"visit_claim",{},lost)
	if not ck(claim.ok,"claim without original officer"):return
	var paid: Dictionary=claim.value
	ck(paid.rewarded and not signed.rewarded and Q.validate(paid,lost).ok,"claim is a separate candidate")
	ck(Q.reconcile(paid,succession)==paid and Q.validate(paid,succession).ok,"claimed history survives end of career")
	ck(not Q.plan(paid,"visit_claim",{},lost).ok and not Q.plan(paid,"visit_accept",TARGET,day9).ok,"paid commission cannot mint another opportunity")
	ck(Q.reward_source(paid)==Q.reward_source(active) and Q.reward_source(paid).begins_with("quest/liuxi/"),"stable reward source")
	var day10:=facts(10)
	day10.last_report=ledger(10,1000,508)
	altered=ready.duplicate(true)
	altered.ledger.prosperity_bonus=99
	altered["ledger_hash"]=C.hash_value(altered.ledger).value
	ck(not Q.validate(altered,day10).ok,"recomputed hash cannot exceed actual governor skill on older day")
	ck(Q.reconcile(ready,day10)==ready and submit(ready,3,day10).ok,"last day inclusive")
	var day11:=facts(11)
	day11.last_report=ledger(11,1000,512)
	var expired:=Q.reconcile(ready,day11)
	ck(expired.status=="expired" and expired.ended_day==11 and Q.validate(expired,day11).ok,"expires on fourth day")
	ck(not Q.plan(expired,"visit_accept",TARGET,day11).ok and Q.plan(expired,"visit_accept",TARGET,facts(12)).ok,"expiry cooldown ends following day")
	ck(not submit(ready,3,day11).ok,"stale report rejected even before explicit reconcile")
	ck(Q.reconcile(ready,lost).status=="failed","unsubmitted commission fails on issuer loss")
	var bereaved:=day9.duplicate(true)
	bereaved.members[H].life_status="Dead"
	bereaved.can_visit=false
	ck(Q.reconcile(ready,bereaved).status=="failed" and Q.reconcile(signed,bereaved).status=="failed","actor death invalidates unclaimed work")
	bad_field(active,"schema_version",2,f)
	bad_field(active,"settlement_id",null,f)
	bad_field(active,"issuer_id",H,f)
	bad_field(active,"actor_id","hero/invalid",f)
	bad_field(active,"accepted_day",8,f)
	bad_field(active,"deadline_day",11,f)
	bad_field(active,"status","ready",f)
	bad_field(active,"status","garbage",f)
	bad_field(active,"rewarded",1,f)
	bad_field(active,"rewarded",true,f)
	bad_field(ready,"ended_day",8,day8)
	bad_field(signed,"ended_day",7,day9)
	bad_field(signed,"reason","forged",day9)
	bad_field(expired,"ended_day",10,day11)
	bad_field(ready,"ledger",{},day8)
	var invalid:=ledger(10)
	bad_field(ready,"ledger",invalid,day9)
	invalid=ledger(8)
	bad_field(ready,"ledger",invalid,day8)
	invalid.governor_id=H
	bad_field(ready,"ledger",invalid,day9)
	invalid=ledger(8)
	invalid.prosperity_after=999
	bad_field(ready,"ledger",invalid,day9)
	ck(not Q.validate(signed,succession).ok and not Q.validate(ready,lost).ok,"reject unreconciled orphan claims/appointments")
	var full:=facts(8)
	full.last_report=ledger(8,1000)
	var capped:=Q.reconcile(active,full)
	ck(submit(capped,0,full).ok and Q.view(capped,full).answers.has(0),"zero realized change at cap")

func _initialize() -> void:
	exercise()
	print("ESTATE_COMMISSION checks=%d failures=%d" % [checks,failures])
	quit(int(failures!=0))
