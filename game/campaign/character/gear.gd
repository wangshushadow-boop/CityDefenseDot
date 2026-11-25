extends RefCounted
## Equipment is a view of the campaign inventory's unique instance holders.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const C = preload("res://contracts/canonical.gd")
const Inventory = preload("res://shared/inventory/inventory.gd")
const HOLDER := "@chr.holder/"
const ITEM := "@chr.gear/"
const BAG_CAPACITY := 1024
const SLOTS := {"combat":["main_hand","off_hand","body","mount","harness"], "civil":["main_hand","body"]}
const SLOT_LABELS := {"main_hand":"主手","off_hand":"副手","body":"衣甲","mount":"坐骑","harness":"马具"}
# The item key is part of the v1 instance ID. Labels carry no inventory identity.
const ITEMS := {
	"clan_blade":{"label":"传家环首刀","slot":"main_hand","family":true},
	"knife":{"label":"随身短刀","slot":"main_hand","civil":true},
	"robe":{"label":"素布便袍","slot":"body","civil":true},
	"coat":{"label":"夹棉行衣","slot":"body"},
	"shield":{"label":"藤编圆盾","slot":"off_hand"},
	"staff":{"label":"双手长杖","slot":"main_hand","two_handed":true},
	"mare":{"label":"河曲驮马","slot":"mount","family":true},
	"saddle":{"label":"毡面马鞍","slot":"harness","needs_mount":true},
	"lance":{"label":"骑矛","slot":"main_hand","needs_mount":true,"skill":"riding","minimum":8},
}
const COMMON := {"clan_blade":"combat/main_hand","coat":"combat/body","robe":"civil/body","knife":"bag"}
const OCCUPATIONS := {
	"guard":{"shield":"combat/off_hand","staff":"bag","lance":"bag"},
	"caravan":{"mare":"combat/mount","saddle":"combat/harness","lance":"bag","staff":"bag"},
	"healer":{"staff":"bag"},
}


static func _bag(id: String) -> String:
	return HOLDER + id + "/bag"


static func _slot(id: String, profile: String, slot: String) -> String:
	return HOLDER + id + "/" + profile + "/" + slot


static func _holders(id: String) -> Dictionary:
	var result := {_bag(id):{"kind":"inventory","capacity":BAG_CAPACITY}}
	for profile in SLOTS:
		for slot in SLOTS[profile]:
			result[_slot(id,profile,slot)] = {"kind":"slot"}
	return result


static func _kit(hero: Dictionary) -> Dictionary:
	var kit := COMMON.duplicate()
	kit.merge(OCCUPATIONS[hero.occupation])
	return kit


static func _known_hero(hero: Dictionary) -> bool:
	if not V.typed_id(hero.get("id"),"hero") or hero.get("occupation") not in OCCUPATIONS:
		return false
	var skills: Variant = hero.get("skills")
	return skills is Dictionary and skills.get("riding") is Dictionary and V.integer(skills.riding.get("level"))


static func _item_id(hero_id: String, kind: String) -> String:
	return ITEM + hero_id + "/" + kind


static func _declared_item(id: String) -> bool:
	var parts := id.trim_prefix(ITEM).split("/")
	return id.begins_with(ITEM) and parts.size() == 3 and V.typed_id(parts[0]+"/"+parts[1],"hero") and ITEMS.has(parts[2])


static func _layout(layout: Dictionary, hero_id: String) -> Dictionary:
	var profiles := {}
	var bag: Array = []
	var bag_id := _bag(hero_id)
	var mapping := {}
	for profile in SLOTS:
		profiles[profile] = {}
		for slot in SLOTS[profile]:
			mapping[_slot(hero_id,profile,slot)] = [profile,slot]
			profiles[profile][slot] = ""
	for id in layout.owners:
		var holder: String = layout.owners[id]
		if holder == bag_id:
			bag.append(id)
		elif mapping.has(holder):
			var at: Array = mapping[holder]
			profiles[at[0]][at[1]] = id
	bag.sort()
	return {"profiles":profiles,"bag":bag}


static func _reason(hero: Dictionary, kind: String, profile: String, slot: String, equipped: Dictionary) -> String:
	var spec: Dictionary = ITEMS[kind]
	if spec.slot != slot or (profile == "civil" and not spec.get("civil",false)):
		return "该物品不适用此装备槽"
	var level: int = hero.get("skills",{}).get(spec.get("skill",""),{}).get("level",0)
	if level < spec.get("minimum",0):
		return "骑术需达到 %d 级" % spec.minimum
	if spec.get("needs_mount",false) and equipped.get("mount","") == "":
		return "需要先装备坐骑"
	if spec.get("two_handed",false) and equipped.get("off_hand","") != "":
		return "请先卸下副手物品"
	var main: String = equipped.get("main_hand","")
	if slot == "off_hand" and main != "" and ITEMS.get(main.get_file(),{}).get("two_handed",false):
		return "主手物品需要双手"
	return ""


static func _remove_reason(slot: String, equipped: Dictionary) -> String:
	if slot == "mount":
		var main: String = equipped.get("main_hand","")
		if equipped.get("harness","") != "" or ITEMS.get(main.get_file(),{}).get("needs_mount",false):
			return "请先卸下马具及骑乘武器"
	return ""


