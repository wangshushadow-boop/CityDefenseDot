extends SceneTree
const Tactics = preload("res://mission/ai/tactical/ports/field_tactics.gd")
const AI = preload("res://mission/ai/ports/field_ai.gd")
const FORM = preload("res://mission/formation/ports/field_formation.gd")
const ENGINE = preload("res://infrastructure/engine/adapter.gd")
const R = preload("res://contracts/result.gd")
const SCOPE := "tactics-field"
var engine: RefCounted
var board: RefCounted
var form: RefCounted
var command := RefCounted.new()
var player := RefCounted.new()
var nav := -1
var tick := 0
var errors := 0
var queries := 0
var rays := 0
var physical_errors := 0
var sites := [{"id":"flat","position":Vector3(-5,0,0)},{"id":"deck","position":Vector3(12,4,0)},
	{"id":"lateral","position":Vector3(-6,0,9)},{"id":"objective","position":Vector3(2,0,1),"objective":true},
	{"id":"off_mesh","position":Vector3(100,40,100)}]

func check(value: bool, label: String) -> void:
	if not value:
		printerr("FAIL ",label)
		errors += 1

static func mm(p: Vector3) -> Array:
	return [roundi(p.x*1000),roundi(p.y*1000),roundi(p.z*1000)]

func los(a: Vector3,b: Vector3) -> bool:
	if a==b:
		return true
	rays += 1
	var r: Dictionary = engine.query_sweep_batch([{"from":mm(a+Vector3.UP),"to":mm(b+Vector3.UP),"mask":4}],{"scope_id":SCOPE,"tick":tick})
	if not r.ok: physical_errors += 1
	return r.ok and r.value.is_empty()

func probe(scope: String, revision: int, _group: int, a: Vector3, b: Vector3, enemy: Variant, _role: String) -> Dictionary:
	queries += 1
	var result: Dictionary = engine.query_path_batch([{"from":mm(a),"to":mm(b)}],revision,scope)
	if not result.ok:
		return result
	return R.ok({"reachable":result.value[0].reachable,"line":enemy!=null and los(b,enemy)})

func authenticate(token: Variant) -> Dictionary:
	if is_same(token,command): return R.ok("ai")
	if is_same(token,player): return R.ok("player")
	return R.fail("Unauthorized")

static func order_rev(row: Dictionary) -> int:
	return row.active.client_sequence if row.active!=null else 0

func granted(scope: String,id: int, revision: int, order_revision: int) -> bool:
	var row: Dictionary = form.view(id)
	return scope==SCOPE and row.ok and row.value.control_revision==revision and order_rev(row.value)==order_revision and (row.value.owner=="ai" or row.value.delegate=="ai")

func live(team: Variant) -> Dictionary:
	var read: Dictionary = board.team_view(team)
	return read.value if read.ok else {}

static func unit(id: int, team: int, role: String, p: Vector3) -> Dictionary:
	return {"handle":{"index":id,"generation":1},"team_key":team,"formation_id":id,"position":p,
		"role":role,"hp":100,"ammo":20 if role in ["archer","mounted_archer"] else 0,"morale":75,"control_revision":0,"order_revision":0}

func frame(at: int, rows: Array) -> Dictionary:
	tick = at
	for row in rows:
		var own: Dictionary = form.view(row.formation_id).value
		row.control_revision = own.control_revision
		row.order_revision = order_rev(own)
	var published: Dictionary = board.publish(tick,nav,rows)
	check(published.ok,"publish valid BAI roster")
	if not published.ok: return {}
	for row in rows:
		if row.team_key==0:
			check(board.sense(row.handle,48,8).ok,"BAI sensed from own member")
	var due: Dictionary = board.schedule()
	for job in due.value.jobs:
		if job.layer=="tactical" and is_same(job.subject,0):
			return {"job":job,"intel":board.team_view(0).value}
	check(false,"tactical job actually due")
	return {}

static func assigned(plan: Dictionary, id: int) -> Dictionary:
	for task in plan.get("formation_tasks",[]):
		if task.formation_id==id: return task
	return {}

