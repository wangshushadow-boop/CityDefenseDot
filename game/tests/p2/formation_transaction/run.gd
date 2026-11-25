extends SceneTree
const FORM = preload("res://mission/formation/ports/field_formation.gd")
const R = preload("res://contracts/result.gd")
var errors := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var owner := RefCounted.new()
	var f := FORM.new("field",func(actor):return R.ok("player") if is_same(actor,owner) else R.fail("Unauthorized"),
		func(_id,_point):return true)
	var h := {"index":1,"generation":1}
	var other := {"index":2,"generation":1}
	check(f.add_formation(1,0,"player",[h,other]).ok,"create")
	var projector := func(points):return R.ok(points)
	var slots: Array = f.build_slot_targets(1,Vector3.ZERO,0,1,100,projector).value.slots
	var hold := {"mission_id":"field","issuer_id":"player","order_id":"hold","issued_tick":1,"client_sequence":1,
		"formation_ids":[1],"order_type":"hold","target_position":null,"target_formation_id":null,"parameters":{}}
	check(f.issue_order(hold,owner,0).ok,"real pending order")
	var before := f.view(1)
	check(f.begin_tick().ok and not f.begin_tick().ok,"single transaction")
	check(f.advance(1).ok and f.order_status("player","hold").value[1].state=="Active","order admitted")
	check(f.set_delegate(1,"captain",owner,0).ok and f.split(1,2,[h],owner,1).ok,"roster and control changed")
	check(f.build_slot_targets(1,Vector3.RIGHT*9,0,1,100,projector).ok,"new slots")
	var second: Dictionary = hold.duplicate(true)
	second.merge({"order_id":"new","issued_tick":2,"client_sequence":2},true)
	check(f.issue_order(second,owner,1).ok,"new history receipt")
	f.rollback_tick()
	f.rollback_tick()
	check(f.view(1)==before and not f.view(2).ok and f.member_formation(h).value==1,"restore roster and authority")
	check(f.order_status("player","hold").value[1].state=="Pending" and not f.order_status("player","new").ok,"restore old order and forget new one")
	check(f.begin_tick().ok and f.advance(1).ok and f.view(1).value.active==hold,"retry same tick")
	check(f.complete_active(1,"player","hold","executed").ok,"finish active after replay")
	check(f.order_status("player","hold").value[1].state=="Completed","active and history share original job")
	check(f.build_slot_targets(1,Vector3.ZERO,0,1,100,projector).value.slots==slots,"original slot layout")
	f.commit_tick()
	f.rollback_tick()
	check(f.advance(2).ok and not f.advance(1).ok,"commit progress")
	print("Formation tick transaction ", "PASS" if errors==0 else "FAIL")
	quit(1 if errors else 0)
