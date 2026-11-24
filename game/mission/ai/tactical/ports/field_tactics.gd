extends RefCounted
## One team's short-lived Mission plan. Only the composition root dispatches
## granted BAI jobs here. FORM and MOV remain the owners of orders and positions.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const STICK_TICKS := 180
const TASK_TICKS := 480
const SITE_LIMIT := 32
const ROLES := ["infantry","archer","cavalry","mounted_archer"]
var _scope: String
var _team: Variant
var _authority: Callable
var _probe: Callable
var _current_view: Callable
var _admit_job: Callable
var _instance := -1
var _plan := {}
var _candidate := {}
var _stamp := {}
var _pending_job := {}
var _busy := false
var _closed := false

func _init(scope: String, team: Variant, may_command: Callable, evaluate_site: Callable, current_view: Callable, admit_job: Callable) -> void:
	_scope = scope
	_team = team
	_authority = may_command
	_probe = evaluate_site
	_current_view = current_view
	_admit_job = admit_job

func view() -> Dictionary:
	return _plan.duplicate(true)

func close() -> void:
	_closed = true
	_plan = {}
	_candidate = {}
	_stamp = {}
	_pending_job = {}

static func _handle(value: Variant) -> bool:
	return value is Dictionary and value.size()==2 and V.integer(value.get("index"),0,V.MAX_U32) and V.integer(value.get("generation"),1,V.MAX_U32)

static func _team_ok(id: Variant) -> bool:
	return V.integer(id,0,V.MAX_U32) or (id is String and not id.is_empty())

func _groups(rows: Array, revisions: Dictionary, seen: Dictionary) -> Dictionary:
	var groups := {}
	for own: Variant in rows:
		if not own is Dictionary or not is_same(own.get("team_key"),_team) or not V.integer(own.get("formation_id"),0,V.MAX_U32) or not _handle(own.get("handle")):
			return R.fail("InvalidArgument","tactical_member")
		if seen.has(own.handle.index) or not own.get("position") is Vector3 or not own.position.is_finite():
			return R.fail("InvalidArgument","tactical_member")
		if own.get("role") not in ROLES and own.get("role")!="mount":
			return R.fail("InvalidArgument","tactical_role")
		if not V.integer(own.get("control_revision")) or not V.integer(own.get("order_revision")) or revisions.get(own.formation_id)!=[own.control_revision,own.order_revision]:
			return R.fail("StaleVersion","formation_revision")
		if not V.integer(own.get("hp",100),0,1000000) or not V.integer(own.get("morale",70),0,100) or not V.integer(own.get("ammo",0),0,1000000):
			return R.fail("InvalidArgument","tactical_condition")
		seen[own.handle.index] = true
		if own.get("hp",100)==0 or own.role=="mount":
			continue
		var id: int = own.formation_id
		if not groups.has(id):
			groups[id] = {"id":id,"revision":own.control_revision,"order_revision":own.order_revision,"troops":0,"roles":{},"position":Vector3.ZERO,"morale":0,"ammo":0}
		var g: Dictionary = groups[id]
		g.troops += 1
		g.position += own.position
		g.roles[own.role] = int(g.roles.get(own.role,0))+1
		if own.role in ["archer","mounted_archer"]:
			g.ammo += own.get("ammo",0)
		g.morale += own.get("morale",70)
	for g: Dictionary in groups.values():
		g.position /= float(g.troops)
		g.morale /= float(g.troops)
		g.role = "infantry"
		for role in ROLES:
			if g.roles.get(role,0)>g.roles.get(g.role,0):
				g.role = role
	return R.ok(groups)

func _contacts(rows: Array, revisions: Dictionary, seen: Dictionary) -> Dictionary:
	var contacts := []
	for sight: Variant in rows:
		if not sight is Dictionary or not _handle(sight.get("handle")) or seen.has(sight.handle.index) or not _team_ok(sight.get("team_key")) or is_same(sight.team_key,_team):
			return R.fail("InvalidArgument","tactical_contact")
		if not V.integer(sight.get("formation_id"),0,V.MAX_U32) or revisions.has(sight.formation_id) or not sight.get("position") is Vector3 or not sight.position.is_finite():
			return R.fail("InvalidArgument","tactical_contact")
		if sight.get("role") not in ROLES and sight.get("role")!="mount":
			return R.fail("InvalidArgument","tactical_contact_role")
		seen[sight.handle.index] = true
		if sight.role!="mount":
			contacts.append(sight)
	return R.ok(contacts)

