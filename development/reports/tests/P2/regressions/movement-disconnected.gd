extends SceneTree
const Field=preload("res://mission/movement/ports/field_movement.gd")
const Adapter=preload("res://infrastructure/engine/adapter.gd")
const ID="review_closed_gap"
func _initialize(): run.call_deferred()
func run():
	var engine:=Adapter.new(root,true)
	var token:=engine.open_scope(ID)
	engine.load_scene({"id":"base:scene/review","simulation_scene":"res://tests/p2/movement/field.tscn"},token.value)
	for f in 120:
		await physics_frame
		var synced:=engine.sync_navigation(ID)
		if synced.ok and synced.value.status=="applied":
			var open:=engine.query_path_batch([{"from":[-8000,0,0],"to":[12000,0,0]}],synced.value.applied_revision,ID)
			if open.ok and open.value[0].reachable:
				break
	var closed:=engine.apply_nav_links([{"link_id":"bridge","enabled":false}],ID)
	print("native close=",closed)
	var ready:=false
	var start_reachable:=true
	var group_reachable:=false
	for f in 120:
		await physics_frame
		var s:=engine.sync_navigation(ID)
		if s.ok and s.value.status=="applied":
			var q:=engine.query_path_batch([{"from":[-8000,0,0],"to":[12000,0,0]},{"from":[4000,0,0],"to":[12000,0,0]}],s.value.applied_revision,ID)
			if q.ok:
				start_reachable=q.value[0].reachable
				group_reachable=q.value[1].reachable
				if group_reachable and not start_reachable:
					ready=true
					break
	var field:=Field.new(engine,ID)
	var h:={"index":0,"generation":1}
	field.spawn(h,Vector3(-8,0,0))
	field.set_corridor("formation",Vector3(4,0,0),Vector3(12,0,0))
	field.assign(h,"formation")
	var success:=true
	for tick in range(220):
		if not field.step(tick,1.0/30.0).ok:
			success=false
			break
	var actual:Dictionary=field.view(h).value
	engine.release_scope(ID)
	print("MOV_DISCONNECTED closed_nav_ready=",ready," member_reachable=",start_reachable," group_reachable=",group_reachable," step_ok=",success," actual_position=",actual.position," arrived=",actual.arrived)
	quit(0 if ready and success and actual.position.x<0.0 and not actual.arrived else 1)