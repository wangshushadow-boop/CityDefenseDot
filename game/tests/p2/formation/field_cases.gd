extends RefCounted
const Field = preload("res://mission/formation/ports/field_formation.gd")
const Layout = preload("res://mission/formation/slot_layout.gd")
const R = preload("res://contracts/result.gd")
const MID := "fixture-field"
var _tokens := {}
var _check: Callable
var _reachable: Callable
var _project: Callable
var _open: Vector3
var _narrow: Vector3

func _init(check: Callable, reachable: Callable, project: Callable, open: Vector3, narrow: Vector3) -> void:
	_check = check
	_reachable = reachable
	_project = project
	_open = open
	_narrow = narrow
	for actor in ["player","captain","guest","enemy"]:
		_tokens[actor] = RefCounted.new()

func _auth(token: Variant) -> Dictionary:
	for actor in _tokens:
		if is_same(_tokens[actor], token):
			return R.ok(actor)
	return R.fail("Unauthorized")

func _ok(value: bool, label: String) -> void:
	_check.call(value, label)

func _order(actor: String, seq: int, tick: int, kind: String, p: Dictionary = {}, target: Variant = null, ids: Array = [1]) -> Dictionary:
	return {"mission_id":MID, "issuer_id":actor, "order_id":actor + str(seq), "client_sequence":seq,
		"issued_tick":tick, "formation_ids":ids, "order_type":kind, "parameters":p,
		"target_formation_id":target if typeof(target) == TYPE_INT else null,
		"target_position":target if typeof(target) == TYPE_ARRAY else null}

func _new() -> Field:
	var f := Field.new(MID, _auth, _reachable)
	_ok(f.add_formation(1, "allies", "player", [{"index":1,"generation":1},{"index":2,"generation":1},{"index":3,"generation":1}]).ok, "deploy player")
	_ok(f.add_formation(2, "opponents", "enemy", [{"index":4,"generation":1}]).ok, "deploy enemy with separate credentials")
	return f

func _submit(f: Field, o: Dictionary, revision: int = 0) -> Dictionary:
	return f.issue_order(o, _tokens[o.issuer_id], revision)

func _state(f: Field, o: Dictionary, id: int = 1) -> Dictionary:
	return f.order_status(o.issuer_id, o.order_id).value[id]

func _priority(reverse: bool) -> void:
	var f := _new()
	_ok(f.set_delegate(1, "captain", _tokens.player, 0).value == 1, "scoped grant")
	var player := _order("player", 1, 1, "hold")
	var ai := _order("captain", 1, 1, "retreat")
	for o in ([ai,player] if reverse else [player,ai]):
		_ok(_submit(f, o, 1).ok, "admit owner/delegate in both invocation orders")
	_ok(f.advance(1).ok and f.view(1).value.active == player, "T-FORM-01 player owns active order")
	_ok(_state(f, ai).state == "Replaced" and _state(f, ai).reason == "player_priority", "T-FORM-01 AI receives reason")
	_ok(_submit(f, player, 0).value.state == "Pending", "retry preserves admission receipt even after tick")
	var collision := player.duplicate(true)
	collision.order_type = "charge"
	_ok(_submit(f, collision, 1).error.field == "order_id", "collision after auth")
	var stale := _order("player", 1, 2, "advance")
	stale.order_id = "different"
	_ok(_submit(f, stale, 1).error.field == "sequence_or_tick", "monotone sequence")
	_ok(f.set_delegate(1, "", _tokens.player, 1).ok and _submit(f, ai, 1).error.code == "Unauthorized", "revoked replay cannot see cached result")
	_ok(f.set_delegate(1, "captain", _tokens.player, 2).ok and _submit(f, ai, 1).error.code == "Unauthorized", "re-grant does not resurrect old token")

