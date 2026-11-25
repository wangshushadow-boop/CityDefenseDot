extends RefCounted
## The household owns membership and the leader. CHR supplies the life facts.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")

static func found(clan_id: String, founder: String, kinsman: String, banner: String) -> Dictionary:
	return {"id":clan_id,"members":[founder,kinsman],"leader":founder,"banner":banner}

static func successors(house: Dictionary, heroes: Dictionary, day: int) -> Array:
	var choices := []
	for member in house.members:
		if member == house.leader:
			continue
		var hero: Dictionary = heroes[member]
		@warning_ignore("integer_division")
		var age: int = hero.age + (day - hero.created_day) / 365
		if age >= 18 and hero.life_status in ["Healthy","Wounded"]:
			choices.append({"id":member,"name":hero.name,"age":age})
	return choices

static func select(house: Dictionary, heroes: Dictionary, heir_id: String, day: int) -> Dictionary:
	if house.leader == null:
		return R.fail("InvalidState","household.leader")
	if not heir_id.is_empty():
		var eligible := false
		for entry in successors(house,heroes,day):
			if entry.id == heir_id:
				eligible = true
				break
		if not eligible:
			return R.fail("InvalidArgument","household.heir")
	var result := house.duplicate(true)
	result.leader = null if heir_id.is_empty() else heir_id
	return R.ok(result)

static func validate(house: Variant, heroes: Dictionary) -> Dictionary:
	if not house is Dictionary or house.size()!=4 or not house.has_all(["id","leader","members","banner"]):
		return R.fail("InvalidArgument","household")
	if not V.typed_id(house.id,"clan") or not house.banner is String or not house.members is Array or house.members.size()!=heroes.size():
		return R.fail("InvalidArgument","household.members")
	var seen := {}
	for member in house.members:
		if not V.typed_id(member,"hero") or not heroes.has(member) or seen.has(member):
			return R.fail("InvalidArgument","household.member")
		seen[member] = true
	if house.leader != null and (not house.leader is String or not seen.has(house.leader) or heroes[house.leader].life_status == "Retired"):
		return R.fail("InvalidState","household.leader")
	return R.ok()
