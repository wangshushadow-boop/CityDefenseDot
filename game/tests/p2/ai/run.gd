extends SceneTree
const AI = preload("res://mission/ai/ports/field_ai.gd")
const Combat = preload("res://mission/combat/ports/field_combat.gd")
const Movement = preload("res://mission/movement/ports/field_movement.gd")
const Formation = preload("res://mission/formation/ports/field_formation.gd")
const EnginePort = preload("res://infrastructure/engine/adapter.gd")
const R = preload("res://contracts/result.gd")
const SCOPE := "p2-ai-real-field"
var engine: RefCounted
var player := RefCounted.new()
var captain := RefCounted.new()
var failed := 0
var los_errors := 0
var form: RefCounted

func check(ok: bool, label: String) -> void:
	if not ok:
		failed += 1
		printerr("FAIL ",label)

static func handle(i: int) -> Dictionary:
	return {"index":i,"generation":1}

static func mm(p: Vector3) -> Array:
	return [roundi(p.x*1000),roundi(p.y*1000),roundi(p.z*1000)]

func los(a: Vector3,b: Vector3) -> bool:
	if a.is_equal_approx(b):
		return true
	var ray: Dictionary = engine.query_sweep_batch([{"from":mm(a+Vector3.UP),"to":mm(b+Vector3.UP),"mask":4}],{"scope_id":SCOPE,"tick":1})
	if not ray.ok:
		los_errors += 1
	return ray.ok and ray.value.is_empty()

func auth(token: Variant) -> Dictionary:
	if is_same(token,player):
		return R.ok("player")
	if is_same(token,captain):
		return R.ok("captain")
	return R.fail("Unauthorized")

func live(layer: String, subject: Variant) -> Dictionary:
	if layer == "formation":
		return {"control_revision":form.view(subject).value.control_revision}
	return {"scope_id":SCOPE}

func order(who: String, kind: String) -> Dictionary:
	return {"mission_id":SCOPE,"issuer_id":who,"order_id":who+"1","client_sequence":1,
		"issued_tick":1,"formation_ids":[0],"order_type":kind,"parameters":{},
		"target_formation_id":null,"target_position":null}

static func unit(i: int, team: int, f: int, p: Vector3, role: String="infantry") -> Dictionary:
	return {"handle":handle(i),"team_key":team,"formation_id":f,"position":p,"role":role,
		"control_revision":0,"order_revision":0}

