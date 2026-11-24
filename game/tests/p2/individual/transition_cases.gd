extends RefCounted

const AI = preload("res://mission/ai/ports/field_ai.gd")
const Brain = preload("res://mission/ai/individual/ports/field_individual.gd")
const Combat = preload("res://mission/combat/ports/field_combat.gd")

# Keep the fixture's physical body fixed and vary the range by moving its observer.
static func exercise(test, scenario: String, switch_tick: int) -> void:
	var ai := AI.new(test.SCOPE,test.clear_ray)
	var brain := Brain.new(test.SCOPE,ai.get_instance_id())
	var com := Combat.new(test.SCOPE)
	com.enlist(test.A,{"team":0,"role":"archer","ranged":"bow","ammo":12})
	com.enlist(test.B,{"team":1,"role":"infantry","hp":1 if scenario=="casualty" else 500})
	if scenario=="casualty":
		com.enlist(test.H,{"team":0,"role":"infantry"})
	var foe: Dictionary = test.B
	var incoming := scenario in ["incoming","hidden","casualty"]
	var first_slot := 1 if incoming else 0
	var final_slot := 1-first_slot
	var old_completion := ""
	var new_strike := false
	var physical_kill := false
	var absent := 0
	for t in range(1,35):
		var switched := t>=switch_tick
		var near_target := switched if incoming else not switched
		var enemy := Vector3(6,0,15)
		var own := Vector3(5 if near_target else -2,0,15)
		if scenario=="hidden":
			enemy = Vector3(6,0,0)
			own = Vector3(2 if t<switch_tick else (-3 if t<10 else 5),0,0)
		elif scenario=="casualty" and t==10:
			com.remove_actor(foe)
			foe={"index":test.B.index,"generation":2}
			com.enlist(foe,{"team":1,"role":"infantry","hp":500})
		var rows := [test.unit(test.A,own,0,"archer"),test.unit(foe,enemy,1,"infantry")]
		var job: Dictionary = test.job_for(ai,t,rows)
		var local: Dictionary = test.context(own)
		if com.view(foe).value.hp==0:
			local.incapacitated=[foe]
			physical_kill=true
		var seen: Dictionary = ai.sense(test.A).value
		var proposal: Dictionary = brain.decide(job,seen,com.view(test.A).value,test.ORDERS,local)
		if not proposal.ok:
			test.check(false,"transition proposal "+scenario)
			return
		var plan: Dictionary = proposal.value
		var receipt := ai.collect(job,plan.intents)
		if not receipt.ok:
			test.check(false,"transition collect "+scenario)
			return
		var batch: Dictionary = ai.drain().value[0]
		var input: Array = test.actions(batch.intents)
		var expected_missing := (scenario=="hidden" and t>=switch_tick and t<10) or (scenario=="casualty" and t>=5 and t<10)
		if expected_missing:
			absent+=1
			test.check(plan.target==null and (input.is_empty() or input[0].get("input_phase")=="cancel"),"no blind action against hidden/downed contact")
		if not input.is_empty():
			var attack: Dictionary = input[0]
			if attack.get("input_phase") in ["release","cancel"] and attack.weapon_slot==first_slot and old_completion.is_empty():
				old_completion=attack.input_phase
			if attack.get("input_phase")=="release" and t>switch_tick and attack.weapon_slot==final_slot:
				new_strike=true
				test.check(attack.target_hint==foe,"current visible generation after switch")
		var own_count := input.size()
		var poses: Dictionary = test.poses(own,enemy)
		if scenario=="casualty":
			poses[test.H.index]={"position_mm":test.mm(enemy+Vector3.LEFT+Vector3.UP*0.7),"facing_ppm":[1000000,0,0]}
			if t in [1,4]:
				input.append({"actor_handle":test.H,"input_phase":"start" if t==1 else "release","direction":"thrust","weapon_slot":0,"target_hint":foe})
		var current_foe := foe
		var sweep := func(queries,step):
			var result: Dictionary = test.sweep(queries,step)
			if result.ok:
				for hit in result.value:
					if hit.get("target")==test.B: hit.target=current_foe
			return result
		var step := com.step_field(t,input,poses,sweep)
		if not step.ok:
			test.check(false,"transition COM "+scenario+" "+str(step))
			return
		var action_receipt: Dictionary = {"ok":true,"value":null} if own_count==0 else step.value.receipts[0]
		test.check(action_receipt.ok and brain.accept(batch,plan,action_receipt).ok,"transition real COM receipt "+scenario)
	var expected := "cancel" if (scenario=="outgoing" and switch_tick==3) or (scenario in ["incoming","hidden"] and switch_tick==2) else "release"
	test.check(old_completion==expected and new_strike and com.view(test.A).value.weapon_slot==final_slot,"finish old weapon then fight using new slot "+scenario+str(switch_tick))
	if scenario=="casualty": test.check(physical_kill and absent==5,"confirmed physical death then replacement")
	if scenario=="hidden": test.check(absent==10-switch_tick,"real occlusion then reacquisition")
	print("L3_TRANSITION ",scenario," switch=",switch_tick," old=",old_completion," new_strike=",new_strike," unavailable_ticks=",absent)


static func run(test) -> void:
	exercise(test,"outgoing",3)
	exercise(test,"outgoing",5)
	exercise(test,"incoming",2)
	exercise(test,"incoming",5)
	exercise(test,"hidden",2)
	exercise(test,"hidden",5)
	exercise(test,"casualty",5)
