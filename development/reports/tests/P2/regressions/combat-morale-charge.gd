extends SceneTree
const Field=preload("res://mission/combat/ports/field_combat.gd")
const R=preload("res://contracts/result.gd")
const A={"index":0,"generation":1}
const B={"index":1,"generation":1}
const H={"index":2,"generation":1}
func _initialize():
	var sim:=Field.new()
	var low:=sim.enlist(A,{"team":0,"role":"infantry","morale":0})
	var attack:={"actor_handle":A,"input_phase":"start","weapon_slot":0,"direction":"up","target_hint":null}
	var out:=sim.step_field(1,[attack],{},Callable())
	print("initial_morale=",sim.view(A).value.morale," routing=",sim.view(A).value.routing," action_receipt=",out.value.receipts[0])
	var m:=Field.new()
	m.enlist(A,{"team":0,"role":"cavalry"})
	m.enlist(H,{"team":0,"role":"mount"})
	m.enlist(B,{"team":1,"role":"infantry"})
	m.mount(A,H)
	var n:=[0]
	var sampled:=[]
	for tick in range(1,12):
		var poses:={0:{"position_mm":[(tick-6)*180,0,0],"speed_mm_tick":180,"facing_ppm":[1000000,0,0]},1:{"position_mm":[0,0,0],"speed_mm_tick":0,"facing_ppm":[-1000000,0,0]},2:{"position_mm":[(tick-6)*180,0,0],"speed_mm_tick":180,"facing_ppm":[1000000,0,0]}}
		var r:=m.step_field(tick,[],poses,func(_q,_t): n[0]+=1; return R.ok([{"query_index":0,"fraction_ppm":500000,"region":"body","target":B}]))
		if r.ok:
			sampled.append_array(r.value.events)
	var victim:Dictionary=m.view(B).value
	print("unarmed_mount_crossing sweep_batches=",n[0]," target_hp=",victim.hp," events=",sampled.size())
	quit(0 if low.ok and sim.view(A).value.routing and not out.value.receipts[0].ok and n[0]>0 and (victim.hp<100 or not sampled.is_empty()) else 1)