func domains() -> bool:
	var start := failed
	formation_targets()
	var com := Combat.new()
	var mov := Movement.new(engine,SCOPE)
	form = Formation.new(SCOPE,auth,func(_p): return R.ok(true))
	form.add_formation(0,0,"player",[handle(0)])
	form.add_formation(1,1,"enemy",[handle(1),handle(2)])
	var rows := []
	for i in 3:
		var team := 0 if i==0 else 1
		var p: Vector3 = [Vector3(-4,0,0),Vector3(4,0,0),Vector3(-3,0,2)][i]
		com.enlist(handle(i),{"team":team,"role":"infantry"})
		mov.spawn(handle(i),p)
		var r := unit(i,team,team,mov.view(handle(i)).value.position)
		r.hp = com.view(handle(i)).value.hp
		rows.append(r)
	check(form.set_delegate(0,"captain",player,0).ok,"grant actual FORM authority")
	rows[0].control_revision = form.view(0).value.control_revision
	rows[0].urgent = true
	var ai := AI.new(SCOPE,los,60,live)
	if not ai.publish(1,1,rows).ok:
		return false
	check(ai.team_view(0).value.visible_enemies.is_empty(),"empty intelligence before sight")
	var view: Dictionary = ai.sense(handle(0)).value
	check(view.visible_enemies.size()==1 and view.visible_enemies[0].handle==handle(2),"wall hides only the far opponent")
	check(not view.visible_enemies[0].has("hp") and view.self.hp==100,"enemy state whitelist")
	check(view.is_read_only() and view.visible_enemies.is_read_only() and view.visible_enemies[0].handle.is_read_only(),"immutable view")
	rows[2].position = Vector3(-50,0,0)
	check(ai.formation_view(0).value.visible_enemies[0].position==Vector3(-3,0,2),"snapshot detached")
	check(ai.team_view(1).value.visible_enemies.is_empty(),"team observations stay scoped")
	var selected: Dictionary = ai.schedule()
	check(not ai.schedule().ok,"second schedule cannot double spend")
	var actor_job := {}
	var form_job := {}
	for job in selected.value.jobs:
		if job.layer == "individual" and job.subject == handle(0):
			actor_job = job
		if job.layer == "formation" and job.subject == 0:
			form_job = job
	if actor_job.is_empty() or form_job.is_empty():
		return false
	check(actor_job.urgent,"shield reaction dispatched in emergency quota")
	check(not ai.collect(actor_job,[{"actor_handle":handle(0),"target_hint":handle(1)}]).ok,"invisible target denied")
	check(not ai.collect(actor_job,[{"actor_handle":handle(1)}]).ok,"foreign actor denied")
	var bad_stamp: Dictionary = actor_job.duplicate(true)
	bad_stamp.stamp.nav_revision += 1
	check(not ai.collect(bad_stamp,[]).ok,"forged nav revision rejected")
	var guard := {"actor_handle":handle(0),"held":true,"direction":"up"}
	check(ai.collect(actor_job,[guard]).ok and not ai.collect(actor_job,[guard]).ok,"single submit")
	guard.direction = "left"
	check(ai.collect(form_job,[order("captain","retreat")]).ok,"formation proposal")
	var actual_guard := []
	var batches: Array = ai.drain().value
	check(batches.size()==2 and batches[0].job.id<batches[1].job.id,"stable collection despite reverse completion")
	for batch in batches:
		if batch.job.layer=="formation":
			check(form.issue_order(batch.intents[0],captain,batch.job.stamp.control_revision).ok,"AI through actual FORM")
		else:
			actual_guard = batch.intents
	check(form.issue_order(order("player","hold"),player,1).ok and form.advance(1).ok and form.view(0).value.active.order_type=="hold","player priority on same authority")
	check(com.step_field(1,actual_guard,{},Callable()).ok and com.view(handle(0)).value.phase=="Guard" and com.view(handle(0)).value.direction=="up","copied intent executed by actual COM")
	rows[0].handle = {"index":0,"generation":2}
	check(ai.publish(2,2,rows).ok and not ai.sense(handle(0)).ok and not ai.collect(actor_job,[]).ok,"replacement handle and stale output")
	check(ai.team_view(0).value.visible_enemies.is_empty(),"prior tick contacts expire")
	var delegated := AI.new(SCOPE,los,60,live)
	delegated.publish(1,2,rows)
	for job in delegated.schedule().value.jobs:
		if job.layer=="formation" and job.subject==0:
			check(delegated.collect(job,[order("captain","retreat")]).ok,"current revision admitted")
	form.set_delegate(0,"",player,1)
	check(delegated.drain().value.is_empty(),"revocation rechecked before dispatch")
	print("T-BAI-01/02 FORM+COM+MOV real_occlusion=true errors=",failed-start)
	return failed == start

func formation_targets() -> void:
	var ai := AI.new(SCOPE,func(_a,_b):return true)
	var rows := [unit(0,0,0,Vector3.ZERO),unit(1,0,1,Vector3.RIGHT),unit(2,0,2,Vector3.BACK)]
	rows[2].team_key = "0"
	check(ai.publish(1,0,rows).ok,"target roster")
	for job in ai.schedule().value.jobs:
		if job.layer!="formation" or job.subject!=0:
			continue
		var friendly := order("captain","follow")
		friendly.target_formation_id = 2
		check(not ai.collect(job,[friendly]).ok,"cannot follow even a visible enemy")
		friendly.target_formation_id = 0
		check(not ai.collect(job,[friendly]).ok,"cannot follow self")
		friendly.target_formation_id = 1
		var attack := friendly.duplicate(true)
		attack.order_type = "charge"
		check(not ai.collect(job,[attack]).ok,"cannot charge ally")
		check(ai.collect(job,[friendly]).ok,"follow another friendly formation")
	ai.close()

