extends SceneTree

const Gear = preload("res://campaign/character/gear.gd")
const Inv = preload("res://shared/inventory/inventory.gd")
const A := "hero/0abf1234-6690-4641-a37d-549ee1d24f88"
const B := "hero/118d1234-6690-4641-a37d-549ee1d24f88"
const C := "hero/4a571234-6690-4641-a37d-549ee1d24f88"
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL ",label)

func hero(id: String, occupation: String, riding: int) -> Dictionary:
	return {"id":id,"name":"云川","occupation":occupation,"life_status":"Healthy","skills":{"riding":{"level":riding}}}

func equip(inv: RefCounted, h: Dictionary, profile: String, slot: String, id: String, txn: String) -> Dictionary:
	return Gear.apply(inv,h,"equip",{"profile":profile,"slot":slot,"item_id":id},txn)

func item(h: Dictionary, kind: String) -> String:
	return Gear.ITEM+h.id+"/"+kind

func run_tests() -> void:
	var a := hero(A,"guard",10)
	var b := hero(B,"caravan",4)
	var c := hero(C,"healer",10)
	var heroes := {A:a,B:b,C:c}
	var issued := Gear.apply(null,a,"create",{},"one")
	check(issued.ok,"character inventory and equipment creation")
	if not issued.ok: return
	var created_b := Gear.apply(issued.value,b,"create",{},"two")
	check(created_b.ok,"second holder added with inventory already populated")
	if not created_b.ok: return
	var inventory: RefCounted = Gear.apply(created_b.value,c,"create",{},"three").value
	check(Gear.validate(inventory,heroes).ok,"three hero inventory consistent")
	var before: Dictionary = inventory.snapshot()
	check(Gear.apply(inventory,b,"create",{},"two").value.snapshot()==before,"replay create")
	check(not Gear.apply(inventory,a,"create",{},"two").ok,"changed create conflict")
	var read := Gear.view(inventory,a).value as Dictionary
	check(read.profiles.combat.off_hand==item(a,"shield") and read.profiles.civil.body==item(a,"robe"),"starting profiles")
	check(not equip(inventory,a,"combat","main_hand",item(a,"staff"),"twohand").ok,"two-handed blocked by shield")
	check(not equip(inventory,a,"combat","main_hand",item(a,"lance"),"nomount").ok,"mounted lance requires horse")
	check(not equip(inventory,b,"combat","main_hand",item(b,"lance"),"low").ok,"riding skill requirement")
	check(not equip(inventory,b,"combat","mount","","mounted").ok,"cannot remove mount under tack")
	check(not equip(inventory,a,"civil","main_hand",item(a,"lance"),"civil").ok,"battle weapon excluded from civil profile")
	check(not equip(inventory,a,"civil","main_hand",item(c,"knife"),"foreign").ok,"cannot draw another bag")
	var reservation: RefCounted = inventory.fork_with_locations().value
	var held: Dictionary = reservation.reserve("reserve-sale","order",reservation.owner_of(item(a,"clan_blade")).value,{"kind":"instance","id":item(a,"clan_blade")},1,"merchant")
	check(held.ok and reservation.commit(held.value).ok,"old item is reserved")
	var selectable: Dictionary = Gear.view(reservation,a).value.items[item(a,"knife")].options[0]
	check(not selectable.allowed and selectable.reason=="原装备已预留" and not equip(reservation,a,"combat","main_hand",item(a,"knife"),"reserved-swap").ok,"reserved displaced gear refused in preview and transaction")
	check(not equip(inventory,a,"combat","main_hand","missing","missing").ok,"shortage refused")
	check(inventory.snapshot()==before,"rejected commands leave complete ledger unchanged")
	var free := equip(inventory,a,"combat","off_hand","","free")
	check(free.ok,"remove shield")
	if not free.ok: return
	var two := equip(free.value,a,"combat","main_hand",item(a,"staff"),"swap")
	check(two.ok,"atomic swap")
	if not two.ok: return
	var swapped: RefCounted = two.value
	check(swapped.ledger_for("swap").value.size()==2,"one receipt with two legs")
	check(free.value.snapshot()!=swapped.snapshot() and inventory.snapshot()==before,"prior versions unmodified")
	check(not equip(swapped,a,"combat","off_hand",item(a,"shield"),"blocked").ok,"shield cannot join two-handed weapon")
	check(equip(swapped,a,"combat","main_hand",item(a,"staff"),"swap").value.snapshot()==swapped.snapshot(),"retry exactly once")
	check(not equip(swapped,a,"civil","main_hand",item(a,"knife"),"swap").ok,"txn conflict")
	check(equip(swapped,a,"civil","main_hand",item(a,"knife"),"civil-knife").ok,"civil weapon")
	b.skills.riding.level=8
	var mounted := equip(swapped,b,"combat","main_hand",item(b,"lance"),"lance")
	check(mounted.ok,"meet mounted weapon requirements")
	if not mounted.ok: return
	var retired := b.duplicate(true)
	check(not Gear.apply(mounted.value,b,"inherit",{"heir":c},"alive").ok,"cannot inherit from active holder")
	retired.life_status="Retired"
	var transfer := Gear.apply(mounted.value,retired,"inherit",{"heir":c},"succession")
	check(transfer.ok,"child receives family property")
	if not transfer.ok: return
	var final: RefCounted = transfer.value
	var old := Gear.view(final,b).value as Dictionary
	var new_holder := Gear.view(final,c).value as Dictionary
	check(new_holder.items.has(item(b,"clan_blade")) and new_holder.items.has(item(b,"mare")),"heir owns family assets")
	check(old.items.has(item(b,"saddle")) and old.items.has(item(b,"knife")) and not new_holder.items.has(item(b,"saddle")),"personal property kept")
	check(old.profiles.combat.harness=="" and old.profiles.combat.main_hand=="","dependent personal tack and lance put away")
	check(final.instance_layout().owners.size()==inventory.instance_layout().owners.size(),"instance conservation")
	check(Gear.validate(final,heroes).ok,"valid final repository")
	check(not equip(final,retired,"combat","main_hand",item(b,"staff"),"terminal").ok,"retired control revoked")
	var captive := c.duplicate(true)
	captive.life_status="Captive"
	check(not Gear.apply(mounted.value,retired,"inherit",{"heir":captive},"invalid-heir").ok,"captive heir rejected")
	var reloaded := Inv.new()
	check(reloaded.restore(final.snapshot()).ok and Gear.validate(reloaded,heroes).ok,"cold replay of full transaction history")
	check(Gear.apply(reloaded,retired,"inherit",{"heir":c},"succession").value.snapshot()==final.snapshot(),"cold inheritance retry")
	check(not Gear.validate(reloaded,{A:a,B:b}).ok,"foreign hero orphan rejected")
	check(not Gear.validate(reloaded,{A:b,B:a,C:c}).ok,"swapped character ID rejected")
	check(not Gear.view(final,{"id":A,"occupation":"guard","skills":{"riding":[]}}).ok,"invalid skill shape rejected")
	var corrupt: RefCounted = reloaded.fork_with_locations().value
	var plan: Dictionary = corrupt.prepare_transfer("moved",corrupt.owner_of(item(a,"knife")).value,corrupt.owner_of(item(c,"knife")).value,{"kind":"instance","id":item(a,"knife")},1,"transfer","test")
	check(plan.ok and corrupt.commit(plan.value).ok and not Gear.validate(corrupt,heroes).ok,"reject private equipment assigned across heroes")

func _initialize() -> void:
	run_tests()
	print("P3_GEAR checks=",passed+failed," failures=",failed)
	quit(1 if failed else 0)