static func _row(item: String) -> Dictionary:
	var kind := item.get_file()
	var spec: Dictionary = ITEMS[kind]
	var needs: Array[String] = []
	if spec.get("two_handed",false):
		needs.append("双手")
	if spec.get("needs_mount",false):
		needs.append("已装备坐骑")
	if spec.has("minimum"):
		needs.append("骑术 %d 级" % spec.minimum)
	return {"item_id":item,"label":spec.label,"slot":spec.slot,
		"ownership":"family" if spec.get("family",false) else "personal","requirements":"、".join(needs)}


static func view(inv: Variant, hero: Dictionary) -> Dictionary:
	if not _known_hero(hero) or not inv is Inventory:
		return R.fail("NotFound","character.gear")
	var layout: Dictionary = inv.instance_layout()
	if not layout.locations.has(_bag(hero.id)):
		return R.fail("NotFound","character.gear")
	var worn := _layout(layout,hero.id)
	var items := {}
	var bag := []
	for profile in worn.profiles:
		for slot in worn.profiles[profile]:
			var id: String = worn.profiles[profile][slot]
			if not id.is_empty():
				if not _declared_item(id):
					return R.fail("InvalidState","character.item")
				items[id] = _row(id)
	for id in worn.bag:
		var kind: String = id.get_file()
		if not _declared_item(id):
			return R.fail("InvalidState","character.item")
		var row := _row(id)
		row.options = []
		for profile in SLOTS:
			if row.slot not in SLOTS[profile]:
				continue
			var reason := _reason(hero,kind,profile,row.slot,worn.profiles[profile])
			var displaced: String = worn.profiles[profile][row.slot]
			if hero.get("life_status") in ["Captive","Retired","Dead"]:
				reason = "当前人物状态不能换装"
			elif reason.is_empty() and inv.available(_bag(hero.id),{"kind":"instance","id":id}).get("value",0) != 1:
				reason = "物品已预留"
			elif reason.is_empty() and not displaced.is_empty() and inv.available(_slot(hero.id,profile,row.slot),{"kind":"instance","id":displaced}).get("value",0) != 1:
				reason = "原装备已预留"
			row.options.append({"profile":profile,"slot":row.slot,"allowed":reason.is_empty(),"reason":reason})
		items[id] = row
		bag.append(row)
	return R.ok({"profiles":worn.profiles,"bag":bag,"items":items,"slot_labels":SLOT_LABELS.duplicate()})


static func _line(item: String, src: String, dst: String, op: String, source: String) -> Dictionary:
	return {"src":src,"dst":dst,"resource":{"kind":"instance","id":item},"amount":1,"reason":op,"source_ref":source}


static func _equip(inv: Inventory, hero: Dictionary, args: Dictionary, source: String) -> Dictionary:
	if args.size() != 3 or not args.has_all(["profile","slot","item_id"]) or not args.item_id is String:
		return R.fail("InvalidArgument","equipment")
	if not SLOTS.has(args.profile) or args.slot not in SLOTS[args.profile]:
		return R.fail("InvalidArgument","equipment.slot")
	var profile: String = args.profile
	var slot: String = args.slot
	var item: String = args.item_id
	var read := view(inv,hero)
	if not read.ok:
		return read
	var equipped: Dictionary = read.value.profiles[profile]
	var old: String = equipped[slot]
	var holder := _slot(hero.id,profile,slot)
	var bag := _bag(hero.id)
	var lines := []
	if item.is_empty():
		if old.is_empty():
			return R.fail("InvalidState","equipment.empty")
		var blocked := _remove_reason(slot,equipped)
		if not blocked.is_empty():
			return R.fail("InvalidState",blocked)
	else:
		if not read.value.items.has(item) or inv.owner_of(item).get("value") != bag:
			return R.fail("InsufficientResource","equipment.bag")
		var blocked := _reason(hero,item.get_file(),profile,slot,equipped)
		if not blocked.is_empty():
			return R.fail("InvalidState",blocked)
		lines.append(_line(item,bag,holder,"equip",source))
	if not old.is_empty():
		lines.append(_line(old,holder,bag,"equip",source))
	return R.ok(lines)


static func _inherit(inv: Inventory, hero: Dictionary, heir: Dictionary, source: String) -> Dictionary:
	if not _known_hero(heir) or hero.id == heir.id:
		return R.fail("InvalidArgument","heir")
	if hero.get("life_status") not in ["Dead","Retired"]:
		return R.fail("InvalidState","succession")
	if heir.get("life_status") in ["Captive","Dead","Retired"]:
		return R.fail("InvalidState","heir")
	var from := view(inv,hero)
	if not from.ok:
		return from
	if not inv.instance_layout().locations.has(_bag(heir.id)):
		return R.fail("NotFound","heir.bag")
	var lines := []
	# Unequip personal tack/weapon if the family mount is leaving its rider.
	for profile in from.value.profiles:
		var slots: Dictionary = from.value.profiles[profile]
		var mount: String = slots.get("mount","")
		if mount.is_empty() or from.value.items[mount].ownership != "family":
			continue
		for slot in ["main_hand","harness"]:
			var item: String = slots.get(slot,"")
			if not item.is_empty() and ITEMS[item.get_file()].get("needs_mount",false) and from.value.items[item].ownership == "personal":
				lines.append(_line(item,_slot(hero.id,profile,slot),_bag(hero.id),"inherit",source))
	for item in from.value.items:
		if from.value.items[item].ownership == "family":
			lines.append(_line(item,inv.owner_of(item).value,_bag(heir.id),"inherit",source))
	return R.ok(lines)


