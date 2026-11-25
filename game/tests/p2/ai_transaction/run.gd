extends SceneTree

const AI = preload("res://mission/ai/ports/field_ai.gd")
var checks := 0
var failures := 0
var clear := true
var probe_callback := false
var ai: RefCounted
var revision := 1

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ",label)

func los(_a: Vector3,_b: Vector3) -> bool:
	if probe_callback:
		check(not ai.begin_tick().ok, "reentrant begin rejected")
		ai.rollback_tick()
		ai.commit_tick()
		probe_callback = false
	return clear

func live(layer: String,_subject: Variant) -> Dictionary:
	return {"scope_id":"test-field"} if layer == "tactical" else {"control_revision":revision}

static func unit(id: int, team: Variant, position: Vector3, generation := 1) -> Dictionary:
	return {"handle":{"index":id,"generation":generation},"team_key":team,"formation_id":id/2,
		"role":"infantry","position":position,"hp":90,"control_revision":1,"order_revision":3}

static func signature(jobs: Array) -> Array:
	var values := []
	for job in jobs:
		values.append([job.layer,job.subject,job.urgent,job.stamp])
	return values

func _initialize() -> void:
	ai = AI.new("test-field",los,5,live)
	var rows := [unit(0,0,Vector3.ZERO),unit(1,0,Vector3(2,0,0)),
		unit(2,"0",Vector3(5,0,0)),unit(3,"0",Vector3(7,0,0))]
	var member: Dictionary = rows[0].handle
	var points := PackedVector3Array()
	for row in rows:
		points.append(row.position)
	check(ai.begin_tick().ok and not ai.begin_tick().ok,"single live transaction")
	var discarded: Dictionary = ai.publish(1,1,rows).value
	var abandoned: Array = ai.schedule().value.jobs
	ai.rollback_tick()
	check(not ai.team_view(0).ok and ai.metrics().issued_total==0,"rollback first publish")
	ai.rollback_tick()
	check(ai.begin_tick().ok,"reopen initial tick")
	var roster: Dictionary = ai.publish(1,1,rows).value
	check(not ai.advance(2,1,discarded,points).ok,"discarded roster cannot advance replay")
	var first: Array = ai.schedule().value.jobs
	check(signature(first)==signature(abandoned),"same first jobs and scout stamps")
	check(not ai.collect(abandoned[0],[]).ok,"discarded job denied on replay")
	ai.commit_tick()
	ai.rollback_tick()
	var accepted: Dictionary
	var outstanding: Dictionary
	for job in first:
		if job.layer=="individual" and job.subject==member:
			accepted=job
		elif job.layer=="formation":
			outstanding=job
	var intent := {"actor_handle":member,"move":{"speed":2}}
	check(ai.collect(accepted,[intent]).ok,"accepted before checkpoint")
	var old_sight: Dictionary = ai.sense(member,18.0,2).value
	var old_team: Dictionary = ai.team_view(0).value
	var stats: Dictionary = ai.metrics()
	check(ai.begin_tick().ok,"open tick after accepting a result")
	var carried: Array=ai.drain().value
	check(carried.size()==1 and is_same(carried[0].job,accepted),"drained original accepted grant")
	carried[0].intents[0].move.speed=999
	# Mutate observations on the committed board, then cross several spatial cells.
	clear=false
	ai.sense(rows[1].handle,6.0,1)
	var next := PackedVector3Array([Vector3(23,0,0),Vector3(25,0,0),Vector3(24,0,0),Vector3(80,0,0)])
	check(ai.advance(2,2,roster,next,[member],[{"handle":member,"hp":10}],8).ok,"advance changed nav, health and urgency")
	probe_callback=true
	var changed: Dictionary = ai.sense(member,18.0,2).value
	check(changed.self.hp==10 and changed.self.position==next[0] and changed.visible_enemies.is_empty(),"candidate health and new occlusion")
	var due: Dictionary = ai.schedule({"individual":1,"urgent":1}).value
	var work: Dictionary=due.jobs[0]
	check(ai.collect(work,[]).ok and ai.drain().value.size()==1,"consume candidate result")
	var replacement: Array = rows.duplicate(true)
	replacement[0].handle.generation=2
	check(ai.publish(3,3,replacement).ok and ai.schedule().ok,"generation and schedule replacements")
	ai.rollback_tick()
	check(ai.metrics()==stats,"restore all published counters")
	check(ai.team_view(0).value==old_team and ai.team_view("0").ok,"original typed teams and observations")
	check(is_same(ai.sense(member,18.0,2).value,old_sight),"original cached view identity")
	check(ai.team_view(0).value.own_units[0].position==points[0] and ai.team_view(0).value.own_units[0].hp==90,"restore prior movement and health")
	var restored: Array=ai.drain().value
	check(restored.size()==1 and is_same(restored[0].job,accepted) and restored[0].intents==[intent],"restore original accepted intents without an escaped mutation")
	revision=2
	check(not ai.collect(outstanding,[]).ok,"revoked permission still checked after rollback")
	revision=1
	check(ai.collect(outstanding,[]).ok and is_same(ai.drain().value[0].job,outstanding),"unconsumed grant identity restored")
	check(ai.begin_tick().ok and ai.advance(2,2,roster,next,[member],[{"handle":member,"hp":10}],8).ok,"original token can replay in same tick")
	ai.sense(member,18.0,2)
	var retry: Dictionary = ai.schedule({"individual":1,"urgent":1}).value
	check(signature(retry.jobs)==signature(due.jobs) and retry.backlog==due.backlog,"same due clocks, debt, emergencies and order")
	check(not ai.collect(work,[]).ok and ai.collect(retry.jobs[0],[]).ok,"abandoned worker grant cannot consume replacement")
	ai.commit_tick()
	check(ai.begin_tick().ok and ai.publish(3,3,rows).ok,"discarded higher generation never poisons later publish")
	check(ai.schedule().ok,"calendar retains its new committed cadence")
	ai.commit_tick()
	check(ai.begin_tick().ok and ai.close().ok,"dispose outstanding transaction")
	ai.rollback_tick()
	check(not ai.begin_tick().ok and not ai.sense(member).ok,"cannot revive a disposed scope")
	check(cadence_after_retry(),"1000-member steady roster retains deadlines through repeated rollback")
	print("AI_TRANSACTION checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func cadence_after_retry() -> bool:
	clear = true
	var tested := AI.new("cadence",los)
	var control := AI.new("cadence",los)
	var rows := []
	var points := PackedVector3Array()
	for i in 1000:
		var p := Vector3(i%40,0,i/40)
		var row := unit(i,i%2,p)
		row.formation_id = (i%2)*4 + (i/2)%4
		rows.append(row)
		points.append(p)
	var a: Dictionary = tested.publish(0,1,rows).value
	var b: Dictionary = control.publish(0,1,rows).value
	for tick in range(1,76):
		points[0] += Vector3(1,0,0)
		var urgent := [rows[tick].handle]
		if tick % 4 == 0:
			if not tested.begin_tick().ok or not tested.advance(tick,1,a,points,urgent,[],1).ok:
				return false
			if not tested.schedule({"individual":1,"urgent":0}).ok:
				return false
			tested.sense(rows[0].handle)
			tested.rollback_tick()
		if not tested.begin_tick().ok or not tested.advance(tick,1,a,points,urgent,[],1).ok or not control.advance(tick,1,b,points,urgent,[],1).ok:
			return false
		var scheduled: Dictionary = tested.schedule().value
		var reference: Dictionary = control.schedule().value
		if scheduled.backlog!=reference.backlog or scheduled.jobs.size()!=reference.jobs.size():
			return false
		for i in scheduled.jobs.size():
			var job: Dictionary = scheduled.jobs[i]
			var other: Dictionary = reference.jobs[i]
			if [job.layer,job.subject,job.urgent]!=[other.layer,other.subject,other.urgent]:
				return false
		var p: Dictionary = tested.sense(rows[0].handle).value
		var q: Dictionary = control.sense(rows[0].handle).value
		if p.visible_enemies!=q.visible_enemies or p.nearby_allies!=q.nearby_allies:
			return false
		var stats := tested.metrics()
		var expected := control.metrics()
		stats.erase("los_us")
		expected.erase("los_us")
		if stats!=expected:
			return false
		tested.commit_tick()
	return true