static func _sites_valid(sites: Array) -> bool:
	if sites.size()>SITE_LIMIT:
		return false
	var ids := {}
	for site: Variant in sites:
		if not site is Dictionary or not site.get("id") is String or site.id.is_empty() or ids.has(site.id):
			return false
		if not site.get("position") is Vector3 or not site.position.is_finite() or not site.get("objective",false) is bool:
			return false
		ids[site.id] = true
	return true

static func _nearest(position: Vector3,contacts: Array) -> Variant:
	var best: Variant = null
	var distance := INF
	for contact: Dictionary in contacts:
		var squared := position.distance_squared_to(contact.position)
		if best==null or squared<distance or (squared==distance and (contact.formation_id<best.formation_id or (contact.formation_id==best.formation_id and contact.handle.index<best.handle.index))):
			distance = squared
			best = contact
	return best

func _choose(g: Dictionary, sites: Array, contact: Variant, stamp: Dictionary, retreat: bool, previous: Dictionary, unavailable: Dictionary, force: bool) -> Dictionary:
	var best := {}
	var ordered := sites
	if not force and stamp.tick<previous.get("locked_until",-1):
		for i in sites.size():
			if sites[i].id==previous.get("site_id"):
				ordered = sites.duplicate()
				ordered.push_front(ordered.pop_at(i))
				break
	for site: Dictionary in ordered:
		if unavailable.has(site.id):
			continue
		var facts: Variant = _probe.call(_scope,stamp.nav_revision,g.id,g.position,site.position,contact.position if contact!=null else null,g.role)
		if _closed:
			return R.fail("InvalidState","tactical_scope")
		if not facts is Dictionary or not is_same(facts.get("ok"),true):
			return R.fail("Unavailable","tactical_terrain")
		var field: Variant = facts.get("value")
		if not field is Dictionary or not field.get("reachable") is bool or not field.get("line") is bool:
			return R.fail("InvalidArgument","tactical_terrain")
		if not field.reachable:
			continue
		var travel: float = g.position.distance_to(site.position)
		var opposite: float = site.position.distance_to(contact.position) if contact!=null else 0.0
		var elevation: float = clampf(site.position.y-g.position.y,-8,12)
		var target: Variant = contact.formation_id if contact!=null else null
		var score := -travel*.13
		var goal := "hold"
		if retreat:
			score += opposite*.65
			goal = "retreat"
			target = null
		elif contact!=null:
			score += 3 if site.get("objective",false) else 0
			match g.role:
				"archer","mounted_archer":
					if g.ammo>0 and field.line:
						score += elevation*2.1+12.0-absf(opposite-18.0)*.45
						goal = "harass" if g.role=="mounted_archer" else "cover"
					else:
						score -= 6.0
						target = null
				"cavalry":
					var axis: Vector3 = (contact.position-g.position).normalized()
					var side := absf((site.position-g.position).dot(axis.cross(Vector3.UP)))
					score += minf(side,15)*1.3-absf(opposite-10)*.32
					goal = "flank"
				_:
					score += elevation*.4-opposite*.45
					goal = "advance"
		else:
			score += 3 if site.get("objective",false) else 0
		var choice := {"site_id":site.id,"score":score,"role":g.role,"goal":goal,"position":site.position,"target_formation":target,"line":field.line}
		if not force and stamp.tick<previous.get("locked_until",-1) and previous.get("site_id")==site.id and previous.get("position")==site.position and previous.get("goal")==goal and previous.get("target_formation")==target and previous.get("role")==g.role:
			return R.ok(choice)
		if best.is_empty() or score>best.score or (score==best.score and site.id<best.site_id):
			best = choice
	if best.is_empty():
		best = {"site_id":"","score":0.0,"role":g.role,"goal":"hold","position":g.position,"target_formation":null,"line":false}
	return R.ok(best)

func _snapshot() -> Dictionary:
	if not _current_view.is_valid():
		return {}
	var current: Variant = _current_view.call(_team)
	return current if not _closed and current is Dictionary else {}

