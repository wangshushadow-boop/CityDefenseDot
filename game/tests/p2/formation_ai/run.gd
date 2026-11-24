extends SceneTree
const World = preload("res://tests/p2/formation_ai/world.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const R = preload("res://contracts/result.gd")
const A := Vector3(0,0,3.5)
const B := Vector3(0,0,6)
const FIELD := {"id":"test:scene/formation_ai","simulation_scene":"res://tests/p2/formation_ai/field.tscn"}
const L1 := "res://mission/ai/tactical/ports/field_tactics.gd"
var adapter: RefCounted
var nav: int
var failures := 0
var assertions := 0
var l1_script: Script

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func owner_hold() -> bool:
	var w := World.new(adapter,nav,check)
	var p := Vector3(0,0,-8)
	w.deploy(0,[0],[p],"cavalry",0)
	w.deploy(1,[1],[p+Vector3.RIGHT*6],"infantry",0)
	var job: Dictionary = w.publish(1).formation
	var flank := w.task("flank","cavalry",p,1)
	flank.order_revision = w.revision
	var forged := job.duplicate(true)
	forged.id += 99999
	var tentative: Dictionary = w.brain.stage(forged,flank,w.ground(),1).value
	check(not w.brain.collect(tentative.token).ok and not w.brain.commit(tentative.token,{"job":forged,"intents":tentative.orders}).ok,"counterfeit grant cannot be collected or committed")
	check(w.brain.rollback(tentative.token).ok,"drop rejected grant")
	var unseen := flank.duplicate(true)
	unseen.target_formation=42
	var hidden: Dictionary = w.brain.stage(job,unseen,w.ground(),1).value
	check(hidden.feedback.reason=="target_not_visible" and hidden.member_constraint.focus_target==null,"no scouting hidden formation by task ID")
	check(w.brain.rollback(hidden.token).ok,"discard hidden candidate")
	var during := {"token":null,"attempted":false}
	var guarded = World.Brain.new(World.SCOPE,"captain",w.ai.formation_view,w.form.view,0,func(candidate,orders):
		var rollback_result: Dictionary = during.brain.rollback(during.token)
		during.attempted=not rollback_result.ok
		return w.ai.collect(candidate,orders))
	during.brain=guarded
	# A wrong grant intentionally leaves the real grant available for the owner scenario.
	var guarded_result: Dictionary=guarded.stage(forged,flank,w.ground(),1).value
	during.token=guarded_result.token
	check(not guarded.collect(during.token).ok and during.attempted,"reentrant rollback rejected during collection")
	check(guarded.rollback(during.token).ok,"ordinary rollback available after callback")
	guarded.close()
	during.clear()
	var eager: Dictionary = w.brain.stage(job,flank,w.ground(),1).value
	check(eager.behavior=="Charge" and eager.orders[0].order_type=="charge","eligible cavalry at site really selects charge")
	var row := w.collect(job,eager)
	var order := {"mission_id":World.SCOPE,"issuer_id":"player","order_id":"player-hold","client_sequence":1,"issued_tick":2,
		"formation_ids":[0],"order_type":"hold","target_position":null,"target_formation_id":null,"parameters":{}}
	check(w.form.issue_order(order,w.player,1).ok,"real player v1 hold")
	w.to_tick(2)
	check(not w.brain.commit(eager.token,row).ok and not w.brain.view(0).ok,"late player order invalidates candidate")
	check(w.brain.rollback(eager.token).ok,"release stale candidate")
	w.revision+=1
	var fresh: Dictionary = w.publish(7).formation
	var d := w.decide(fresh,flank)
	check(d.behavior=="Hold" and d.orders.is_empty() and d.feedback.reason=="player_order","retain active player hold")
	check(not d.member_constraint.engage_allowed and d.member_constraint.movement_limit==0.0,"standing hold constrains L3")
	check(w.form.view(0).value.active == order and not w.brain.stage(job,flank,w.ground(),2).ok,"old grant rejected after next snapshot")
	check(w.form.set_delegate(0,"",w.player,1).ok,"revoke")
	var next: Dictionary = w.publish(12).formation
	check(not w.brain.stage(next,flank,w.ground(),2).ok,"old task grant revoked")
	var blind := w.task("flank","cavalry",p,1)
	var blocked: Dictionary = w.brain.stage(next,blind,w.ground(),2).value
	check(blocked.orders.is_empty(),"ungranted actor emits no order")
	check(w.brain.rollback(blocked.token).ok,"cancel unissued plan")
	w.brain.close()
	check(not w.brain.stage(next,blind,w.ground(),2).ok,"disposed scope")
	return true

func bottleneck() -> bool:
	var w := World.new(adapter,nav,check)
	w.deploy(0,[0,1,2],[B,B+Vector3.BACK,B+Vector3.BACK*2],"infantry",0,true)
	w.deploy(1,[3],[A],"archer",1)
	var target := Vector3(6,0,-8)
	var task := w.task("advance","infantry",target)
	check(w.ground().clear_width==1.0,"real navigation sees a one-metre passage")
	var d := w.decide(w.publish(1).formation,task)
	check(d.behavior=="Regroup" and d.feedback.reason=="bottleneck","L2 requests recovery at passage")
	var first := w.layout(d)
	check(first.ok and first.value.compressed and first.value.requested_layout=="line","FORM applies feasible transient slots")
	w.shoot(3,0)
	check(w.combat.view(World.h(0)).value.hp==0 and w.combat.view(World.h(3)).value.ammo==0,"COM shot caused an actual casualty")
	w.groups[0]=[World.h(1),World.h(2)]
	check(w.form.assign_members(0,w.groups[0]).ok and w.mov.despawn(World.h(0)).ok,"authoritative survivor roster")
	var loss := w.decide(w.publish(10).formation,task)
	check(loss.feedback.reason=="casualties" and loss.orders.is_empty(),"loss triggers regroup without duplicating standing order")
	var narrowed := w.layout(loss)
	check(narrowed.ok and narrowed.value.slots.size()==2 and narrowed.value.compressed,"survivors receive unique feasible slots")
	var active: Dictionary = w.form.view(0).value.active
	check(active.order_type=="move" and World.meters(active.target_position).is_equal_approx(loss.local_goal),"authority permits advancing through passage while reforming")
	check(w.mov.set_corridor("exit",w.center(),World.meters(active.target_position)).ok,"MOV exit from active FORM order")
	for slot in narrowed.value.slots:
		check(w.mov.assign(slot.member,"exit",slot.local_offset).ok,"assign projected surviving member")
	for tick in range(1,241):
		check(w.mov.step(tick,1.0/30.0).ok,"real movement step")
	check(w.center().z < -2.0 and w.ground().clear_width>=4.0,"survivors physically exited narrow gate")
	var resume := w.decide(w.publish(250).formation,task)
	var wide := w.layout(resume)
	check(resume.behavior=="Advance" and resume.orders.is_empty() and w.form.view(0).value.active.target_position==World.mm(target),"resumes task after casualty and exit")
	check(wide.ok and not wide.value.compressed and wide.value.requested_layout=="line","FORM restores initial layout")
	print("navigation projections=",w.projected," survivors=",w.groups[0].size()," center=",w.center())
	return true

func role_and_order_modes() -> bool:
	var w := World.new(adapter,nav,check)
	var p := Vector3(3,0,-6)
	var enemy := Vector3(-3,0,-6)
	w.deploy(0,[0],[p],"archer",2)
	w.deploy(1,[1],[enemy],"infantry",0)
	var job: Dictionary = w.publish(1).formation
	check(w.form.assign_members(0,[World.h(99)]).ok,"FORM mutates same-size membership before decision")
	check(not w.brain.stage(job,null,w.ground(),1).ok,"stale roster with same count, control and order revisions")
	check(w.form.assign_members(0,[World.h(0)]).ok,"restore original fixture membership")
	var site := p+Vector3.BACK*3
	for row in [["hold","infantry",site,"Move"],["advance","infantry",null,"Advance"],
			["cover","archer",p,"Fire"],["harass","mounted_archer",p,"Fire"],["retreat","infantry",site,"Retreat"]]:
		var t := w.task(row[0],row[1],row[2],1)
		var draft: Dictionary = w.brain.stage(job,t,w.ground(),1).value
		check(draft.behavior==row[3],"L1 goal "+row[0])
		if row[3]=="Fire":
			check(draft.member_constraint.fire_allowed and draft.member_constraint.focus_target==World.h(1),"contact scoped by BAI")
		check(w.brain.rollback(draft.token).ok,"discard role example")
	var site_task := w.task("advance","infantry",site)
	var blocked_ground := w.ground()
	blocked_ground.reachable=false
	var blocked: Dictionary = w.brain.stage(job,site_task,blocked_ground,1).value
	check(blocked.behavior=="Hold" and blocked.feedback.reason=="unreachable","blocked path falls back")
	check(w.brain.rollback(blocked.token).ok,"release blocked case")
	var stale := site_task.duplicate(true)
	stale.order_revision = 7
	check(not w.brain.stage(job,stale,w.ground(),1).ok,"L1 stale order revision")
	var routed: Dictionary = w.form.set_routing(0,true)
	var retreat: Dictionary=w.brain.stage(job,site_task,w.ground(),1).value
	check(routed.ok and retreat.behavior=="Retreat" and retreat.orders.is_empty() and retreat.feedback.reason=="routing","routing never issues a forbidden command")
	check(w.brain.rollback(retreat.token).ok and w.form.set_routing(0,false).ok,"rally")
	var mode := {"mission_id":World.SCOPE,"issuer_id":"player","order_id":"fire-off","client_sequence":1,"issued_tick":2,
		"formation_ids":[0],"order_type":"hold_fire","target_position":null,"target_formation_id":null,"parameters":{}}
	check(w.form.issue_order(mode,w.player,1).ok,"owner sets fire discipline")
	w.to_tick(2)
	w.revision+=1
	var no_fire := w.decide(w.publish(7).formation,w.task("cover","archer",p,1))
	check(no_fire.behavior=="Hold" and not no_fire.member_constraint.fire_allowed and w.form.view(0).value.fire_mode=="hold_fire","L2 preserves fire discipline")
	w.deploy(2,[2],[p+Vector3.BACK*3],"infantry",0,false,0)
	var follow: Dictionary = mode.duplicate(true)
	follow.merge({"order_id":"follow","order_type":"follow","target_formation_id":2,"issued_tick":w.tick+1,"client_sequence":2},true)
	check(w.form.issue_order(follow,w.player,1).ok,"owner follows an allied formation")
	w.to_tick(w.tick+1)
	w.revision+=1
	var following := w.decide(w.publish(13).formation,null)
	check(following.behavior=="Follow" and following.local_goal==w.pos(2) and following.orders.is_empty(),"follow uses allied current formation center")
	return true

func load_l1() -> Script:
	return _layer_script(L1,"RECOLLECTION_TEST_L1")

func _layer_script(resource_path: String, source_env: String) -> Script:
	if ResourceLoader.exists(resource_path):
		return load(resource_path)
	var path := OS.get_environment(source_env)
	if path.is_empty() or not FileAccess.file_exists(path): return null
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	return script if script.reload()==OK else null

func tactics(w: World) -> RefCounted:
	return l1_script.new(World.SCOPE,0,func(_scope,id,rev,order_rev):
		var f: Dictionary = w.form.view(id).value
		return f.delegate=="captain" and f.control_revision==rev and w.revision==order_rev,
		func(_scope,_version,id,_from,to,contact,_role):
			return R.ok({"reachable":w.reachable(id,World.mm(to)),"line":contact!=null}),
		func(team):return w.ai.team_view(team).value,
		func(job):return w.ai.collect(job,[]))

func published_orders() -> bool:
	var w := World.new(adapter,nav,check)
	var p := Vector3(0,0,-8)
	w.deploy(0,[0],[p],"cavalry",0)
	w.deploy(1,[1],[p+Vector3.RIGHT*6],"infantry",0)
	var jobs := w.publish(1)
	var planner := tactics(w)
	var plan: Dictionary=planner.stage(jobs.tactical,w.ai.team_view(0).value,[{"id":"flank","position":p}])
	check(plan.ok and planner.commit().ok,"authorized production flank task")
	w.ai.drain()
	var task: Dictionary = planner.view().formation_tasks[0]
	check(task.goal=="flank" and task.completion=="arrived","L1 completion contract")
	var charged := w.decide(jobs.formation,task)
	var arrived: Dictionary = w.brain.view(0).value
	check(w.form.view(0).value.active.order_type=="charge" and arrived.behavior=="Charge","reaching the site retains the tactical action")
	check(arrived.feedback.status=="completed" and arrived.feedback.reason=="arrived" and arrived.feedback.progress==1.0,"acknowledge exact L1 destination")

	# A second granted task is a distinct proposal at the same position. The
	# owner and delegate submit for the same next tick before FORM arbitrates.
	var fresh := w.publish(7)
	var pending := w.task("retreat","cavalry",p)
	var d: Dictionary = w.brain.stage(fresh.formation,pending,w.ground(),w.sequence+1).value
	var row := w.collect(fresh.formation,d)
	var player := {"mission_id":World.SCOPE,"issuer_id":"player","order_id":"immediate-hold","client_sequence":1,"issued_tick":8,
		"formation_ids":[0],"order_type":"hold","target_position":null,"target_formation_id":null,"parameters":{}}
	check(w.form.issue_order(player,w.player,1).ok and w.brain.validate(d.token,row).ok,"queue player order before L2 publication")
	check(w.form.issue_order(row.intents[0],w.captain,1).ok and w.brain.commit(d.token,row).ok,"publish candidate before FORM resolution")
	check(w.brain.view(0).value.behavior=="Charge","before arbitration only earlier effective command permits a charge")
	w.to_tick(8)
	var effective: Dictionary = w.brain.view(0).value
	var receipt: Dictionary = w.form.order_status("captain",row.intents[0].order_id).value[0]
	check(receipt.state=="Replaced" and receipt.reason=="player_priority","authority rejects delegate on execution tick")
	check(effective.behavior=="Hold" and effective.local_goal==p and not effective.member_constraint.engage_allowed and effective.member_constraint.movement_limit==0.0,"read effective player hold before next L2 job")
	check(effective.feedback.status=="blocked" and effective.feedback.reason=="player_order","losing candidate does not publish task success")
	check(w.brain.view(0).value==effective,"effective query is side-effect free")

	var script := _layer_script("res://mission/ai/individual/ports/field_individual.gd","RECOLLECTION_TEST_L3")
	if script==null:
		print("L3 consumer cross-suite NOT_RUN (set RECOLLECTION_TEST_L3 or integrate L3)")
		return true
	w.revision+=1
	var after := w.publish(9)
	var job: Dictionary=after.individual
	var soldier: RefCounted=script.new(World.SCOPE,w.ai.get_instance_id())
	var perception: Dictionary=w.ai.sense(job.subject).value
	var com: Dictionary=w.combat.field_view(World.SCOPE,[job.subject],0).value.actors[0]
	var local_state := {"slot_position":p,"heading":Vector3.FORWARD,"nav_revision":nav,"weapons":["melee"],"reload_until":0,
		"can_travel":func(_from,to,_rev): return w.reachable(0,World.mm(to))}
	var stale: Dictionary=soldier.decide(job,perception,com,charged.member_constraint,local_state)
	check(stale.ok and stale.value.intents.any(func(i): return i.get("speed_fraction",0)>0),"same L3 job would physically advance on superseded charge")
	var held: Dictionary=soldier.decide(job,perception,com,w.brain.view(0).value.member_constraint,local_state)
	check(held.ok and held.value.mode=="Hold" and held.value.intents.is_empty(),"production L3 immediately holds; no movement/attack to execute")
	check(w.ai.collect(job,held.value.intents).ok and soldier.accept(w.ai.drain().value[0],held.value,R.ok()).ok,"real L3 grant and final receipt")
	print("L3 priority at tick 9 ",stale.value.mode," -> ",held.value.mode)
	return true

func spent_or_late() -> bool:
	if l1_script==null:
		printerr("T-BAI-F-03 L1 receiver NOT_RUN: missing integrated L1 or RECOLLECTION_TEST_L1")
		return false
	for scenario in ["ammo_depleted","timeout"]:
		var w := World.new(adapter,nav,check)
		w.deploy(0,[0],[A],"archer",1)
		w.deploy(1,[1],[B],"infantry",0)
		var planner := tactics(w)
		var jobs := w.publish(1)
		var site := [{"id":"ridge","position":A}]
		var plan: Dictionary = planner.stage(jobs.tactical,w.ai.team_view(0).value,site)
		check(plan.ok and plan.value.formation_tasks.size()==1,"production L1 issued task "+str(plan))
		if not plan.ok or plan.value.formation_tasks.is_empty(): return false
		check(planner.commit().ok,"production L1 authorized commit")
		var l1_rows: Array = w.ai.drain().value
		check(l1_rows.size()==1 and is_same(l1_rows[0].job,jobs.tactical),"real tactical grant consumed once")
		var task: Dictionary = plan.value.formation_tasks[0]
		check(task.goal=="cover" and task.role=="archer","actual approved L1 vocabulary")
		var next_tick := 7
		if scenario=="ammo_depleted":
			w.shoot(0,1)
			check(w.combat.view(World.h(0)).value.ammo==0,"real ranged ammunition debit")
		else:
			next_tick=task.timeout
		var due_jobs := w.publish(next_tick)
		var inputs := w.ground()
		var draft: Dictionary = w.brain.stage(due_jobs.formation,task,inputs,1).value
		check(draft.behavior=="Hold" and draft.feedback.reason==scenario and draft.feedback.status=="failed","legal fallback and reason "+scenario)
		check(draft.orders.size()==1 and draft.orders[0].order_type=="hold","fallback v1")
		var row := w.collect(due_jobs.formation,draft)
		var initial_orders: Array = draft.orders.duplicate(true)
		draft.orders[0].order_type="retreat"
		check(w.brain.validate(draft.token,row).ok,"candidate copy cannot alter authoritative proposal")
		check(w.brain.rollback(draft.token).ok and not w.brain.view(0).ok and w.form.view(0).value.active==null,"downstream failure left no state or order")
		var retry: Dictionary = w.brain.stage(due_jobs.formation,task,inputs,1).value
		check(retry.orders==initial_orders and retry.feedback==draft.feedback,"same grant, inputs and sequence replay")
		check(not w.brain.commit(draft.token,row).ok,"abandoned ticket cannot commit")
		check(w.brain.collect(retry.token).ok and w.ai.drain().value.is_empty(),"accepted replay does not consume a second grant")
		w.finish(retry,row)
		check(w.form.view(0).value.active.order_type=="hold" and not w.brain.commit(retry.token,row).ok,"one published fallback")
		var fresh := w.publish(next_tick+8)
		var without: Dictionary = planner.stage(fresh.tactical,w.ai.team_view(0).value,site)
		check(without.ok and without.value.formation_tasks[0].site_id=="ridge","without L2 failure the same site remains selectable")
		check(planner.rollback().ok,"discard counterfactual L1 plan")
		var adapted: Dictionary = planner.stage(fresh.tactical,w.ai.team_view(0).value,site,[w.brain.view(0).value.feedback])
		check(adapted.ok and adapted.value.phase=="Adapt" and adapted.value.formation_tasks[0].id!=task.id and adapted.value.formation_tasks[0].site_id!="ridge","actual L1 consumes "+scenario)
		check(planner.commit().ok,"production L1 published feedback-driven change")
		var adapted_rows: Array=w.ai.drain().value
		check(adapted_rows.size()==1 and is_same(adapted_rows[0].job,fresh.tactical),"one real L1 receipt despite speculative rollback")
		print("L1 feedback ",scenario," -> ",planner.view().phase," task=",planner.view().formation_tasks[0].id)
	return true

func layer_cost() -> bool:
	for people in [500,1000]:
		var w := World.new(adapter,nav,check)
		var ids := range(people)
		var points := []
		for i in people:
			points.append(Vector3(3 + (i%20)*.10, 0, -12 + floori(i/20.0)*.10))
		w.deploy(0,ids,points,"infantry",0)
		var task := w.task("advance","infantry",Vector3(8,0,-4))
		var ground := w.ground()
		var samples := PackedInt64Array()
		var reads := PackedInt64Array()
		for trial in 21:
			var job: Dictionary = w.publish(1+trial*5).formation
			var begin := Time.get_ticks_usec()
			var d: Dictionary = w.brain.stage(job,task,ground,trial+1).value
			var row := w.collect(job,d)
			for order in row.intents:
				check(w.form.issue_order(order,w.captain,1).ok,"publish measured order")
			check(w.brain.validate(d.token,row).ok and w.brain.commit(d.token,row).ok,"timed read, grant, preflight and commit")
			if trial>0: samples.append(Time.get_ticks_usec()-begin)
			w.to_tick(w.tick+1)
			var read_start := Time.get_ticks_usec()
			var public_state: Dictionary = w.brain.view(0)
			if trial>0: reads.append(Time.get_ticks_usec()-read_start)
			check(public_state.ok and public_state.value.behavior=="Advance","one effective formation view for L3 dispatch")
		samples.sort()
		reads.sort()
		print("L2_ONE_FORMATION members=",people," samples=",samples.size()," p50_us=",samples[9]," p95_us=",samples[18]," effective_view_p95_us=",reads[18])
	return true

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	adapter=Adapter.new(root,true)
	var scope: Dictionary = adapter.open_scope(World.SCOPE)
	check(scope.ok and adapter.load_scene(FIELD,scope.value).ok,"load real field")
	var ready := false
	for i in 120:
		await physics_frame
		var sync: Dictionary = adapter.sync_navigation(World.SCOPE)
		if sync.ok and sync.value.status=="applied":
			nav=sync.value.applied_revision
			var path: Dictionary=adapter.query_path_batch([{"from":[0,0,-4000],"to":[0,0,6000]}],nav,World.SCOPE)
			if path.ok and path.value[0].reachable:
				ready=true
				break
	if not ready:
		printerr("FAIL field did not sync")
		quit(1)
		return
	check(role_and_order_modes(),"role and active order modes complete")
	l1_script=load_l1()
	check(l1_script!=null and published_orders(),"authoritative order read and arrival feedback")
	var tests: Array[Callable]=[owner_hold,bottleneck,spent_or_late]
	for i in tests.size():
		var before := failures
		check(tests[i].call()==true,"case returned "+str(i+1))
		print("T-BAI-F-0",i+1," ","PASS" if before==failures else "FAIL")
	check(layer_cost(),"L2 isolated field decision costs")
	adapter.release_scope(World.SCOPE)
	print("P2-BAI-F-001 ", "PASS" if failures==0 else "FAIL"," assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
