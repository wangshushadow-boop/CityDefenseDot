extends SceneTree
const F=preload("res://mission/movement/ports/field_movement.gd")
const R=preload("res://contracts/result.gd")
class NavProbe:
	extends RefCounted
	var paused:=false
	func sync_navigation(_s): return R.ok({"status":"pending" if paused else "applied","applied_revision":1})
	func query_path_batch(batch,_r,_s):
		var rows:=[]
		for item in batch:
			rows.append({"nav_revision":1,"reachable":true,"points":[item.from,item.to]})
		return R.ok(rows)
func _initialize():
	var a:=NavProbe.new()
	var b:=NavProbe.new()
	var original:=F.new(a,"field")
	var retry:=F.new(b,"field")
	var h:={"index":0,"generation":1}
	for f in [original,retry]:
		f.spawn(h,Vector3.ZERO,"mounted",Vector3.RIGHT)
		f.set_corridor("A",Vector3.ZERO,Vector3(500,0,0),"mounted")
		f.assign(h,"A")
		for tick in range(20):
			f.step(tick,1.0/30.0)
	var before:Dictionary=original.view(h).value
	b.paused=true
	var rejected:Dictionary=retry.step(20,1.0/30.0)
	var after:Dictionary=retry.view(h).value
	b.paused=false
	var retried:Dictionary=retry.step(20,1.0/30.0)
	var control:Dictionary=original.step(20,1.0/30.0)
	var c:Dictionary=original.view(h).value
	var s:Dictionary=retry.view(h).value
	print("MOV_RETRY result=",rejected," speeds previous/rejected/retried/control=",before.velocity.length(),"/",after.velocity.length(),"/",s.velocity.length(),"/",c.velocity.length()," positions retry/control=",s.position,"/",c.position)
	quit(0 if not rejected.ok and retried.ok and control.ok and before==after and c==s else 1)