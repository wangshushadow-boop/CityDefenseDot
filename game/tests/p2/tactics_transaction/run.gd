extends SceneTree
const Tactics = preload("res://mission/ai/tactical/ports/field_tactics.gd")
const AI = preload("res://mission/ai/ports/field_ai.gd")
const R = preload("res://contracts/result.gd")
var errors := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var ai := AI.new("field",func(_a,_b):return true)
	var row := {"handle":{"index":1,"generation":1},"team_key":0,"formation_id":0,"position":Vector3.ZERO,
		"role":"infantry","hp":100,"morale":70,"ammo":0,"control_revision":0,"order_revision":0}
	check(ai.publish(1,1,[row]).ok,"publish roster")
	var job: Dictionary = ai.schedule().value.jobs.filter(func(j):return j.layer=="tactical")[0]
	var intel: Dictionary = ai.team_view(0).value
	var planner := Tactics.new("field",0,func(_s,_f,_r,_o):return true,func(_s,_n,_f,_p,_t,_e,_role):return R.ok({"reachable":true,"line":true}),
		func(team):return ai.team_view(team).value,ai.collect.bind([]))
	check(planner.begin_tick().ok and not planner.begin_tick().ok,"single transaction")
	check(planner.stage(job,intel,[]).ok and planner.commit().ok and not planner.view().is_empty(),"real candidate admitted")
	planner.rollback_tick()
	planner.rollback_tick()
	check(planner.view().is_empty(),"later failure unpublishes plan")
	check(planner.begin_tick().ok and planner.stage(job,intel,[]).ok and not planner.commit().ok,"expired grant remains rejected")
	planner.rollback_tick()
	check(ai.publish(61,1,[row]).ok,"new tick")
	job = ai.schedule().value.jobs.filter(func(j):return j.layer=="tactical")[0]
	check(planner.begin_tick().ok and planner.stage(job,ai.team_view(0).value,[]).ok and planner.commit().ok,"real next grant")
	planner.commit_tick()
	planner.rollback_tick()
	check(planner.view().tick==61,"committed plan survives late rollback")
	check(planner.begin_tick().ok,"begin closing")
	planner.close()
	planner.rollback_tick()
	check(planner.view().is_empty() and not planner.begin_tick().ok,"closed scope cannot return")
	print("Tactics tick transaction ", "PASS" if errors==0 else "FAIL")
	quit(1 if errors else 0)