func _authority() -> void:
	var f := _new()
	var guest := _order("guest", 1, 1, "hold")
	var player := _order("player", 1, 1, "hold")
	var mixed := _order("player", 2, 1, "retreat", {}, null, [1,2])
	_ok(_submit(f, player).ok, "initial allowed order")
	_ok(f.issue_order(player, _tokens.guest, 0).error.code == "Unauthorized", "impersonation fails before dedup")
	_ok(f.issue_order(player, {"actor":"player"}, 0).error.code == "Unauthorized", "untrusted dictionary")
	_ok(_submit(f, guest).error.code == "Unauthorized" and _submit(f, mixed).error.code == "Unauthorized", "T-FORM-04 deny other player and partial grant")
	var wrong_scope := player.duplicate(true)
	wrong_scope.mission_id = "another"
	_ok(_submit(f, wrong_scope).error.code == "Unauthorized", "mission scope before cache")
	_ok(f.advance(1).ok and f.view(1).value.active == player and f.view(2).value.active == null, "T-FORM-04 no foreign mutation")
	_ok(f.set_delegate(1, "guest", _tokens.guest, 0).error.code == "Unauthorized", "cannot self-authorize")
	var next := _order("player", 2, 2, "advance")
	_ok(_submit(f, next, 4).error.field == "control_revision", "stale grant rejected")
	_ok(not f.advance(3).ok, "skipped tick rejected")

func _field_failures() -> void:
	var f := _new()
	var good := _order("player", 1, 1, "move", {}, [-500000,0,-799000])
	var bad := _order("player", 2, 2, "move", {}, [16000000,0,16000000])
	_ok(_submit(f, good).ok and f.advance(1).ok and _state(f, good).state == "Active", "reachable order via engine map")
	_ok(_submit(f, bad).ok and f.advance(2).ok, "unreachable command evaluated on field tick")
	_ok(_state(f,bad).state == "Failed" and f.view(1).value.feedback.reason == "unreachable" and f.view(1).value.active == good, "T-FORM-03 navigation failure preserves active movement and publishes reason")
	_ok(f.set_routing(1,true).ok and f.view(1).value.active == null and f.view(1).value.feedback.reason == "routing", "T-FORM-03 routing stops active work and publishes reason")
	var hold := _order("player",3,3,"hold")
	_ok(_submit(f,hold).ok and f.advance(3).ok and _state(f,hold).reason == "routing", "routing denies new orders")
	_ok(f.set_routing(1,false).ok, "rally")
	var ally_charge := _order("player",4,4,"charge",{},1)
	var enemy_charge := _order("player",5,4,"charge",{},2)
	_ok(_submit(f,ally_charge).ok and _submit(f,enemy_charge).ok and f.advance(4).ok and _state(f,ally_charge).reason == "invalid_target" and _state(f,enemy_charge).state == "Active", "charge validates target team")
	_ok(f.assign_members(2,[]).ok and f.advance(5).ok and _state(f,enemy_charge).reason == "invalid_target", "active target became invalid")
	var siege := _order("player",6,6,"breach_gate")
	_ok(_submit(f,siege).error.field == "order_type", "field mode rejects siege-only command")
	var moving := _order("player",6,6,"advance")
	_ok(_submit(f,moving).ok and f.advance(6).ok, "new movement after route failure")
	var blocked := f.build_slot_targets(1,_open,0,1,0.5,_project.bind(_open))
	_ok(not blocked.ok and f.view(1).value.terrain_feedback.field == "corridor_width" and _state(f,moving).reason == "unreachable", "slot failure reaches execution and view")

func _queue() -> void:
	var f := _new()
	var move := _order("player",1,1,"move",{},[-500000,0,-799000])
	var later := _order("player",2,1,"advance")
	var mode := _order("player",3,1,"hold_fire")
	for o in [move,later,mode]:
		_ok(_submit(f,o).ok,"queue input")
	_ok(f.advance(1).ok and f.view(1).value.active == move and f.view(1).value.queued == [later] and f.view(1).value.fire_mode == "hold_fire", "type default immediate / replace / append")
	_ok(not f.complete_active(1,"player",move.order_id,"executed").ok and f.complete_active(1,"player",move.order_id,"arrived").ok, "completion condition")
	_ok(f.view(1).value.active == later and _state(f,move).state == "Completed", "FIFO after completion")
	var expiring := _order("player",4,2,"advance",{"expires_tick":2})
	_ok(_submit(f,expiring).ok and f.advance(2).ok and f.advance(3).ok and _state(f,expiring).reason == "expired", "queued expiry without completing active")
	var extra := _order("player",5,4,"advance")
	var cancel := _order("player",6,4,"cancel")
	_ok(_submit(f,extra).ok and _submit(f,cancel).ok and f.advance(4).ok, "cancel at tick")
	_ok(f.view(1).value.queued.is_empty() and f.view(1).value.active == null and _state(f,later).reason == "cancelled" and _state(f,extra).reason == "cancelled", "cancel clears active and queued with receipts")

