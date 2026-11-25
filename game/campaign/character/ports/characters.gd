extends RefCounted
## Character commands plan changes on a candidate. Campaign publishes it with the save receipt.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const Hero = preload("res://campaign/character/hero_domain.gd")
const Gear = preload("res://campaign/character/gear.gd")
const House = preload("res://campaign/clan/ports/character_household.gd")
const DAY := 1440
const PRACTICE_MINUTES := 15
const DIRECTIONS := ["左","右","上","下"]
const AIM_SKILLS := ["bow","crossbow","throwing"]
const FORMS := ["one_handed","two_handed","polearm","bow","crossbow","throwing","riding","athletics"]

static func empty() -> Dictionary:
	return {}

static func _day(minute: int) -> int:
	@warning_ignore("integer_division")
	return minute / DAY

static func _id(world: String, role: String, kind: String) -> String:
	var bits := (world + "/" + role).sha256_text()
	return "%s/%s-%s-4%s-%s%s-%s" % [kind,bits.left(8),bits.substr(8,4),bits.substr(13,3),
		"89ab"[bits.substr(16,1).hex_to_int() % 4],bits.substr(17,3),bits.substr(20,12)]

static func _created(inv: Variant, choices: Dictionary, world: String, day: int, txn: String) -> Dictionary:
	var player := Hero.create(_id(world,"founder","hero"),choices,day)
	if not player.ok:
		return player
	var other_choices := choices.duplicate(true)
	other_choices.name = "阿衡" if player.value.name != "阿衡" else "阿芷"
	other_choices.age = 24
	var cousin := Hero.create(_id(world,"cousin","hero"),other_choices,day)
	if not cousin.ok:
		return cousin
	var player_gear := Gear.apply(inv,player.value,"create",{},txn+"/founder")
	if not player_gear.ok:
		return player_gear
	var cousin_gear := Gear.apply(player_gear.value,cousin.value,"create",{},txn+"/cousin")
	if not cousin_gear.ok:
		return cousin_gear
	var household := House.found(_id(world,"household","clan"),player.value.id,cousin.value.id,player.value.banner)
	var repo := {"schema_version":1,"world_id":world,"heroes":{player.value.id:player.value,cousin.value.id:cousin.value},
		"household":household,"attempts":0,"last_practice":{}}
	return R.ok({"repo":repo,"inventory":cousin_gear.value})

static func _exercise(id: String, skill: String, attempt: int) -> Dictionary:
	# Vary the task per actor, skill and committed attempt. The client receives only its prompt and possible answers.
	var seed_text := ("%s/%s/%d" % [id,skill,attempt]).sha256_text()
	var seed_number := seed_text.left(7).hex_to_int()
	if skill in AIM_SKILLS:
		var target := [125 + seed_number % 750, 125 + seed_text.substr(8,5).hex_to_int() % 750]
		return {"kind":"aim","prompt":"在靶场中瞄准靶心，命中即可获得对应技能经验。","target":target,"radius":75,"options":[]}
	var answer := seed_number % 3
	var options := []
	var prompt: String
	if skill in FORMS:
		var step := 1 + (seed_number >> 6) % 3
		var start := (seed_number >> 4) % 4
		var next := (start+3*step)%4
		prompt = "演武场旗令按固定步幅轮换：%s · %s · %s。下一面旗是？" % [
			DIRECTIONS[start],DIRECTIONS[(start+step)%4],DIRECTIONS[(start+step*2)%4]]
		for i in 3:
			options.append(DIRECTIONS[(next+posmod(i-answer,3))%4])
	else:
		var groups := 2 + (seed_number >> 4) % 7
		var count := 3 + (seed_number >> 8) % 8
		var spent := 1 + (seed_number >> 13) % 5
		var unit: String = {"medicine":"药材","smithing":"铁料","engineering":"木料","trade":"货物",
			"scouting":"路标","leadership":"号旗","charm":"礼帖","roguery":"线索","tactics":"筹码","stewardship":"粮袋"}[skill]
		var expected := groups*count-spent
		prompt = "%d 组%s，每组 %d 份，已用 %d 份。还余多少？" % [groups,unit,count,spent]
		for i in 3:
			options.append(str(expected+i-answer))
	return {"prompt":prompt,"options":options,"answer":answer}

