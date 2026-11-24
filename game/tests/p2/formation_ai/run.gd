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
	if ResourceLoader.exists(L1):
		return load(L1)
	var path := OS.get_environment("RECOLLECTION_TEST_L1")
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
		for trial in 21:
			var job: Dictionary = w.publish(1+trial*5).formation
			var begin := Time.get_ticks_usec()
			var d: Dictionary = w.brain.stage(job,task,ground,trial+1).value
			var row := w.collect(job,d)
			check(w.brain.validate(d.token,row).ok and w.brain.commit(d.token,row).ok,"timed read, grant, preflight and commit")
			if trial>0: samples.append(Time.get_ticks_usec()-begin)
		samples.sort()
		print("L2_ONE_FORMATION members=",people," samples=",samples.size()," p50_us=",samples[9]," p95_us=",samples[18])
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
	var tests: Array[Callable]=[owner_hold,bottleneck,spent_or_late]
	for i in tests.size():
		var before := failures
		check(tests[i].call()==true,"case returned "+str(i+1))
		print("T-BAI-F-0",i+1," ","PASS" if before==failures else "FAIL")
	check(layer_cost(),"L2 isolated field decision costs")
	adapter.release_scope(World.SCOPE)
	print("P2-BAI-F-001 ", "PASS" if failures==0 else "FAIL"," assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