func _organization() -> void:
	var f := _new()
	var h := {"index":2,"generation":1}
	var before: Array = f.view(1).value.members
	_ok(not f.split(1,4,[{"index":2,"generation":9}],_tokens.player,0).ok and f.view(1).value.members == before and not f.view(4).ok, "invalid selection rollback")
	_ok(not f.add_formation(5,"allies","player",[h]).ok and not f.view(5).ok, "unique formation index")
	var split_order := _order("player",1,1,"split",{"new_formation_id":4,"members":[h]})
	_ok(_submit(f,split_order).ok and f.advance(1).ok and f.view(4).value.members == [h] and f.view(1).value.members.size() == 2, "split through authenticated order")
	var assign := _order("player",2,2,"assign_members",{"members":[h]})
	var enemy_merge := _order("player",3,2,"merge",{"source_id":2})
	var delegate := _order("player",4,2,"appoint_captain",{"actor":"captain"})
	_ok(_submit(f,assign).ok and _submit(f,enemy_merge).error.code == "Unauthorized" and _submit(f,delegate).ok and f.advance(2).ok, "organization scope")
	_ok(_state(f,assign).state == "Failed" and f.view(1).value.members.size() == 2 and f.view(1).value.delegate == "captain", "no silent stealing")
	var merge_order := _order("player",5,3,"merge",{"source_id":4})
	_ok(_submit(f,merge_order,1).ok and f.advance(3).ok and f.view(1).value.members == before and not f.view(4).ok, "merge exact conservation")
	_ok(_submit(f,merge_order,1).ok and not f.add_formation(4,"allies","player",[]).ok, "retired ID and retry")
	var ai := _order("captain",1,4,"hold")
	_ok(_submit(f,ai,1).ok and f.set_delegate(1,"",_tokens.player,1).ok and f.advance(4).ok and _state(f,ai).reason == "control_revoked", "pending grant revoked immediately")
	before.clear()
	_ok(f.view(1).value.members.size() == 3, "read isolation")

func _commands_and_transfers() -> void:
	var f := _new()
	var h := {"index":8,"generation":2}
	_ok(f.add_formation(3,"allies","player",[h]).ok and f.member_formation(h).value == 3, "handle index lookup")
	var modes := [
		_order("player",1,1,"follow",{},3), _order("player",2,1,"face",{"facing_microradians":789}),
		_order("player",3,1,"face_enemy",{},2), _order("player",4,1,"keep_distance",{"distance_mm":4000}),
		_order("player",5,1,"mount"), _order("player",6,1,"hold_fire"), _order("player",7,1,"use_ranged")]
	for o in modes:
		_ok(_submit(f,o).ok, "mode " + o.order_type)
	_ok(f.advance(1).ok, "advance modes")
	var v: Dictionary = f.view(1).value
	_ok(v.active.order_type == "follow" and v.facing_target_id == 2 and v.facing_microradians == 789 and v.distance_mm == 4000 and v.mounted and v.use_ranged and v.fire_mode == "hold_fire", "independent formation constraints")
	var after := [_order("player",8,2,"fire_at_will"), _order("player",9,2,"dismount"), _order("player",10,2,"free_attack")]
	for o in after:
		_ok(_submit(f,o).ok, "mode " + o.order_type)
	_ok(f.advance(2).ok and not f.view(1).value.mounted and f.view(1).value.fire_mode == "fire_at_will" and f.view(1).value.active.order_type == "free_attack", "second set of modes")
	var send := _order("player",11,3,"assign_members",{"source_id":3,"members":[h]})
	var invented := _order("player",12,3,"assign_members",{"members":[{"index":99,"generation":5}]})
	_ok(_submit(f,send).ok and _submit(f,invented).ok and f.advance(3).ok and _state(f,send).state == "Completed" and _state(f,invented).state == "Failed", "only previously deployed owned members transferred")
	_ok(f.member_formation(h).value == 1 and f.view(3).value.members.is_empty() and f.view(1).value.members_revision > v.members_revision and not f.member_formation({"index":8,"generation":1}).ok, "inverse index and revision")
	_ok(f.set_delegate(1,"captain",_tokens.player,0).ok, "different control versions")
	var both := _order("player",13,4,"hold",{},null,[1,3])
	_ok(not _submit(f,both,0).ok and f.issue_order(both,_tokens.player,{1:1,3:0}).ok and f.advance(4).ok and f.view(3).value.active == both and f.view(1).value.active == both, "multi-select with independent revisions")
	var late := _order("captain",1,5,"retreat")
	_ok(_submit(f,late,1).ok and f.advance(5).ok and _state(f,late).reason == "player_priority" and f.view(1).value.active == both, "no silent override on later tick")
	var ally := _order("player",14,6,"follow",{},2)
	_ok(_submit(f,ally,1).ok and f.advance(6).ok and _state(f,ally).reason == "invalid_target", "follow requires friendly target")