func exercise() -> void:
	var rows := [unit(0,0,"infantry",Vector3(-6,0,-9)),unit(1,0,"archer",Vector3(-6,0,1)),
		unit(2,0,"cavalry",Vector3(-5,0,0)),unit(3,0,"infantry",Vector3(-7,0,4)),
		unit(4,0,"mounted_archer",Vector3(-7,0,-4)),unit(5,1,"infantry",Vector3(3,0,0))]
	for row in rows:
		check(form.add_formation(row.formation_id,row.team_key,"player" if row.formation_id==0 else "ai",[row.handle]).ok,"real formation member")
	var order := {"mission_id":SCOPE,"issuer_id":"player","order_id":"hold0","client_sequence":1,"issued_tick":1,
		"formation_ids":[0],"order_type":"hold","parameters":{},"target_formation_id":null,"target_position":null}
	var accepted: Dictionary = form.issue_order(order,player,0)
	var advanced: Dictionary = form.advance(1)
	check(accepted.ok and advanced.ok,"player's actual order "+str([accepted,advanced]))
	var planner := Tactics.new(SCOPE,0,granted,probe,live,board.collect.bind([]))
	var first := frame(1,rows)
	var original_job: Dictionary = first.job
	check(first.intel.visible_enemies.size()==1,"confirmed BAI contact")
	var started := Time.get_ticks_usec()
	var staged := planner.stage(first.job,first.intel,sites)
	check(staged.ok and planner.view().is_empty(),"only draft before commit "+str([staged,first.job]))
	if not staged.ok: return
	staged.value.formation_tasks.clear()
	check(planner.commit().ok,"first commit")
	check(board.drain().value[0].job.id==first.job.id,"original job admitted for publication")
	var plan: Dictionary = planner.view()
	var bow := assigned(plan,1)
	var mounted := assigned(plan,2)
	var infantry := assigned(plan,3)
	var rider := assigned(plan,4)
	check(assigned(plan,0).is_empty() and plan.formation_tasks.size()==4,"detached output; only authorized roles assigned")
	check(bow.goal=="cover" and bow.site_id=="deck" and bow.line and bow.role=="archer","archer chooses reachable platform with sight")
	check(mounted.goal=="flank" and mounted.site_id=="lateral" and infantry.goal=="advance" and infantry.site_id=="objective","individual role assignments")
	check(rider.goal=="harass" and rider.role=="mounted_archer","mounted archer role")
	check(not los(sites[0].position,rows[5].position) and los(sites[1].position,rows[5].position),"real low wall blocks flat candidate only")
	for prior in plan.formation_tasks: check(prior.site_id!="off_mesh","unreachable terrain rejected")
	print("T-BAI-T-01 deck=",bow.site_id," cavalry=",mounted.site_id," infantry=",infantry.site_id,
		" rider=",rider.goal," first_stage_commit_us=",Time.get_ticks_usec()-started)
	# A new better-scoring platform cannot dislodge a valid locked squad assignment.
	var second := frame(61,rows)
	var forged: Dictionary = second.job.duplicate(true)
	forged.id += 100000
	check(planner.stage(forged,second.intel,sites).ok and not planner.commit().ok and planner.view()==plan and board.drain().value.is_empty(),"normal stage/commit cannot publish an invented job")
	var shifted := sites.duplicate(true)
	shifted.append({"id":"better","position":Vector3(11,4,-2),"objective":true})
	var next := planner.stage(second.job,second.intel,shifted)
	check(next.ok and assigned(next.value,1).id==bow.id and assigned(next.value,1).site_id=="deck","squad lock")
	check(planner.rollback().ok and planner.view()==plan,"rollback leaves committed plan unchanged")
	var feedback := [{"formation_id":1,"task_id":bow.id,"status":"blocked","reason":"unreachable","progress":0.1}]
	var fallback := planner.stage(second.job,second.intel,shifted,feedback)
	check(fallback.ok and assigned(fallback.value,1).id!=bow.id and assigned(fallback.value,1).site_id!="deck" and fallback.value.phase=="Adapt","L2 failure moves only affected squad")
	check(assigned(fallback.value,2).id==mounted.id and planner.commit().ok,"unaffected role keeps prior task")
	var retry := planner.stage(second.job,second.intel,sites)
	check(not retry.ok,"same tick already committed")
	for row in rows: row.morale = 10
	var third := frame(121,rows)
	var withdraw := planner.stage(third.job,third.intel,sites)
	check(withdraw.ok and withdraw.value.phase=="Retreat" and assigned(withdraw.value,3).goal=="retreat" and not assigned(withdraw.value,1).constraints.fire_allowed and planner.commit().ok,"visible contact and real BAI morale switch retreat")
	var last := frame(181,rows)
	var no_route := planner.stage(last.job,last.intel,[sites[-1]])
	check(no_route.ok and assigned(no_route.value,1).goal=="hold" and assigned(no_route.value,1).target_formation==null,"all candidate paths unreachable => hold")
	check(planner.rollback().ok,"drop fallback draft")
	print("T-BAI-T-02 fallback=",assigned(fallback.value,1).site_id," phase=",withdraw.value.phase," blocked_paths=hold")
	check(form.view(0).value.active.order_id=="hold0" and form.set_delegate(0,"ai",player,0).ok,"unchanged player hold and explicit delegation")
	var delegated := frame(241,rows)
	var added := planner.stage(delegated.job,delegated.intel,sites)
	check(added.ok and not assigned(added.value,0).is_empty(),"delegated group admitted")
	check(form.set_delegate(0,"",player,1).ok and not planner.commit().ok,"same-tick revoke aborts commit")
	check(form.view(0).value.active.order_id=="hold0" and assigned(planner.view(),0).is_empty(),"player order survives revoked draft")
	var stale_job := planner.stage(original_job,first.intel,sites)
	check(not stale_job.ok,"old tick rejected")
	var normal := frame(301,rows)
	var invalid: Dictionary = normal.intel.duplicate(true)
	invalid.own_units[1].erase("role")
	check(not planner.stage(normal.job,invalid,sites).ok,"missing role rejected")
	invalid = normal.intel.duplicate(true)
	invalid.visible_enemies[0].team_key = 0
	check(not planner.stage(normal.job,invalid,sites).ok,"friendly contact rejected")
	invalid = normal.intel.duplicate(true)
	invalid.own_units[1].order_revision += 1
	check(not planner.stage(normal.job,invalid,sites).ok,"mismatched order revision rejected")
	invalid = normal.intel.duplicate(true)
	invalid.own_units[1].ammo = 888
	check(not planner.stage(normal.job,invalid,sites).ok,"current stamp cannot authorize invented own troop data")
	check(not planner.stage(normal.job,normal.intel,[{"id":"bad","position":Vector3.INF}]).ok,"bad terrain input refused")
	check(not planner.stage(normal.job,normal.intel,sites,[{"formation_id":1,"task_id":bow.id,"status":"bogus"}]).ok,"invalid feedback refused")
	for at in range(2,301):
		check(form.advance(at).ok,"advance FORM authoritative fixed step")
	check(planner.stage(normal.job,normal.intel,sites).ok,"stage before real FORM order changes")
	var changed_order := order.duplicate(true)
	changed_order.merge({"issuer_id":"ai","order_id":"hold1","issued_tick":301,"formation_ids":[1]},true)
	check(form.issue_order(changed_order,command,0).ok and form.advance(301).ok and not planner.commit().ok,"same-tick order revision invalidates staged work")
	normal = frame(361,rows)
	var end := planner.stage(normal.job,normal.intel,[],[],true)
	check(end.ok and end.value.phase=="Finish" and end.value.formation_tasks.is_empty() and planner.commit().ok,"terminal plan")
	var pending := Tactics.new(SCOPE,0,granted,probe,live,board.collect.bind([]))
	check(pending.stage(normal.job,normal.intel,sites).ok,"pending at mission replacement")
	var old_board := board
	board = AI.new(SCOPE,los)
	var new_frame := frame(421,rows)
	var replacement := Tactics.new(SCOPE,0,granted,probe,live,board.collect.bind([]))
	check(not pending.commit().ok and pending.view().is_empty(),"old draft cannot commit after replacement")
	check(not replacement.stage(normal.job,normal.intel,sites).ok and replacement.stage(new_frame.job,new_frame.intel,sites).ok,"same name different Mission instance, stale first job denied")
	replacement.rollback()
	check(not planner.stage(new_frame.job,new_frame.intel,sites).ok,"old task planner cannot reopen")
	old_board.close()
	replacement.close()
	planner.close()
	print("T-BAI-T-03 player_order=",form.view(0).value.active.order_id," stale_scope_rejected=true")

