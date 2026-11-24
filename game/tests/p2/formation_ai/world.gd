extends RefCounted
const Brain = preload("res://mission/ai/formation/ports/field_formation_ai.gd")
const AI = preload("res://mission/ai/ports/field_ai.gd")
const Combat = preload("res://mission/combat/ports/field_combat.gd")
const Movement = preload("res://mission/movement/ports/field_movement.gd")
const Formation = preload("res://mission/formation/ports/field_formation.gd")
const R = preload("res://contracts/result.gd")
const SCOPE := "formation-ai"
var engine: RefCounted
var nav: int
var verify: Callable
var player := RefCounted.new()
var captain := RefCounted.new()
var form: RefCounted
var ai: RefCounted
var combat: RefCounted
var mov: RefCounted
var brain: RefCounted
var groups := {}
var roles := {}
var revision := 0
var tick := 0
var sequence := 0
var projected := 0

func _init(adapter: RefCounted, version: int, check: Callable) -> void:
	engine = adapter
	nav = version
	verify = check
	form = Formation.new(SCOPE, auth, reachable)
	ai = AI.new(SCOPE, los, 5, live)
	combat = Combat.new(SCOPE)
	mov = Movement.new(engine,SCOPE)
	brain = Brain.new(SCOPE,"captain",ai.formation_view,form.view,0,ai.collect)

static func h(index: int) -> Dictionary:
	return {"index":index,"generation":1}

static func mm(p: Vector3) -> Array:
	return [roundi(p.x*1000), roundi(p.y*1000), roundi(p.z*1000)]

static func meters(p: Array) -> Vector3:
	return Vector3(p[0],p[1],p[2])*.001

func auth(token: Variant) -> Dictionary:
	if is_same(token,player): return R.ok("player")
	if is_same(token,captain): return R.ok("captain")
	return R.fail("Unauthorized")

func pos(index: int) -> Vector3:
	return mov.view(h(index)).value.position

func reachable(id: int, dest: Array) -> bool:
	var start := pos(groups[id][0].index)
	var reply: Dictionary = engine.query_path_batch([{"from":mm(start),"to":dest}],nav,SCOPE)
	return reply.ok and reply.value[0].reachable

func los(a: Vector3, b: Vector3) -> bool:
	if a.is_equal_approx(b): return true
	var ray: Dictionary = engine.query_sweep_batch([{"from":mm(a+Vector3.UP),"to":mm(b+Vector3.UP),"mask":4}],{"scope_id":SCOPE,"tick":tick})
	return ray.ok and ray.value.is_empty()

func live(layer: String, subject: Variant) -> Dictionary:
	if layer == "formation":
		return {"control_revision":form.view(subject).value.control_revision,"order_revision":revision}
	return {"scope_id":SCOPE}

func deploy(id: int, indices: Array, positions: Array, role: String, ammo: int, fragile := false, camp := -1) -> void:
	var team := id if camp < 0 else camp
	var handles := []
	for i in indices.size():
		var handle := h(indices[i])
		handles.append(handle)
		roles[handle.index] = role
		verify.call(mov.spawn(handle,positions[i]).ok,"MOV spawn")
		var hp := 5 if fragile and i == 0 else 100
		verify.call(combat.enlist(handle,{"role":role, "team":team,"hp":hp,"ammo":ammo}).ok,"COM enlist")
	groups[id] = handles
	verify.call(form.add_formation(id,team,"player" if team==0 else "enemy",handles).ok,"FORM deploy")
	if id==0:
		verify.call(form.set_delegate(0,"captain",player,0).ok,"FORM delegate")

func to_tick(t: int) -> void:
	while tick < t:
		tick += 1
		verify.call(form.advance(tick).ok,"FORM tick")

func publish(t: int) -> Dictionary:
	to_tick(t)
	var rows := []
	for id: int in groups:
		var group: Dictionary = form.view(id).value
		var people: Array = group.members
		var members: Array = combat.field_view(SCOPE,people,0).value.actors
		var points: PackedVector3Array = mov.read_positions(mov.bind_roster(people).value).value
		for i in people.size():
			rows.append({"handle":people[i],"team_key":group.team_key,"formation_id":id,"position":points[i],"role":members[i].role,
				"hp":members[i].hp,"ammo":members[i].ammo,"morale":members[i].morale,
				"control_revision":group.control_revision,"order_revision":revision})
	verify.call(ai.publish(t,nav,rows).ok,"publish actual domain views")
	var scheduled: Dictionary = ai.schedule()
	verify.call(scheduled.ok,"schedule")
	var selected := {}
	for job: Dictionary in scheduled.value.jobs:
		if job.layer == "formation" and job.subject == 0: selected.formation = job
		if job.layer == "tactical" and job.subject == 0: selected.tactical = job
	verify.call(selected.has("formation"),"own formation job due")
	return selected