func _failed_owner_arbitration(reverse: bool) -> void:
	for kind in ["split","merge","assign_members","delegate"]:
		var f := Field.new(MID, _auth, _reachable)
		var h := {"index":1,"generation":1}
		var second := {"index":2,"generation":1}
		var foreign := {"index":3,"generation":1}
		_ok(f.add_formation(1,0,"player",[h,second]).ok, "numeric team")
		_ok(f.add_formation(2,"0","player",[foreign]).ok, "text team")
		_ok(f.set_delegate(1,"captain",_tokens.player,0).ok, "captain")
		var parameters := {"split":{"new_formation_id":3,"members":[{"index":1,"generation":2}]},
			"merge":{"source_id":2}, "assign_members":{"source_id":2,"members":[foreign]}, "delegate":{"actor":"player"}}
		var bad := _order("player",1,1,kind,parameters[kind])
		var good := _order("captain",1,1,"retreat")
		for o in ([good,bad] if reverse else [bad,good]):
			_ok(_submit(f,o,1).ok, "admit conflicting requests " + kind)
		_ok(f.advance(1).ok and _state(f,bad).state == "Failed" and _state(f,good).state == "Active", "only successful owner orders claim " + kind)
		_ok(f.view(1).value.active == good and f.member_formation(h).value == 1 and f.member_formation(foreign).value == 2 and not f.view(3).ok, "failed organization keeps indices " + kind)
		var charge := _order("player",2,2,"charge",{},2)
		var follow := _order("player",3,3,"follow",{},2)
		_ok(_submit(f,charge,1).ok and f.advance(2).ok and _state(f,charge).state == "Active", "0 and text 0 are distinct enemies")
		_ok(_submit(f,follow,1).ok and f.advance(3).ok and _state(f,follow).reason == "invalid_target" and f.view(1).value.active == charge, "mixed-key hostile group cannot be followed")

func _standing_owner() -> void:
	for cancel in [false,true]:
		var f := _new()
		var hold := _order("player",1,1,"hold")
		var retreat := _order("captain",1,2,"retreat")
		_ok(_submit(f,hold).ok and f.advance(1).ok and f.set_delegate(1,"captain",_tokens.player,0).ok, "grant after active hold")
		_ok(_submit(f,retreat,1).ok and f.advance(2).ok and f.view(1).value.active == hold and _state(f,retreat).reason == "player_priority", "standing owner survives new grant")
		var tick := 3
		if cancel:
			_ok(_submit(f,_order("player",2,tick,"cancel"),1).ok and f.advance(tick).ok, "owner cancels")
			tick += 1
		else:
			_ok(f.complete_active(1,"player",hold.order_id,"executed").ok, "owner completed")
		var next := _order("captain",2,tick,"retreat")
		_ok(_submit(f,next,1).ok and f.advance(tick).ok and f.view(1).value.active == next, "delegate moves after explicit release")

