extends "res://tests/p2/individual/run.gd"

func run() -> void:
	var ai = AI.new(SCOPE,func(_a,_b):return true)
	var brain := Brain.new(SCOPE,ai.get_instance_id())
	var com := Combat.new(SCOPE)
	com.enlist(A,{"team":0,"role":"archer","ranged":"bow","ammo":10})
	com.enlist(B,{"team":1,"role":"infantry"})
	var pos := Vector3.ZERO
	var local := {"slot_position":pos,"exit_position":null,"heading":Vector3.RIGHT,"nav_revision":0,"can_travel":func(_p,_q,_n): return true}
	var attacks := 0
	var mode := ""
	var report := {}
	for t in range(1,62):
		var b := Vector3.RIGHT * (1.0 if t<=2 else 8.0)
		var rows := [unit(A,pos,0,"archer"),unit(B,b,1,"infantry")]
		var j := job_for(ai,t,rows)
		var proj: Dictionary = brain.decide(j,ai.sense(A).value,com.view(A).value,ORDERS,local)
		if not proj.ok: print("bad ",proj);quit(2);return
		var v: Dictionary = proj.value
		var c: Dictionary = ai.collect(j,v.intents)
		var wr: Dictionary = com.step_field(t,actions(v.intents),poses(pos,b),func(_qs,_t):return R.ok([]))
		if not c.ok or not wr.ok: print("bad execute ",c,wr);quit(2);return
		var raw: Array = ai.drain().value
		var ok: Dictionary = brain.accept(raw[0],v,R.ok())
		if not ok.ok: print("bad accept ",ok);quit(2);return
		if not actions(v.intents).is_empty(): attacks+=1
		if t<5 or t==61: print("t=",t," mode=",v.mode," action=",actions(v.intents)," phase=",com.view(A).value.phase)
		mode=v.mode
		report=com.view(A).value
	print("final=",report.phase," slot=",report.weapon_slot," actions=",attacks," mode=",mode)
	quit(1 if report.phase=="Hold" and report.weapon_slot==0 and attacks==2 else 0)