static func _practice(repo: Dictionary, hero: Dictionary, args: Dictionary, day: int, txn: String) -> Dictionary:
	if args.size()!=2 or not args.get("skill") is String or not Hero.catalog().skills.has(args.skill):
		return R.fail("InvalidArgument","character.practice")
	if hero.life_status != "Healthy" or repo.attempts >= V.MAX_INTEGER:
		return R.fail("InvalidState","character.practice")
	var drill := _exercise(hero.id,args.skill,repo.attempts)
	var correct: bool
	if drill.get("kind")=="aim":
		var position: Variant = args.get("aim")
		if not position is Array or position.size()!=2 or not V.integer(position[0],0,1000) or not V.integer(position[1],0,1000):
			return R.fail("InvalidArgument","character.aim")
		var dx: int = position[0]-drill.target[0]
		var dy: int = position[1]-drill.target[1]
		correct = dx*dx+dy*dy <= drill.radius*drill.radius
	else:
		if not V.integer(args.get("answer"),0,2):
			return R.fail("InvalidArgument","character.answer")
		correct = args.answer == drill.answer
	if correct:
		var earned := Hero.apply(hero,"practice",{"skill":args.skill,"source":txn},day)
		if not earned.ok:
			return earned
		repo.heroes[hero.id] = earned.value
	repo.attempts += 1
	repo.last_practice = {"skill":args.skill,"correct":correct}
	return R.ok()

static func _retire(repo: Dictionary, inv: Variant, hero: Dictionary, args: Dictionary, day: int, txn: String) -> Dictionary:
	if args.size()!=1 or not args.get("heir_id") is String:
		return R.fail("InvalidArgument","character.heir")
	var selected := House.select(repo.household,repo.heroes,args.heir_id,day)
	if not selected.ok:
		return selected
	if hero.life_status != "Dead":
		var retired := Hero.apply(hero,"retire",{},day)
		if not retired.ok:
			return retired
		repo.heroes[hero.id] = retired.value
	if selected.value.leader != null:
		var transfer := Gear.apply(inv,repo.heroes[hero.id],"inherit",{"heir":repo.heroes[selected.value.leader]},txn)
		if not transfer.ok:
			return transfer
		inv = transfer.value
	repo.household = selected.value
	repo.last_practice = {}
	return R.ok(inv)

static func plan(current: Dictionary, inv: Variant, op: String, args: Dictionary, world: String, minute: int, txn: String) -> Dictionary:
	var day := _day(minute)
	if op=="create":
		if not current.is_empty():
			return R.fail("Conflict","character.exists")
		var birth := _created(inv,args,world,day,txn)
		if birth.ok:
			birth.value["minute"] = minute
		return birth
	if current.is_empty() or current.world_id!=world:
		return R.fail("NotFound","character")
	var repo := current.duplicate(true)
	var id: Variant = repo.household.leader
	var payload := args.duplicate(true)
	if op=="outcome":
		id = payload.get("hero_id")
		payload.erase("hero_id")
	if not id is String or not repo.heroes.has(id):
		return R.fail("NotFound","character.hero")
	var hero: Dictionary = repo.heroes[id]
	var applied: Dictionary
	match op:
		"practice":
			if minute > V.MAX_INTEGER-PRACTICE_MINUTES:
				return R.fail("InvalidState","game_minute")
			applied = _practice(repo,hero,payload,day,txn)
			minute += PRACTICE_MINUTES
		"equip":
			if hero.life_status not in ["Healthy","Wounded"]:
				return R.fail("InvalidState","character.equip")
			applied = Gear.apply(inv,hero,"equip",payload,txn)
			if applied.ok:
				inv = applied.value
		"retire":
			applied = _retire(repo,inv,hero,payload,day,txn)
			if applied.ok:
				inv = applied.value
		"rest":
			if not args.is_empty() or hero.life_status in ["Dead","Retired"] or minute > V.MAX_INTEGER-DAY:
				return R.fail("InvalidState","character.rest")
			minute += DAY
			applied = R.ok()
		"perk","focus","outcome":
			applied = Hero.apply(hero,op,payload,day)
			if applied.ok:
				repo.heroes[id] = applied.value
		_:
			return R.fail("InvalidArgument","character.operation")
	if not applied.ok:
		return applied
	var result := {"repo":repo,"inventory":inv,"minute":minute}
	if op=="rest":
		result["resting_id"] = id
	return R.ok(result)

static func recover(current: Dictionary, world: String, day: int, resting_id: String = "") -> Dictionary:
	if current.is_empty():
		return R.ok({})
	if current.world_id!=world:
		return R.fail("InvalidState","character.world")
	var repo := current.duplicate(true)
	for id in repo.heroes:
		var hero: Dictionary = repo.heroes[id]
		if hero.life_status in ["Dead","Retired"]:
			continue
		var recovery := Hero.apply(hero,"rest",{"resting":true} if id==resting_id else {},day)
		if not recovery.ok:
			return recovery
		repo.heroes[id] = recovery.value
	return R.ok(repo)