func ties() -> void:
	form = FORM.new(SCOPE,authenticate,func(_point): return R.ok(true))
	var a := Vector3(-9,0,-8)
	var rows := [unit(0,0,"infantry",a),unit(4,0,"infantry",a),unit(11,1,"infantry",a+Vector3.RIGHT*2),unit(9,1,"infantry",a+Vector3.LEFT*2)]
	for row in rows: form.add_formation(row.formation_id,row.team_key,"ai",[row.handle])
	var alternatives := [{"id":"z","position":a},{"id":"a","position":a}]
	for round_index in 2:
		board = AI.new(SCOPE,los)
		var local := Tactics.new(SCOPE,0,granted,probe,live,board.collect.bind([]))
		var event := frame(1,rows)
		var result := local.stage(event.job,event.intel,alternatives)
		var selected := assigned(result.value,0)
		check(selected.site_id=="a" and selected.target_formation==9,"equal distances/rank independent of publication order")
		check(local.commit().ok,"tie plan commit")
		var settled := frame(61,rows)
		var confirmed := local.stage(settled.job,settled.intel,alternatives,[{"task_id":selected.id,"formation_id":0,"status":"completed","progress":1.0,"reason":"arrived"}])
		check(confirmed.value.feedback[0].status=="completed" and assigned(confirmed.value,0).id==selected.id,"matching L2 completion recorded without restart")
		local.rollback()
		var only_site := [{"id":"a","position":a}]
		var blocked := local.stage(settled.job,settled.intel,only_site,[{"task_id":selected.id,"formation_id":0,"status":"blocked","progress":0.0,"reason":"unreachable"}])
		check(assigned(blocked.value,0).site_id=="" and local.commit().ok,"failed only site yields safe hold")
		var wait_frame := frame(121,rows)
		var waiting := local.stage(wait_frame.job,wait_frame.intel,only_site)
		check(assigned(waiting.value,0).site_id=="" and local.commit().ok,"unconfirmed failed site is not immediately retried")
		var recovered := frame(241,rows)
		var probe_again := local.stage(recovered.job,recovered.intel,only_site)
		check(assigned(probe_again.value,0).site_id=="a" and local.commit().ok,"expired block allows a bounded later retry")
		local.close()
		rows.reverse()
		alternatives.reverse()

