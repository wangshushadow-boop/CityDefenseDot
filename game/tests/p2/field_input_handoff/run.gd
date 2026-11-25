extends "res://tests/p2/input/retry_cases.gd"

var reenter: Callable

func batch_port(batch: Dictionary) -> Dictionary:
	if reenter.is_valid():
		var denied: Dictionary = reenter.call(Vector3.FORWARD)
		check(not denied.ok and denied.error.code == "InvalidState","reject reentrant alignment")
	return super.batch_port(batch)

func movement(frame: Dictionary) -> Vector3:
	for intent in frame.value.batch.inputs:
		if intent.has("desired_direction"):
			var d: Array = intent.desired_direction
			return Vector3(d[0],d[1],d[2])*0.000001
	return Vector3.ZERO

func facing_cases() -> void:
	var player := router()
	player.handle_event(key(KEY_W))
	var tick := 0
	for heading: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK,Vector3(3,8,-4)]:
		tick += 1
		var expected := Vector3(heading.x,0,heading.z).normalized()
		var aligned := player.align_look(heading)
		check(aligned.ok and Vector3.FORWARD.rotated(Vector3.UP,aligned.value.x).distance_to(expected) < 0.000002,"camera and input share horizontal yaw")
		var frame := player.step(tick)
		check(frame.value.batch_receipt.ok and movement(frame).distance_to(expected) < 0.000002,"first W follows actor facing " + str(heading))
		check(frame.value.batch.inputs.size() == 1,"handoff contributes no device look intent")
	for bad_heading: Vector3 in [Vector3.ZERO,Vector3.UP,Vector3(NAN,0,1)]:
		var invalid := player.align_look(bad_heading)
		check(not invalid.ok and invalid.error.field == "heading","reject invalid heading")
	check(movement(player.step(tick+1)).distance_to(Vector3(0.6,0,-0.8)) < 0.000002,"invalid alignment preserves prior facing")
	player.set_control({},5)
	check(not player.align_look(Vector3.LEFT).ok,"observer has no controlled heading")
	player.free()

func devices_and_retries() -> void:
	var player := router()
	player.handle_event(key(KEY_W))
	player.handle_event(mouse_look(4,-2))
	var anchor := player.align_look(Vector3.RIGHT)
	check(anchor.ok and absf(anchor.value.x + PI/2) < 0.000001 and anchor.value.y == 0.0,"east facing seed in radians")
	var busy := R.fail("Unavailable","simulation")
	batch_replies = [busy,R.ok()]
	reenter = player.align_look
	var first := player.step(1)
	reenter = Callable()
	var aim: Dictionary = first.value.batch.inputs[0]
	var options: Dictionary = player.profile_view().options
	var mouse_yaw := roundi(anchor.value.x*1000000) - 4*int(options.mouse_sensitivity)
	var mouse_pitch := 2*int(options.mouse_sensitivity)
	check(aim.yaw == mouse_yaw and aim.pitch == mouse_pitch,"queued mouse delta applies once on seeded heading")
	check(movement(first).distance_to(Vector3.FORWARD.rotated(Vector3.UP,mouse_yaw*0.000001)) < 0.000002,"W follows sampled mouse yaw")
	var first_wire := S.encode_value("IntentBatch",first.value.batch)
	check(first_wire.ok and first.value.batch_receipt == busy,"pending canonical v1 batch")
	var second_anchor := player.align_look(Vector3.BACK)
	check(second_anchor.ok and absf(second_anchor.value.y - mouse_pitch*0.000001) < 0.000001,"handoff preserves sampled pitch")
	player.handle_event(axis(JOY_AXIS_RIGHT_X,1))
	var retry := player.step(1)
	check(retry.value.batch_receipt.ok and received_batches.size()==2 and first_wire.value == S.encode_value("IntentBatch",received_batches[1]).value,"pending batch retries byte for byte after handoff")
	var next := player.step(2)
	var stick_aim: Dictionary = next.value.batch.inputs[0]
	var expected_yaw := wrapf(second_anchor.value.x - float(options.stick_sensitivity)*0.000001,-PI,PI)
	check(absf(stick_aim.yaw*0.000001 - expected_yaw) < 0.000002 and stick_aim.pitch == mouse_pitch,"controller turn starts at new heading across wrap")
	check(movement(next).distance_to(Vector3.FORWARD.rotated(Vector3.UP,expected_yaw)) < 0.000002,"held W and controller rotation share facing")
	player.handle_event(axis(JOY_AXIS_RIGHT_X,0))
	player.set_control({"index":H.index,"generation":2},5)
	var third_anchor := player.align_look(Vector3.LEFT)
	player.handle_event(key(KEY_W,false))
	player.handle_event(key(KEY_W))
	var rebound := player.step(3)
	check(third_anchor.ok and rebound.value.batch.control_revision == 5 and rebound.value.batch.inputs[0].actor_handle.generation == 2 and movement(rebound).distance_to(Vector3.LEFT) < 0.000002,"new generation receives the rebound W")
	player.free()

func run() -> void:
	facing_cases()
	devices_and_retries()
	print("P2-FIELD-INTEGRATION-016 ", "PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
