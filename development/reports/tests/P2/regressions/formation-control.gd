extends SceneTree
const Field=preload("res://mission/formation/ports/field_formation.gd")
const R=preload("res://contracts/result.gd")
var player:=RefCounted.new()
var ai:=RefCounted.new()
var checks:=0
var errors:=0
var reached_all:=false
func auth(t:Variant)->Dictionary:
	if is_same(t,player):return R.ok("player")
	if is_same(t,ai):return R.ok("ai")
	return R.fail("Unauthorized")
func ok(b:bool,msg:String)->void:
	checks+=1
	if not b:
		errors+=1
		printerr("QA_FAIL ",msg)
func h(i:int,g:int=1)->Dictionary:
	return {"index":i,"generation":g}
func fresh():
	var f=Field.new("qa",auth,func(_id,p):return p[0]<100)
	ok(f.add_formation(1,0,"player",[h(10),h(11),h(12)]).ok,"first")
	ok(f.add_formation(2,"0","player",[h(13)]).ok,"second")
	return f
func order(a:String,seq:int,t:int,k:String,p:Dictionary={},target:Variant=null)->Dictionary:
	return {"mission_id":"qa","issuer_id":a,"order_id":a+str(seq),"client_sequence":seq,"issued_tick":t,"formation_ids":[1],"order_type":k,"parameters":p,"target_formation_id":target if typeof(target)==TYPE_INT else null,"target_position":target if typeof(target)==TYPE_ARRAY else null}
func _initialize()->void:
	go.call_deferred()
func go()->void:
	var f=fresh()
	var manual:=order("player",1,1,"hold")
	ok(f.issue_order(manual,player,0).ok and f.advance(1).ok,"manual admitted")
	ok(f.set_delegate(1,"ai",player,0).ok,"grant")
	var override:=order("ai",1,2,"retreat")
	ok(f.issue_order(override,ai,1).ok and f.advance(2).ok,"delegated after owner")
	print("AFTER_GRANT owner=",f.order_status("player","player1").value[1]," delegated=",f.order_status("ai","ai1").value[1])
	ok(f.view(1).value.active==manual,"new delegate replaces standing player order")
	ok(f.set_delegate(1,"",player,1).ok and not f.issue_order(override,ai,1).ok and f.set_delegate(1,"ai",player,2).ok and not f.issue_order(override,ai,3).ok,"re-grant cannot replay old receipt")
	var g=fresh()
	g.set_delegate(1,"ai",player,0)
	var rejected:=order("player",1,1,"split",{"members":[h(10,99)],"new_formation_id":3})
	var valid:=order("ai",1,1,"retreat")
	ok(g.issue_order(rejected,player,1).ok and g.issue_order(valid,ai,1).ok and g.advance(1).ok,"split and retreat admitted")
	print("FAILED_SOURCE owner=",g.order_status("player","player1").value[1]," delegated=",g.order_status("ai","ai1").value[1])
	ok(g.order_status("player","player1").value[1].state=="Failed" and g.view(1).value.active==valid,"failed split suppresses valid same-tick delegated order")
	var c=fresh()
	var cmd:=order("player",1,1,"charge",{},2)
	ok(c.issue_order(cmd,player,0).ok and c.advance(1).ok and c.view(1).value.active==cmd,"typed keys distinguish enemy")
	var wrong:=order("player",2,2,"follow",{},2)
	var wait:=order("player",3,2,"advance")
	ok(c.issue_order(wrong,player,0).ok and c.issue_order(wait,player,0).ok and c.advance(2).ok and c.view(1).value.active==cmd and c.view(1).value.queued==[wait],"invalid target preserves active and FIFO")
	ok(c.complete_active(1,"player","player1","executed").ok and c.view(1).value.active==wait and not c.complete_active(1,"player","player1","executed").ok,"stale completion")
	ok(c.split(1,7,[h(12)],player,0).ok and c.member_formation(h(12)).value==7,"split")
	ok(c.merge(1,7,player,0,0).ok and c.member_formation(h(12)).value==1 and not c.view(7).ok,"merge")
	ok(c.merge(1,2,player,0,0).get("ok",true) == false,"typed groups cannot merge")
	print("QA_FORM ", "PASS" if errors==0 else "FAIL", " checks=",checks," failures=",errors)
	quit(1 if errors else 0)