func _same_tick_roster_change() -> void:
	var f := _new()
	var a := {"index":8,"generation":1}
	_ok(f.add_formation(3,"allies","player",[a,{"index":9,"generation":1}]).ok and f.set_delegate(3,"captain",_tokens.player,0).ok, "second owned group")
	var first := _order("player",1,1,"split",{"new_formation_id":4,"members":[{"index":1,"generation":1}]})
	var second := _order("player",2,1,"split",{"new_formation_id":4,"members":[a]},null,[3])
	var ai := _order("captain",1,1,"hold",{},null,[3])
	_ok(_submit(f,ai,1).ok and _submit(f,first).ok and _submit(f,second,1).ok and f.advance(1).ok, "two competing split commits")
	_ok(_state(f,first).state == "Completed" and _state(f,second,3).state == "Failed" and f.member_formation(a).value == 3 and f.view(3).value.active == ai, "late split conflict does not suppress delegate")
	# The player owns group 1 and acts as a delegate on group 2. With a third
	# issuer owning group 2, group 1 remains available to its own delegate.
	_ok(f.set_delegate(2,"player",_tokens.enemy,0).ok and f.set_delegate(1,"captain",_tokens.player,0).ok, "mixed authority")
	var mixed := _order("player",3,2,"retreat",{},null,[1,2])
	var enemy := _order("enemy",1,2,"hold",{},null,[2])
	var free := _order("captain",2,2,"advance")
	for o in [free,mixed,enemy]:
		_ok(_submit(f,o,1).ok, "multi-target arbitration")
	_ok(f.advance(2).ok and _state(f,mixed).reason == "player_priority" and f.view(1).value.active == free and f.view(2).value.active == enemy, "rejected mixed scope leaves other delegate available")
	_ok(f.complete_active(2,"enemy",enemy.order_id,"executed").ok and f.set_delegate(1,"enemy",_tokens.player,1).ok, "release for mutual delegation")
	var enemy_mixed := _order("enemy",2,3,"advance",{},null,[1,2])
	var player_mixed := _order("player",4,3,"hold",{},null,[1,2])
	for o in [player_mixed,enemy_mixed]:
		_ok(f.issue_order(o,_tokens[o.issuer_id],{1:2,2:1}).ok, "mutual mixed scopes")
	_ok(f.advance(3).ok and f.view(1).value.active == enemy_mixed and f.view(2).value.active == enemy_mixed and _state(f,player_mixed).reason == "player_priority", "mutual dependency resolves in stable order")

func _through_orders() -> void:
	var f := _new()
	var roster := []
	for i in range(100,600):
		roster.append({"index":i,"generation":1})
	_ok(f.assign_members(1,roster).ok,"owner roster 500")
	var tick := 0
	for kind: String in Layout.KINDS:
		tick += 1
		var order := _order("player",tick,tick,"layout",{"layout":kind})
		_ok(_submit(f,order).ok and f.advance(tick).ok and f.view(1).value.layout == kind,"layout executed through authority " + kind)
		var wide := f.build_slot_targets(1,_open,0,1,INF,_project.bind(_open))
		var corridor := f.build_slot_targets(1,_narrow,0,1,1,_project.bind(_narrow))
		var again := f.build_slot_targets(1,_open,0,1,INF,_project.bind(_open))
		_ok(wide.ok and corridor.ok and again.ok and wide.value.slots == again.value.slots,"T-FORM-02 open/corridor/recovery " + kind)
		var survivors := roster.slice(1)
		_ok(f.assign_members(1,survivors).ok,"apply casualty")
		var loss := f.build_slot_targets(1,_open,0,1,INF,_project.bind(_open))
		_ok(loss.ok and loss.value.slots == wide.value.slots.slice(1),"T-FORM-02 local casualty " + kind)
		_ok(f.assign_members(1,roster).ok,"refill wave")

func run() -> void:
	_priority(false)
	_priority(true)
	_authority()
	_field_failures()
	_queue()
	_organization()
	_commands_and_transfers()
	_failed_owner_arbitration(false)
	_failed_owner_arbitration(true)
	_standing_owner()
	_same_tick_roster_change()
	_through_orders()
