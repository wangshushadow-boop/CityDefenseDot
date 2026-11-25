extends SceneTree

const Inv = preload("res://shared/inventory/inventory.gd")
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	var original := Inv.new()
	var policy := func(reason, _source, _resource, mint): return reason == "quest" and mint
	check(original.initialize({"stash":{"kind":"inventory","capacity":4}},[{"holder":"stash","resource":{"kind":"instance","id":"legacy"},"amount":1}],policy).ok,"existing inventory")
	var before := original.snapshot()
	var added := {"pack":{"kind":"inventory","capacity":1},"hand":{"kind":"slot"}}
	var grants := [{"holder":"pack","instance_id":"knife"},{"holder":"hand","instance_id":"sword"}]
	var fork := original.fork_with_locations(added,grants,"create")
	check(fork.ok,"fork")
	if not fork.ok: quit(1); return
	var next: RefCounted = fork.value
	check(original.snapshot()==before,"candidate isolation")
	check(next.owner_of("legacy").value=="stash" and next.owner_of("sword").value=="hand" and next.owner_of("knife").value=="pack","original and new unique instances")
	check(next.ledger_for("create").value.size()==2,"initial issuance recorded")
	check(not next.mint_or_burn("bad","pack",{"kind":"instance","id":"x"},1,true,"holder_endowment","create").ok,"endowment grant not retained")
	check(next.mint_or_burn("quest-line","stash",{"kind":"instance","id":"reward"},1,true,"quest","quest42").ok,"legacy authorization preserved")
	check(not original.fork_with_locations(added,[{"holder":"stash","instance_id":"forged"}],"no").ok,"opening only issues to new holders")
	check(not original.fork_with_locations(added,[{"holder":"hand","instance_id":"legacy"}],"reuse").ok,"cannot duplicate live instance")
	check(not next.fork_with_locations({"pack":{"kind":"inventory","capacity":999}}).ok,"cannot redefine old capacity")
	var burning := Inv.new()
	check(burning.initialize({"old":{"kind":"inventory","capacity":2}},[],func(_r,_s,_res,_m):return true).ok,"history source")
	check(burning.commit(burning.mint_or_burn("issued","old",{"kind":"instance","id":"lost"},1,true,"reward","case").value).ok,"old issue")
	check(burning.commit(burning.mint_or_burn("spent","old",{"kind":"instance","id":"lost"},1,false,"wear","case").value).ok,"old burn")
	check(not burning.fork_with_locations({"new":{"kind":"slot"}},[{"holder":"new","instance_id":"lost"}],"restore-lost").ok,"burned item not recreated as a new endowment")
	check(not original.fork_with_locations({"pack":{"kind":"slot"}},[{"holder":"pack","instance_id":"a"},{"holder":"pack","instance_id":"b"}],"overflow").ok,"cannot exceed slot capacity")
	check(not original.fork_with_locations({"bad":{"kind":"unknown"}}).ok,"unknown location rejected")
	check(original.snapshot()==before,"all rejected branches keep origin")
	var loaded := Inv.new()
	check(loaded.restore(next.snapshot(),policy).ok and loaded.snapshot()==next.snapshot(),"cold restore and ledger replay")
	var unpacked := loaded.instance_layout()
	unpacked.locations.clear()
	unpacked.owners.clear()
	check(loaded.owner_of("knife").value=="pack","projection isolated")
	print("P3_GEAR_INVENTORY checks=",passed+failed," failures=",failed)
	quit(1 if failed else 0)