class Delayed:
	extends RefCounted
	var started := Semaphore.new()
	var release := Semaphore.new()
	var result: Dictionary
	func calculate(job: Dictionary) -> void:
		started.post()
		release.wait()
		result = {"job":job,"intents":[{"actor_handle":job.subject,"held":true,"direction":"up"}]}

func teardown_worker() -> bool:
	var rows := [unit(0,0,0,Vector3.ZERO)]
	var old := AI.new("reused",los)
	old.publish(0,1,rows)
	var chosen: Dictionary = old.schedule().value.jobs.back()
	var delayed := Delayed.new()
	var task := WorkerThreadPool.add_task(delayed.calculate.bind(chosen))
	delayed.started.wait()
	var retired := old.close()
	var next := AI.new("reused",los)
	next.publish(0,1,rows)
	next.schedule()
	delayed.release.post()
	WorkerThreadPool.wait_for_task_completion(task)
	var yes: bool = retired.ok and not old.collect(delayed.result.job,delayed.result.intents).ok and not next.collect(delayed.result.job,delayed.result.intents).ok and next.drain().value.is_empty()
	print("T-BAI-04 threaded_late_result_rejected=",yes)
	return yes

func incremental_visibility() -> void:
	var ai := AI.new(SCOPE,los)
	var a := Vector3(-4,0,0)
	var b := Vector3(4,0,0)
	var rows := [unit(0,0,0,a),unit(1,1,1,b)]
	var roster: Dictionary = ai.publish(0,1,rows).value
	var positions := PackedVector3Array([a,b])
	check(not ai.advance(1,1,roster.duplicate(),positions).ok,"foreign roster token")
	check(not ai.advance(1,1,roster,positions,[],[{"handle":handle(0),"hp":-1}]).ok,"reject invalid delta atomically")
	check(ai.advance(1,1,roster,positions,[handle(0),handle(1)],[{"handle":handle(0),"hp":31}],1).ok,"retry valid delta")
	var old: Dictionary = ai.sense(handle(0)).value
	check(old.visible_enemies.is_empty() and old.self.hp==31,"wall initially blocked")
	ai.sense(handle(0))
	check(ai.metrics().rays==1 and ai.metrics().cache_hits==1,"same-tick cache")
	var limited: Dictionary = ai.schedule({"urgent":1,"individual":0,"formation":0,"tactical":0}).value
	check(limited.jobs.size()==1 and limited.jobs[0].subject==handle(0) and limited.backlog.urgent==1,"single emergency budget")
	check(ai.advance(2,1,roster,positions,[],[],1).ok,"new tick same visibility epoch")
	check(ai.sense(handle(0)).value.visible_enemies.is_empty() and ai.metrics().rays==0,"unchanged endpoints reuse a ray")
	var carried: Dictionary = ai.schedule({"urgent":1,"individual":0,"formation":0,"tactical":0}).value
	check(carried.jobs.size()==1 and carried.jobs[0].subject==handle(1),"deferred emergency survives next snapshot")
	var wall := get_first_node_in_group("ai_test_wall") as StaticBody3D
	wall.position.z = 18
	await physics_frame
	await physics_frame
	check(ai.advance(3,1,roster,positions,[],[],2).ok,"advance occluder epoch")
	check(ai.sense(handle(0)).value.visible_enemies.size()==1 and ai.metrics().rays==1,"moving real wall invalidates formerly hidden contact")
	check(not ai.advance(4,1,roster,positions,[],[],1).ok,"stale occluder epoch rejected")
	wall.position.z = 0
	await physics_frame
	await physics_frame
	ai.advance(4,2,roster,positions,[],[],2)
	check(ai.sense(handle(0)).value.visible_enemies.is_empty() and ai.metrics().rays==1,"nav revision invalidates positive sight")
	positions[0] = Vector3(-5,0,0)
	var before := ai.sense(handle(0)).value as Dictionary
	ai.advance(5,2,roster,positions,[],[],2)
	check(old.self.position==a and before.self.position==a and ai.sense(handle(0)).value.self.position==positions[0] and ai.metrics().rays==1,"moved endpoint, immutable prior snapshots")
	ai.advance(18,2,roster,positions,[],[],2)
	ai.sense(handle(0))
	check(ai.metrics().rays==1,"TTL expires without obstacle changes")
	ai.publish(19,2,[])
	check(not ai.publish(20,2,rows).ok and not ai.advance(20,2,roster,positions).ok,"retired handle and roster rejected")
	print("T-BAI-02 dynamic_wall=true ttl=12 emergency_debt_repaid=true")

