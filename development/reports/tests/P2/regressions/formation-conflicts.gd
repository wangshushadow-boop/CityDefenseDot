extends SceneTree
const F=preload("res://mission/formation/ports/field_formation.gd")
const R=preload("res://contracts/result.gd")
func order(actor:String, n:int, tick:int, kind:String, p:Dictionary={}, ids:Array=[1])->Dictionary:
	return {"mission_id":"m","order_id":actor+str(n),"issuer_id":actor,"client_sequence":n,"issued_tick":tick,"order_type":kind,"parameters":p,"formation_ids":ids,"target_position":null,"target_formation_id":null}
func _initialize():
	var f:=F.new("m",func(ctx):return R.ok(ctx),func(_a,_b):return true)
	f.add_formation(1,"A","player",[{"index":1,"generation":1},{"index":2,"generation":1}])
	f.add_formation(2,"B","player",[{"index":3,"generation":1}])
	f.set_delegate(1,"captain","player",0)
	var bad:=order("player",1,1,"merge",{"source_id":2})
	var good:=order("captain",1,1,"hold")
	var a:=f.issue_order(bad,"player",1)
	var b:=f.issue_order(good,"captain",1)
	var tick:=f.advance(1)
	var p:Dictionary=f.order_status("player","player1").value[1]
	var d:Dictionary=f.order_status("captain","captain1").value[1]
	print("cross-team owner merge=",p," otherwise-valid delegate hold=",d," active=",f.view(1).value.active)
	quit(0 if a.ok and b.ok and tick.ok and p.state=="Failed" and d.state=="Active" and f.view(1).value.active==good else 1)