func sample(n: int) -> void:
	# L1 is scheduled once per second. Every sample goes through an actual
	# BAI team job, a FORM authorization read, real path queries and LOS.
	board = AI.new(SCOPE,los)
	form = FORM.new(SCOPE,authenticate,func(_point): return R.ok(true))
	var rows := []
	var members := {}
	var points := PackedVector3Array()
	for i in n:
		var group: int = i%20
		var team: int = group%2
		var role: String = ["infantry","infantry","infantry","infantry","infantry","archer","archer","archer","cavalry","cavalry"][group%10]
		var p := Vector3(-12+((i/20)%12)*0.65,0,-9+(i%20)*0.6)
		var row := unit(i,team,role,p)
		row.formation_id = group
		rows.append(row)
		members.get_or_add(group,[]).append(row.handle)
		points.append(p)
	for group in members: check(form.add_formation(group,group%2,"ai",members[group]).ok,"large roster FORM")
	var roster: Dictionary = board.publish(0,nav,rows)
	var local := Tactics.new(SCOPE,0,granted,probe,live,board.collect.bind([]))
	var costs: Array[int] = []
	var before_queries := queries
	var before_rays := rays
	var tasks := 0
	for i in 20:
		tick = 1+i*60
		check(board.advance(tick,nav,roster.value,points,[],[],1).ok,"batch positions")
		for id in range(0,20,2): board.sense(rows[id].handle,18,4)
		var schedule: Dictionary = board.schedule()
		for job in schedule.value.jobs:
			if job.layer!="tactical" or not is_same(job.subject,0): continue
			var start := Time.get_ticks_usec()
			var result: Dictionary = local.stage(job,board.team_view(0).value,sites)
			check(result.ok and local.commit().ok,"scheduled L1 transaction")
			costs.append(Time.get_ticks_usec()-start)
			tasks += result.value.formation_tasks.size()
	check(costs.size()==20 and tasks==200 and queries>before_queries and rays>before_rays,"L1 workload counts")
	costs.sort()
	print("TACTICS_LOAD roster=",n," own=",n/2," decisions=",costs.size()," assignments=",tasks," terrain_queries=",queries-before_queries,
		" physics_los=",rays-before_rays," stage_commit_p50_us=",costs[9]," p95_us=",costs[18]," max_us=",costs[19])
	local.close()