func threat_cadence() -> void:
	var ai := AI.new(SCOPE,los)
	var rows := [unit(0,0,0,Vector3(-4,0,0)),unit(1,1,1,Vector3(-4,0,1))]
	rows[0].hp = 20
	var roster: Dictionary = ai.publish(0,1,rows).value
	var positions := PackedVector3Array([rows[0].position,rows[1].position])
	var count := [0,0]
	var groups := [0,0]
	for tick in range(1,121):
		ai.advance(tick,1,roster,positions,[],[],1)
		var work: Dictionary = ai.schedule().value
		for job in work.jobs:
			if job.layer=="individual":
				count[job.subject.index] += 1
				ai.sense(job.subject)
			elif job.layer=="formation":
				groups[job.subject] += 1
	check(count[0]>=18 and count[1]==10 and groups[0]>=9,"local threat raises decision rate within budget")
	print("BAI_CADENCE two_seconds critical/normal=",count," threatened_squads=",groups)

func bounded_contact_order() -> void:
	var ai := AI.new(SCOPE,los)
	var p := Vector3(-8,0,0)
	var rows := [unit(0,0,0,p),unit(0xffffffff,1,1,p+Vector3.RIGHT),
		unit(0xfffffffe,1,1,p+Vector3.LEFT),unit(0x1000001,1,1,p+Vector3.BACK*0.5)]
	check(ai.publish(0,1,rows).ok,"wide handle fixture")
	var contacts: Array = ai.sense(handle(0),4,2).value.visible_enemies
	check(contacts.size()==2 and contacts[0].handle.index==0x1000001 and contacts[1].handle.index==0xfffffffe,"nearest then full-width handle on equal distance")