func stage(job: Dictionary, intel: Dictionary, sites: Array, feedback: Array = [], finished := false) -> Dictionary:
	if _closed or _busy or not _candidate.is_empty() or _plan.get("phase")=="Finish" or not _authority.is_valid() or not _probe.is_valid() or not _admit_job.is_valid():
		return R.fail("InvalidState","tactical_plan")
	var stamp: Variant = job.get("stamp")
	if _scope.is_empty() or not _team_ok(_team) or job.get("layer")!="tactical" or not V.integer(job.get("id"),1) or not is_same(job.get("subject"),_team) or not stamp is Dictionary or stamp.get("scope_id")!=_scope or intel.get("stamp")!=stamp:
		return R.fail("Unauthorized","tactical_job")
	if typeof(stamp.get("instance"))!=TYPE_INT or stamp.instance==0 or (_instance!=-1 and _instance!=stamp.instance) or not V.integer(stamp.get("tick")) or not V.integer(stamp.get("nav_revision")) or stamp.tick<=_plan.get("tick",-1) or stamp.nav_revision<_plan.get("nav_revision",-1):
		return R.fail("StaleVersion","tactical_tick")
	if not stamp.get("formation_revisions") is Dictionary or not _sites_valid(sites) or not intel.get("own_units") is Array or not intel.get("visible_enemies") is Array:
		return R.fail("InvalidArgument","tactical_view")
	_busy = true
	var result := R.fail("StaleVersion","tactical_snapshot")
	var trusted := _snapshot()
	if trusted==intel:
		_instance = stamp.instance
		var seen := {}
		var grouped := _groups(trusted.own_units,stamp.formation_revisions,seen)
		var contacts := _contacts(trusted.visible_enemies,stamp.formation_revisions,seen)
		if not grouped.ok:
			result = grouped
		elif not contacts.ok:
			result = contacts
		else:
			result = _plan_step(trusted.stamp,grouped.value,contacts.value,sites.duplicate(true),feedback,finished)
			if result.ok:
				_pending_job = job.duplicate(true)
	_busy = false
	return result