func task(goal: String, role: String, point: Variant = null, target: Variant = null) -> Dictionary:
	return {"id":"task-0","formation_id":0,"priority":1,"completion":"executed","timeout":10000,
		"control_revision":form.view(0).value.control_revision,"constraints":{"engage_allowed":true,"fire_allowed":true},
		"goal":goal,"role":role,"position":point,"target_formation":target}

func center() -> Vector3:
	var p := Vector3.ZERO
	for handle in groups[0]: p+=pos(handle.index)
	return p/float(groups[0].size())

func project(points: PackedVector3Array, start: Vector3) -> Dictionary:
	var requests := []
	for p in points: requests.append({"from":mm(start),"to":mm(p)})
	var reply: Dictionary = engine.query_path_batch(requests,nav,SCOPE)
	if not reply.ok: return reply
	var out := PackedVector3Array()
	for path in reply.value:
		if not path.reachable: return R.fail("Unavailable","terrain")
		out.append(meters(path.points[-1]))
	projected += out.size()
	return R.ok(out)

func ground() -> Dictionary:
	var start := center()
	var width := 1.0
	for radius: float in [.5,1.0,2.0]:
		var a := start + Vector3.RIGHT*radius
		var b := start - Vector3.RIGHT*radius
		var ends := project(PackedVector3Array([a,b]),start)
		if ends.ok and ends.value[0].distance_to(a)<.05 and ends.value[1].distance_to(b)<.05:
			width = 2.0*radius
	return {"clear_width":width,"spacing":1.0,"slot_error":0.0,"yaw":0.0,"reachable":true}

func layout(result: Dictionary) -> Dictionary:
	var slot: Dictionary = result.slot_request
	return form.build_slot_targets(slot.formation_id,slot.center,slot.yaw,slot.spacing,slot.clear_width,project.bind(slot.center))

func collect(job: Dictionary, d: Dictionary) -> Dictionary:
	var accepted: Dictionary = brain.collect(d.token)
	verify.call(accepted.ok,"real BAI grant acceptance")
	var rows: Array = ai.drain().value
	verify.call(rows.size()==1,"one drained row")
	verify.call(rows.size()==1 and is_same(rows[0].job,job),"drained actual grant")
	return rows[0] if rows.size()==1 else {}

func finish(d: Dictionary, row: Dictionary) -> void:
	verify.call(brain.validate(d.token,row).ok,"preflight")
	for order in row.intents:
		verify.call(form.issue_order(order,captain,d.control_revision).ok,"authenticated v1 order")
	verify.call(brain.commit(d.token,row).ok,"commit L2")
	to_tick(tick+1)
	for order in row.intents:
		var status: Dictionary = form.order_status("captain",order.order_id).value[0]
		verify.call(status.state=="Active","authority executed " + order.order_type)
	sequence += row.intents.size()
	if not row.intents.is_empty(): revision += 1

func decide(job: Dictionary, task_value: Variant) -> Dictionary:
	var result: Dictionary = brain.stage(job,task_value,ground(),sequence+1)
	verify.call(result.ok,"decision")
	if not result.ok: return {}
	var d: Dictionary = result.value
	finish(d,collect(job,d))
	return d

func shoot(attacker: int, victim: int) -> void:
	var poses := {}
	for id in groups:
		for actor in groups[id]:
			poses[actor.index] = {"position_mm":mm(pos(actor.index)),"facing_ppm":[0,0,1000000]}
	var sweep := func(queries: Array,t: int):
		var reply: Dictionary = engine.query_sweep_batch(queries,{"scope_id":SCOPE,"tick":t})
		if not reply.ok: return reply
		var hits := []
		for s: Dictionary in reply.value:
			var hit := {"query_index":s.query_index,"fraction_ppm":s.fraction_ppm,"region":s.region}
			if s.entity_handle=="foe": hit.target=h(victim)
			hits.append(hit)
		return R.ok(hits)
	for t in range(1,8):
		var attack := []
		if t in [1,4]:
			attack.append({"actor_handle":h(attacker),"weapon_slot":1,"direction":"up","input_phase":"start" if t==1 else "release","target_hint":null})
		var result: Dictionary = combat.step_field(t,attack,poses,sweep)
		verify.call(result.ok,"COM field projectile")
		if result.ok:
			for receipt in result.value.receipts: verify.call(receipt.ok,"accepted bow input")