## The character use case owns equipment slots. Other campaign writers keep their normal INV authority.
static func permit_exchange(_repo: Dictionary, inv: Variant, lines: Array) -> Dictionary:
	var reservations: Variant = null
	for entry in lines:
		if not entry is Dictionary:
			continue  # INV validates the complete exchange shape.
		var line: Dictionary = entry
		if line.get("op")=="release" and inv!=null and line.get("reservation_id") is String:
			if reservations==null:
				reservations = inv.snapshot().state.reservations
			line = reservations.get(line.reservation_id,line)
		for key in ["src","dst","holder"]:
			if line.get(key) is String and Gear.holder_name(line[key]):
				return R.fail("Unauthorized","character.equipment_holder")
		var resource: Variant = line.get("resource")
		if resource is Dictionary and resource.get("kind")=="instance" and resource.get("id") is String and Gear.item_name(resource.id):
			return R.fail("Unauthorized","character.equipment_instance")
	return R.ok()

static func can_deploy(repo: Dictionary, hero_id: String) -> Dictionary:
	if repo.is_empty() or not repo.heroes.has(hero_id):
		return R.fail("NotFound","character.hero")
	if repo.heroes[hero_id].life_status!="Healthy":
		return R.fail("InvalidState","character.deployment")
	return R.ok()

static func validate(repo: Dictionary, inv: Variant, world: String, minute: int) -> Dictionary:
	if repo.is_empty():
		return Gear.validate(inv,{})
	if not V.integer(repo.get("schema_version"),1,1):
		return R.fail("StaleVersion","characters.schema_version")
	if repo.size()!=6 or repo.get("world_id")!=world or not repo.get("heroes") is Dictionary or repo.heroes.is_empty() or not repo.get("last_practice") is Dictionary or not V.integer(repo.get("attempts")):
		return R.fail("InvalidArgument","characters")
	for id in repo.heroes:
		var hero: Variant = repo.heroes[id]
		if not hero is Dictionary or hero.get("id")!=id or not V.integer(hero.get("created_day"),0,_day(minute)):
			return R.fail("InvalidArgument","characters.identity")
		var valid := Hero.validate(hero)
		if not valid.ok:
			return valid
		if hero.recovery_day > _day(minute) or hero.practice_day > _day(minute):
			return R.fail("InvalidArgument","characters.day")
	var household := House.validate(repo.get("household"),repo.heroes)
	if not household.ok:
		return household
	if repo.household.id!=_id(world,"household","clan") or not Hero.catalog().options.banner.has(repo.household.banner):
		return R.fail("InvalidArgument","characters.household")
	var last: Dictionary = repo.last_practice
	if not last.is_empty() and (last.size()!=2 or not last.get("correct") is bool or not Hero.catalog().skills.has(last.get("skill")) or repo.attempts==0):
		return R.fail("InvalidArgument","characters.last_practice")
	return Gear.validate(inv,repo.heroes)

static func view(repo: Dictionary, inv: Variant, world: String, minute: int) -> Dictionary:
	var day := _day(minute)
	var catalog := Hero.catalog()
	if catalog.is_empty():
		return R.fail("Unavailable","character.rules")
	var result := {"world_id":world,"day":day,"catalog":catalog,"player_id":null,"ended":false,"hero":null,
		"practice":{},"last_practice":{},"gear":{},"heirs":[],"family":[]}
	if repo.is_empty():
		return R.ok(result)
	result.player_id = repo.household.leader
	result.heirs = House.successors(repo.household,repo.heroes,day)
	for id in repo.household.members:
		var member: Dictionary = repo.heroes[id]
		result.family.append({"id":id,"name":member.name,"life_status":member.life_status})
	if result.player_id==null:
		result.ended = true
		result.heirs = []
		return R.ok(result)
	var hero: Dictionary = repo.heroes[result.player_id]
	result.hero = Hero.view(hero)
	@warning_ignore("integer_division")
	result.hero.age = hero.age + (day-hero.created_day) / 365
	result.last_practice = repo.last_practice.duplicate()
	var loadout := Gear.view(inv,hero)
	if not loadout.ok:
		return loadout
	result.gear = loadout.value
	for skill in catalog.skills:
		var drill := _exercise(hero.id,skill,repo.attempts)
		drill.erase("answer")
		result.practice[skill] = drill
	return R.ok(result)