func _plan_step(stamp: Dictionary, groups: Dictionary, contacts: Array, sites: Array, feedback: Array, finished: bool) -> Dictionary:
	var prior := {}
	for task: Dictionary in _plan.get("formation_tasks",[]):
		prior[task.formation_id] = task
	var statuses := {}
	for row: Variant in feedback:
		if not row is Dictionary or not V.integer(row.get("formation_id"),0,V.MAX_U32) or not row.get("task_id") is String or row.task_id.is_empty():
			return R.fail("InvalidArgument","task_feedback")
		if row.get("status") not in ["running","blocked","failed","completed"] or not row.get("reason","") is String or typeof(row.get("progress",0)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(row.get("progress",0))) or row.get("progress",0)<0 or row.get("progress",0)>1:
			return R.fail("InvalidArgument","task_feedback")
		var last: Dictionary = prior.get(row.formation_id,{})
		if last.get("id")==row.task_id:
			if statuses.has(row.formation_id):
				return R.fail("Conflict","task_feedback")
			statuses[row.formation_id] = {"task_id":row.task_id,"status":row.status,"progress":row.get("progress",0),"reason":row.get("reason","")}
	var tasks := []
	var total := 0
	var morale := 0.0
	for g: Dictionary in groups.values():
		total += g.troops
		morale += g.morale*g.troops
	var retreat := not contacts.is_empty() and (morale/maxi(total,1)<25.0 or contacts.size()>maxi(1,total)*1.6)
	var adapt := false
	var ids := groups.keys()
	ids.sort()
	for id in ids:
		if finished:
			break
		var g: Dictionary = groups[id]
		var granted: Variant = _authority.call(_scope,id,g.revision,g.order_revision)
		if _closed:
			return R.fail("InvalidState","tactical_scope")
		if not granted is bool:
			return R.fail("InvalidArgument","tactical_authority")
		if not granted:
			continue
		if statuses.get(id,{}).get("reason") in ["player_order","not_delegated"]:
			continue
		var last: Dictionary = prior.get(id,{})
		var failed: bool = statuses.get(id,{}).get("status") in ["failed","blocked"]
		var unavailable := {}
		if stamp.nav_revision==_plan.get("nav_revision"):
			var remembered: Dictionary = last.get("unavailable_sites",{})
			for site in sites:
				if remembered.get(site.id,-1)>stamp.tick:
					unavailable[site.id] = remembered[site.id]
		if failed and not last.get("site_id","").is_empty():
			unavailable[last.site_id] = stamp.tick+STICK_TICKS
		var expired: bool = last.get("timeout",-1)<=stamp.tick
		var nearest: Variant = _nearest(g.position,contacts)
		var observed: Variant = nearest.formation_id if nearest!=null else null
		var strength_changed := absi(total-int(_plan.get("strength",total)))>=maxi(1,ceili(total*.25))
		var authority_changed: bool = g.revision!=last.get("control_revision") or g.order_revision!=last.get("order_revision")
		var situation_changed: bool = observed!=last.get("observed_contact") or (g.ammo>0)!=last.get("has_ammo")
		var force := failed or expired or strength_changed or authority_changed or situation_changed
		var chosen := _choose(g,sites,nearest,stamp,retreat,last,unavailable,force)
		if not chosen.ok:
			return chosen
		var t: Dictionary = chosen.value
		var fresh: bool = force or t.role!=last.get("role") or t.goal!=last.get("goal") or t.site_id!=last.get("site_id") or t.position!=last.get("position") or t.target_formation!=last.get("target_formation")
		adapt = adapt or (not last.is_empty() and fresh)
		t.merge({"id":"%s/%s/%s/%s"%[_instance,id,g.revision,stamp.tick] if fresh else last.id,
			"formation_id":id,"priority":2 if retreat else 1,"control_revision":g.revision,"order_revision":g.order_revision,
			"observed_contact":observed,"has_ammo":g.ammo>0,
			"unavailable_sites":unavailable,
			"constraints":{"fire_allowed":g.ammo>0 and t.line and not retreat,"engage_allowed":not retreat},
			"completion":"arrived" if t.goal in ["retreat","flank","advance"] else "executed",
			"timeout":stamp.tick+TASK_TICKS if fresh else last.timeout,"locked_until":stamp.tick+STICK_TICKS if fresh else last.locked_until})
		tasks.append(t)
	var phase := "Deploy" if contacts.is_empty() else "Engage"
	if adapt and not contacts.is_empty() and _plan.get("phase")!="Deploy": phase = "Adapt"
	if retreat: phase = "Retreat"
	if finished: phase = "Finish"
	var transitioned: bool = _plan.is_empty() or _plan.phase!=phase
	_candidate = {"scope_id":_scope,"instance":_instance,"team":_team,"tick":stamp.tick,"nav_revision":stamp.nav_revision,
		"id":"%s/%s/%s/%s"%[_instance,typeof(_team),_team,stamp.tick] if transitioned else _plan.id,
		"created_tick":stamp.tick if transitioned else _plan.created_tick,"phase":phase,"strength":total,
		"formation_tasks":tasks,"feedback":statuses,"locked_until":stamp.tick+STICK_TICKS if transitioned else _plan.locked_until}
	_stamp = stamp.duplicate(true)
	return R.ok(_candidate.duplicate(true))

func _candidate_current() -> bool:
	if _closed or not _authority.is_valid() or _snapshot().get("stamp") != _stamp:
		return false
	for task: Dictionary in _candidate.formation_tasks:
		if not is_same(_authority.call(_scope,task.formation_id,task.control_revision,task.order_revision),true) or _closed:
			return false
	return not _closed

func commit() -> Dictionary:
	if _busy or _closed or _candidate.is_empty():
		return R.fail("InvalidState","tactical_commit")
	_busy = true
	var fresh := _candidate_current()
	if fresh:
		# Admission consumes the BAI job and can publish new FORM permissions.
		var receipt: Variant = _admit_job.call(_pending_job) if _admit_job.is_valid() else null
		fresh = receipt is Dictionary and is_same(receipt.get("ok"),true) and _candidate_current()
	_busy = false
	if fresh:
		_plan = _candidate
	_candidate = {}
	_stamp = {}
	_pending_job = {}
	return R.ok() if fresh else R.fail("StaleVersion","tactical_authority")

func rollback() -> Dictionary:
	if _busy or _closed:
		return R.fail("InvalidState","tactical_rollback")
	_candidate = {}
	_stamp = {}
	_pending_job = {}
	return R.ok()