func transitions() -> void:
	board = AI.new(SCOPE,los)
	form = FORM.new(SCOPE,authenticate,func(_point): return R.ok(true))
	var a := Vector3(-9,0,-8)
	var rows := [unit(0,0,"archer",a),unit(1,0,"infantry",a+Vector3.RIGHT)]
	for row in rows: form.add_formation(row.formation_id,row.team_key,"ai",[row.handle])
	var local := Tactics.new(SCOPE,0,granted,probe,live,board.collect.bind([]))
	var frame0 := frame(1,rows)
	var counterfeit: Dictionary = frame0.job.duplicate(true)
	counterfeit.id += 100000
	check(not board.collect(counterfeit,[]).ok,"composition BAI disallows invented job IDs")
	var initial := local.stage(frame0.job,frame0.intel,sites)
	check(initial.value.phase=="Deploy" and assigned(initial.value,0).goal=="hold" and local.commit().ok,"pre-contact deployment")
	var enemy := unit(8,1,"infantry",a+Vector3.BACK)
	rows.append(enemy)
	form.add_formation(8,1,"hostile",[enemy.handle])
	var engage := frame(61,rows)
	var selected := local.stage(engage.job,engage.intel,sites)
	check(assigned(selected.value,0).goal=="cover" and local.commit().ok,"new permitted contact")
	rows[0].ammo = 0
	var empty := frame(121,rows)
	var dry := local.stage(empty.job,empty.intel,sites)
	check(assigned(dry.value,0).role=="archer" and assigned(dry.value,0).goal=="hold" and not assigned(dry.value,0).constraints.fire_allowed and local.commit().ok,"empty quiver changes task without changing soldier role")
	var additions := [unit(20,0,"infantry",a),unit(21,0,"infantry",a)]
	for row in additions: row.formation_id = 1
	form.assign_members(1,[rows[1].handle,additions[0].handle,additions[1].handle])
	rows.append_array(additions)
	var stronger := frame(181,rows)
	var rerouted := local.stage(stronger.job,stronger.intel,sites)
	check(rerouted.value.strength==4 and assigned(rerouted.value,1).id!=assigned(dry.value,1).id and local.commit().ok,"reinforcement triggers reassignment")
	var later := frame(721,rows)
	var renewed := local.stage(later.job,later.intel,sites)
	check(assigned(renewed.value,1).id!=assigned(rerouted.value,1).id and assigned(renewed.value,1).timeout>721 and local.commit().ok,"expired task gets a new deadline")
	rows[2].position = Vector3(100,0,100)
	var hidden := frame(781,rows)
	var lost := local.stage(hidden.job,hidden.intel,sites)
	check(hidden.intel.visible_enemies.is_empty() and assigned(lost.value,1).target_formation==null and local.commit().ok,"lost contact not retained as target")
	local.close()

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	engine = ENGINE.new(root,true)
	board = AI.new(SCOPE,los)
	form = FORM.new(SCOPE,authenticate,func(_point): return R.ok(true))
	var token: Dictionary = engine.open_scope(SCOPE)
	if not token.ok or not engine.load_scene({"id":"base:scene/tactical_fixture","simulation_scene":"res://tests/p2/tactical/arena.tscn"},token.value).ok:
		quit(1)
		return
	for i in 120:
		await physics_frame
		var sync: Dictionary = engine.sync_navigation(SCOPE)
		if sync.ok and sync.value.status=="applied":
			nav = sync.value.applied_revision
			var route: Dictionary = engine.query_path_batch([{"from":[-6000,0,0],"to":[12000,4000,0]}],nav,SCOPE)
			if route.ok and route.value[0].reachable and not los(Vector3(-5,0,0),Vector3(3,0,0)):
				break
			nav = -1
	check(nav>=0,"real flat-ramp-platform navigation and wall ready")
	if nav>=0:
		exercise()
		ties()
		transitions()
		sample(500)
		sample(1000)
	check(physical_errors==0,"all occlusion calls succeeded")
	engine.release_scope(SCOPE)
	print("FIELD_TACTICS errors=",errors," nav_queries=",queries," physical_los=",rays)
	quit(1 if errors else 0)
