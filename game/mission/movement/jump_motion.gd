extends RefCounted
## Sweeps in the same Mission physics world as COM. Positions are the actor's feet, in metres.
const R = preload("res://contracts/result.gd")
const SPEED := 4.6
const GRAVITY := 11.0
const HEIGHT := 1.8
const SKIN := 0.003

static func _mm(p: Vector3) -> Array:
	return [roundi(p.x*1000),roundi(p.y*1000),roundi(p.z*1000)]

static func _query(a: Vector3,b: Vector3,radius: float,mask: int) -> Dictionary:
	return {"from":_mm(a),"to":_mm(b),"radius_mm":roundi(radius*1000),"mask":mask}

## Probe the proposed horizontal destination before leaving its supported neighbour.
## The bottom is the lowest coordinate representable by the engine query port.
static func _landing_support(p: Vector3,mask: int,sweep: Callable) -> Dictionary:
	var start := _mm(p+Vector3.UP*SKIN)
	var query := {"from":start,"to":[start[0],-2147483648,start[2]],"mask":mask}
	var hits: Dictionary = sweep.call([query])
	if not hits.ok: return hits
	for hit in hits.value:
		if hit.normal_ppm[1]>=500000: return R.ok(true)
	return R.ok(false)

static func can_launch(p: Vector3,r: float,mask: int,sweep: Callable) -> Dictionary:
	var head := p+Vector3.UP*(HEIGHT-r)
	var queries := [_query(p+Vector3.UP*.07,p+Vector3.DOWN*.12,0.0,mask),
		_query(p+Vector3.UP*(r+SKIN),head+Vector3.UP*.14,r,mask)]
	var result: Dictionary = sweep.call(queries)
	if not result.ok: return result
	var supported := false
	for hit in result.value:
		if hit.query_index==1:
			return R.fail("Unavailable","jump_headroom")
		if hit.normal_ppm[1]>=500000 and absi(hit.point_mm[1]-roundi(p.y*1000))<=75:
			supported = true
	return R.ok() if supported else R.fail("Unavailable","jump_ground")

static func advance(p: Vector3, velocity: Vector3, desired: Variant, dt: float, radius: float,
		mask: int, sweep: Callable, actor_clearance: Callable) -> Dictionary:
	var speed := Vector3(velocity.x,0,velocity.z)
	if desired!=null:
		speed = speed.move_toward(desired,6.0*dt)
	var delta := speed*dt
	var at := p
	var blocked := ""
	if _mm(p)!=_mm(p+delta):
		var queries := []
		for i in 4:
			var h := lerpf(radius+SKIN,HEIGHT-radius,float(i)/3.0)
			var origin := p+Vector3.UP*h
			queries.append(_query(origin,origin+delta,radius,mask))
		var walls: Dictionary = sweep.call(queries)
		if not walls.ok: return walls
		var fraction := 1.0
		for hit in walls.value:
			fraction = minf(fraction,hit.fraction_ppm*.000001)
		if fraction<1.0:
			delta=delta.limit_length(maxf(0,delta.length()*fraction-SKIN))
			blocked="scene"
		if is_same(actor_clearance.call(at+delta),true):
			var support := _landing_support(at+delta,mask,sweep)
			if not support.ok: return support
			if support.value:
				at += delta
			else:
				blocked="no_landing"
		else:
			blocked="yield"
	var next_v := velocity.y-GRAVITY*dt
	var rise := 0.5*(velocity.y+next_v)*dt
	var landed := false
	var origin := at+Vector3.UP*(HEIGHT-radius if rise>0 else radius)
	var end := origin+Vector3.UP*rise
	if _mm(origin)!=_mm(end):
		var sweep_result: Dictionary = sweep.call([_query(origin,end,radius,mask)])
		if not sweep_result.ok: return sweep_result
		for hit in sweep_result.value:
			if (rise>0 and hit.normal_ppm[1]>=0) or (rise<0 and hit.normal_ppm[1]<=0):
				continue
			landed = rise<0.0
			rise *= hit.fraction_ppm*.000001
			if landed and hit.normal_ppm[1]>=999999:
				# Recover the actual flat contact height rather than accumulating sweep quantization.
				rise = hit.point_mm[1]*0.001-at.y
			next_v=0.0
			break
	at.y += rise
	var actual := (at-p)/dt
	actual.y=next_v
	return R.ok({"position":at,"velocity":actual,"landed":landed,"blocked":blocked})
