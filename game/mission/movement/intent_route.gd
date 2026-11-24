extends RefCounted
## A short immutable strip through a specific revision of the navigation map.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const RANGE := 18.0
var revision: int
var direction: Vector3
var points := PackedVector3Array()
var continues := false

func from_path(origin: Vector3, solved: Dictionary) -> Dictionary:
	var previous := origin
	for index in solved.points.size():
		var raw: Variant = solved.points[index]
		if not raw is Array or raw.size()!=3 or not raw.all(func(v): return V.integer(v,-2147483648,2147483647)):
			return R.fail("InvalidState","movement_path")
		var waypoint := Vector3(raw[0],raw[1],raw[2])*.001
		if index==0:
			# A projected start on another floor or island is not a legal join.
			if origin.distance_to(waypoint)>.015: return R.ok()
			continue
		var delta := waypoint-previous
		if delta.length_squared()<.000001: continue
		# A link endpoint can sit just behind the actor at a bank or doorway.
		if delta.dot(direction)<-.4 or (waypoint-origin).dot(direction)<-.4: break
		points.append(waypoint)
		previous = waypoint
	continues = solved.reachable and previous.distance_to(origin+direction*RANGE)<.015
	return R.ok()