static func apply(inv: Variant, hero: Dictionary, op: String, args: Dictionary, txn: String) -> Dictionary:
	if not _known_hero(hero) or (inv != null and not inv is Inventory) or not C.Reader.valid_key(txn):
		return R.fail("InvalidArgument","character.gear")
	if op == "create":
		if not args.is_empty():
			return R.fail("InvalidArgument","equipment.create")
		var endowment := []
		var kit := _kit(hero)
		for kind in kit:
			endowment.append({"holder":HOLDER+hero.id+"/"+kit[kind],"instance_id":_item_id(hero.id,kind)})
		var bank: Inventory = Inventory.new() if inv == null else inv
		var previous := bank.ledger_for(txn)
		if previous.ok:
			if previous.value.size() != endowment.size():
				return R.fail("Conflict","txn_id")
			for i in endowment.size():
				var entry: Dictionary = previous.value[i]
				if entry.reason != "holder_endowment" or entry.dst != endowment[i].holder or entry.resource.id != endowment[i].instance_id:
					return R.fail("Conflict","txn_id")
			return bank.fork_with_locations()
		return bank.fork_with_locations(_holders(hero.id),endowment,txn)
	if not op in ["equip","inherit"] or inv == null:
		return R.fail("InvalidArgument","gear.operation")
	var identity: Variant = args
	if op == "inherit":
		if args.size() != 1 or not args.get("heir") is Dictionary:
			return R.fail("InvalidArgument","heir")
		identity = args.heir.get("id")
	var digest := C.hash_value([hero.id,op,identity])
	if not digest.ok:
		return digest
	var fork: Dictionary = inv.fork_with_locations()
	if not fork.ok:
		return fork
	var previous: Dictionary = inv.ledger_for(txn)
	if previous.ok:
		for entry in previous.value:
			if entry.get("reason") != op or entry.get("source_ref") != digest.value:
				return R.fail("Conflict","txn_id")
		if previous.value.is_empty(): return R.fail("Conflict","txn_id")
		return fork
	if op == "equip" and hero.get("life_status") in ["Captive","Retired","Dead"]:
		return R.fail("InvalidState","life_status")
	var lines := _equip(inv,hero,args,digest.value) if op == "equip" else _inherit(inv,hero,args.heir,digest.value)
	if not lines.ok or lines.value.is_empty():
		return fork if lines.ok else lines
	var plan: Dictionary = fork.value.prepare_exchange(txn,lines.value)
	if not plan.ok:
		return plan
	var committed: Dictionary = fork.value.commit(plan.value)
	return fork if committed.ok else committed


static func validate(inv: Variant, heroes: Dictionary) -> Dictionary:
	if inv == null:
		return R.ok() if heroes.is_empty() else R.fail("InvalidState","character.inventory")
	if not inv is Inventory:
		return R.fail("InvalidArgument","inventory")
	var layout: Dictionary = inv.instance_layout()
	var expected := {}
	var issued := {}
	for id in heroes:
		var hero: Variant = heroes[id]
		if not hero is Dictionary or not _known_hero(hero) or hero.id != id:
			return R.fail("InvalidState","character.gear_identity")
		expected.merge(_holders(hero.id))
		for kind in _kit(hero):
			issued[_item_id(hero.id,kind)] = hero.id
	for holder in layout.locations:
		if holder.begins_with(HOLDER) and expected.get(holder) != layout.locations[holder]:
			return R.fail("InvalidState","character.gear_holder")
	for holder in expected:
		if not layout.locations.has(holder):
			return R.fail("InvalidState","character.missing_holder")
	for item in issued:
		if not layout.owners.has(item):
			return R.fail("InvalidState","character.missing_item")
	for item in layout.owners:
		var holder: String = layout.owners[item]
		if not item.begins_with(ITEM) and not holder.begins_with(HOLDER):
			continue
		if not issued.has(item) or not expected.has(holder):
			return R.fail("InvalidState","character.item_origin")
		if not ITEMS[item.get_file()].get("family",false) and not holder.begins_with(HOLDER+issued[item]+"/"):
			return R.fail("InvalidState","character.personal_owner")
	for hero in heroes.values():
		var worn := _layout(layout,hero.id)
		for profile in worn.profiles:
			for slot in worn.profiles[profile]:
				var item: String = worn.profiles[profile][slot]
				if not item.is_empty() and not _reason(hero,item.get_file(),profile,slot,worn.profiles[profile]).is_empty():
					return R.fail("InvalidState","character.equipment")
	return R.ok()
