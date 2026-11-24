extends SceneTree
const Camera = preload("res://presentation/camera/ports/field_camera.gd")
const R = preload("res://contracts/result.gd")
const SCOPE := "a"
const FIRST := {"index":1,"generation":1}
const NEXT := {"index":1,"generation":2}
var cam: Camera
var during := ""
var change := ""
var granted := true
var present := true
var allow_deployment := false
var fail_sweep := false
var checks := 0
var failures := 0
var visibility_calls := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func bind() -> Dictionary:
	return cam.open_field(SCOPE,pose,permit,sweep,visible,Vector3(25,0,0))

func callback(boundary: String) -> void:
	if during!=boundary: return
	during = ""
	match change:
		"release":
			cam.release_scope(SCOPE)
		"reopen":
			cam.release_scope(SCOPE)
			check(bind().ok,"reopen the same scope id")
			select_next()
		"retarget":
			select_next()
		"revoke":
			granted = false
		"destroy":
			present = false

func select_next() -> void:
	check(cam.set_mode(SCOPE,"spectator",NEXT).ok and cam.update_view(SCOPE,50,.1).ok,"nested operation presents new generation")

func permit(_scope: String,mode: String,handle: Dictionary) -> bool:
	var allowed := allow_deployment if mode=="deployment" else (handle==NEXT or (handle==FIRST and granted))
	callback("fallback" if mode=="deployment" else "permit")
	return allowed

func pose(_scope: String, handle: Dictionary) -> Dictionary:
	var result := R.ok({"position":Vector3(40 if handle==NEXT else 2,0,0)})
	if handle==FIRST and not present: result = R.fail("NotFound")
	callback("pose")
	return result

func sweep(requests: Array,_stamp: Dictionary) -> Dictionary:
	callback("sweep")
	if fail_sweep: return R.fail("Unavailable")
	if requests[0].radius_mm!=0: return R.ok([])
	return R.ok([{"fraction_ppm":50000,"entity_handle":"old-actor","point_mm":[2,3,4]}])

func visible(_scope: String,_id: String) -> Dictionary:
	visibility_calls += 1
	callback("visible")
	return R.ok(FIRST.duplicate())

func setup() -> void:
	cam.release_scope(SCOPE)
	granted = true
	present = true
	fail_sweep = false
	allow_deployment = false
	visibility_calls = 0
	check(bind().ok and cam.set_mode(SCOPE,"third",FIRST).ok and cam.update_view(SCOPE,1,.1).ok,"old view active")

func run_case(boundary: String, mutation: String, op: String) -> void:
	setup()
	during = boundary
	change = mutation
	var result: Dictionary
	match op:
		"switch": result = cam.set_mode(SCOPE,"first",FIRST)
		"update": result = cam.update_view(SCOPE,2,.1)
		"pick": result = cam.pick(SCOPE,root.get_visible_rect().get_center())
	var label := "%s / %s / %s" % [op,boundary,mutation]
	check(during.is_empty() and not result.ok and not result.has("value"),label+" abandons old output")
	var state := cam.state()
	if mutation in ["reopen","retarget"]:
		check(state.target==NEXT and state.active and cam.current and cam.cull_mask!=0 and cam.position.x==40,label+" preserves replacement view")
	else:
		check(not state.active and not cam.current and cam.cull_mask==0 and state.target.is_empty(),label+" clears retired view")
	if op=="pick" and boundary!="visible":
		check(visibility_calls==0,label+" does not ask for identity after invalidation")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	cam = Camera.new()
	root.add_child(cam)
	setup()
	check(not cam.set_mode(SCOPE,"mounted",FIRST).ok and cam.state().mode=="third","mounted requires affirmative pose")
	for op in ["switch","update","pick"]:
		var boundaries := ["permit","pose"]
		if op!="switch": boundaries.append("sweep")
		if op=="pick": boundaries.append("visible")
		for boundary in boundaries:
			for mutation in ["release","reopen","retarget","revoke"]:
				run_case(boundary,mutation,op)
	for op in ["update","pick"]:
		run_case("sweep","destroy",op)
	run_case("visible","destroy","pick")
	for op in ["update","pick"]:
		setup()
		during = "sweep"
		change = "revoke"
		fail_sweep = true
		var result := cam.update_view(SCOPE,2,.1) if op=="update" else cam.pick(SCOPE,root.get_visible_rect().get_center())
		check(not result.ok and not cam.state().active and cam.state().target.is_empty(),"failing sweep cannot retain revoked "+op)
	setup()
	granted = false
	allow_deployment = true
	during = "fallback"
	change = "reopen"
	check(not cam.update_view(SCOPE,2,.1).ok and cam.state().target==NEXT and cam.state().active and cam.position.x==40,"stale fallback does not clear or override rebound view")
	cam.release_scope(SCOPE)
	cam.free()
	print("CAMERA_REENTRANCY ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(int(failures>0))