func mixed_load(n: int) -> bool:
	var ai := AI.new(SCOPE,los)
	var mov := Movement.new(engine,SCOPE)
	var com := Combat.new()
	var rows := []
	var origin := Vector3(-6,0,0)
	var jobs_count := {"tactical":0,"formation":0,"individual":0}
	var seen := 0
	var reactions := 0
	var inspected := 0
	var rays := 0
	var inputs := 0
	var max_backlog := 0
	var all_cost: Array[int] = []
	var ai_cost: Array[int] = []
	var publish_us := 0
	var schedule_us := 0
	var decisions_us := 0
	var los_us := 0
	var cache_hits := 0
	var movement_us := 0
	var movement_begin_us := 0
	var movement_commit_us := 0
	var projection_us := 0
	var combat_us := 0
	var combat_fork_us := 0
	var scouts := 0
	var group_contacts := 0
	var full_publish := "--full-publish" in OS.get_cmdline_user_args()
	var legacy_read := "--legacy-read" in OS.get_cmdline_user_args()
	var handles := []
	for g in 20:
		var profile := "mounted" if g%10 >= 8 else "foot"
		mov.set_corridor(str(g),origin,origin+Vector3(16,0,0),profile)
	for i in n:
		var group := i%20
		var team := i%2
		var role := "infantry" if group%10 < 5 else ("archer" if group%10 < 8 else "cavalry")
		var p := Vector3(-48+(i%40)*2.15,0,-25+floori(i/40.0)*2.0)
		var row := unit(i,team,group,p,role)
		if not com.enlist(row.handle,{"team":team,"role":role}).ok or not mov.spawn(row.handle,p,"mounted" if role=="cavalry" else "foot",Vector3.RIGHT).ok or not mov.assign(row.handle,str(group),p-origin).ok:
			return false
		rows.append(row)
		handles.append(row.handle)
	var movement_roster := mov.bind_roster(handles)
	if not movement_roster.ok:
		return false
	var nav_revision := 0
	# Finish the real shared-route/member admission before timing decisions.
	for warm in ceili(n/8.0)+6:
		var result := mov.stage_step(warm,1.0/60)
		if not result.ok or not mov.commit_step(result.value.stage_token).ok:
			return false
		nav_revision = result.value.nav_revision
	var start_tick := ceili(n/8.0)+6
	var published_roster := ai.publish(0,nav_revision,rows)
	var positions := PackedVector3Array()
	positions.resize(n)
	if not published_roster.ok:
		return false
	for tick in range(1,121):
		var start := Time.get_ticks_usec()
		var opened := mov.begin_step(start_tick+tick)
		if not opened.ok:
			return false
		var prepared := Time.get_ticks_usec()
		var moved_draft := mov.stage_step(start_tick+tick,1.0/60,opened.value)
		if not moved_draft.ok:
			return false
		var moved := Time.get_ticks_usec()
		if legacy_read:
			for i in n:
				var pose := mov.view(handles[i],opened.value)
				if not pose.ok:
					return false
				positions[i] = pose.value.position
		else:
			var snapshot := mov.read_positions(movement_roster.value,opened.value)
			if not snapshot.ok or snapshot.value.size()!=n:
				return false
			positions = snapshot.value
		var begin_ai := Time.get_ticks_usec()
		movement_begin_us += prepared-start
		movement_us += moved-prepared
		projection_us += begin_ai-moved
		nav_revision = moved_draft.value.nav_revision
		if full_publish:
			for i in n:
				rows[i].position = positions[i]
				rows[i].urgent = i==(tick*7)%n
			if not ai.publish(tick,nav_revision,rows).ok:
				return false
		elif not ai.advance(tick,nav_revision,published_roster.value,positions,[rows[(tick*7)%n].handle],[],1).ok:
			return false
		var published := Time.get_ticks_usec()
		var scheduled := ai.schedule().value as Dictionary
		var dispatched := Time.get_ticks_usec()
		publish_us += published-begin_ai
		schedule_us += dispatched-published
		for debt in scheduled.backlog.values():
			max_backlog = maxi(max_backlog,debt)
		for job in scheduled.jobs:
			jobs_count[job.layer] += 1
			var output := []
			if job.layer == "individual":
				var sensed: Dictionary = ai.sense(job.subject,12,2).value
				seen += sensed.visible_enemies.size()
				if job.urgent:
					reactions += 1
				if not sensed.visible_enemies.is_empty():
					# A fixed reaction driver isolates BAI's actual sensing/dispatch costs.
					output.append({"actor_handle":job.subject,"held":true,"direction":"up"})
			else:
				var group: Dictionary = ai.formation_view(job.subject).value if job.layer=="formation" else ai.team_view(job.subject).value
				group_contacts += group.visible_enemies.size()
				if group.own_units.is_empty():
					return false
			if not ai.collect(job,output).ok:
				return false
		var work: Array = ai.drain().value
		var consumed := []
		for batch in work:
			consumed.append_array(batch.intents)
		var m := ai.metrics()
		decisions_us += Time.get_ticks_usec()-dispatched
		inspected += m.examined
		rays += m.rays
		cache_hits += m.cache_hits
		los_us += m.los_us
		scouts += m.scouts
		ai_cost.append(Time.get_ticks_usec()-begin_ai)
		var begin_combat := Time.get_ticks_usec()
		var combat_draft: RefCounted = com.fork()
		var forked := Time.get_ticks_usec()
		var applied: Dictionary = combat_draft.step_field(tick,consumed,{},Callable())
		if not applied.ok or applied.value.receipts.size()!=consumed.size():
			return false
		for receipt in applied.value.receipts:
			if not receipt.ok:
				return false
		inputs += consumed.size()
		var checked := Time.get_ticks_usec()
		if not mov.commit_step(opened.value).ok:
			return false
		com = combat_draft
		combat_fork_us += forked-begin_combat
		combat_us += checked-forked
		movement_commit_us += Time.get_ticks_usec()-checked
		all_cost.append(Time.get_ticks_usec()-start)
	ai_cost.sort()
	all_cost.sort()
	print("BAI_LOAD people=",n," ticks=120 hz=60 full_publish=",full_publish," legacy_read=",legacy_read," jobs=",jobs_count," urgent=",reactions,
		" examined=",inspected," physical_los=",rays," contacts=",seen," com_inputs=",inputs,
		" max_backlog=",max_backlog," ai_p50_us=",ai_cost[59]," ai_p95_us=",ai_cost[113],
		" ai_p99_us=",ai_cost[118]," combined_p95_us=",all_cost[113]," cpu_budget=","PASS" if all_cost[113]<=16667 else "FAIL")
	print("BAI_MEAN_US people=",n," publish=",publish_us/120.0," schedule=",schedule_us/120.0,
		" decisions=",decisions_us/120.0," los_inclusive=",los_us/120.0," cache_hits=",cache_hits,
		" scouts=",scouts," group_contacts=",group_contacts," mov_begin=",movement_begin_us/120.0,
		" mov_step=",movement_us/120.0," project_mov=",projection_us/120.0,
		" com_fork=",combat_fork_us/120.0," com_step=",combat_us/120.0," commit_and_publish=",movement_commit_us/120.0)
	if "--functional-only" not in OS.get_cmdline_user_args():
		check(all_cost[113]<=16667,str(n)+" combined fixed-step P95 <= 16.667ms")
	if not full_publish:
		var expected: Array = [254439,10504,10239,5120,5120] if n==500 else [494511,20501,20226,10114,10120]
		check([inspected,rays,seen,inputs,jobs_count.individual]==expected,"reference mixed field workload")
	return seen>0 and inputs>0 and group_contacts>0 and jobs_count.individual>=n*9 and reactions==120 and max_backlog==0 and inspected<=(jobs_count.individual+scouts)*48

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	engine = EnginePort.new(root,true)
	var token: Dictionary = engine.open_scope(SCOPE)
	if not token.ok or not engine.load_scene({"id":"base:scene/ai_fixture","simulation_scene":"res://tests/p2/ai/arena.tscn"},token.value).ok:
		quit(1)
		return
	var ready := false
	for frame in 120:
		await physics_frame
		var sync: Dictionary = engine.sync_navigation(SCOPE)
		if sync.ok and sync.value.status=="applied":
			var path: Dictionary = engine.query_path_batch([{"from":[-10000,0,0],"to":[-2000,0,0]}],sync.value.applied_revision,SCOPE)
			if path.ok and path.value[0].reachable and not los(Vector3(-4,0,0),Vector3(4,0,0)):
				ready = true
				break
	check(ready,"real mesh and wall loaded")
	if ready:
		check(domains(),"domain scenario")
		check(teardown_worker(),"async scope teardown")
		await incremental_visibility()
		threat_cadence()
		bounded_contact_order()
		check(mixed_load(500),"500 mixed active actors")
		check(mixed_load(1000),"1000 mixed active actors")
	engine.release_scope(SCOPE)
	check(los_errors==0,"LOS succeeded")
	print("FIELD_AI errors=",failed)
	quit(1 if failed else 0)
