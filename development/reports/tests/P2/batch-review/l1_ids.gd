extends SceneTree
const AI = preload("res://mission/ai/ports/field_ai.gd")
const T = preload("res://mission/ai/tactical/ports/field_tactics.gd")

func _initialize() -> void:
	var board = AI.new("field",func(_a,_b):return true)
	var u := {"handle":{"index":0,"generation":1},"team_key":0,"formation_id":0,"position":Vector3.ZERO,"role":"infantry","order_revision":0,"control_revision":0}
	var v := u.duplicate(true)
	v.handle.index = 1
	v.team_key = "0"
	v.formation_id = 1
	var published: Dictionary = board.publish(1,0,[u,v])
	board.schedule({"tactical":0})
	board.publish(61,0,[u,v])
	var jobs: Array = board.schedule().value.jobs
	var ids := []
	for job in jobs:
		if job.layer != "tactical": continue
		var t = T.new("field",job.subject,func(_s,_f,_c,_o): return true,func(_s,_v,_f,_a,_b,_e,_r):return {"ok":true,"value":{"reachable":true,"line":true}},func(team):return board.team_view(team).value,board.collect.bind([]))
		var stage: Dictionary = t.stage(job,board.team_view(job.subject).value,[])
		var committed: Dictionary = t.commit()
		if not stage.ok or not committed.ok:
			printerr("unexpected ",stage,committed)
			quit(2)
			return
		var plan: Dictionary = t.view()
		ids.append(plan.id)
		print("team type=",type_string(typeof(plan.team))," plan_id=",plan.id)
	print("count=",ids.size()," equal=",ids.size()==2 and ids[0]==ids[1], " published=",published.ok)
	quit(1 if ids.size()==2 and ids[0]==ids[1] else 0)
