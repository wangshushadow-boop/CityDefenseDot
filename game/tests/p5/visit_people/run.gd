extends SceneTree

const People = preload("res://campaign/character/ports/characters.gd")
const Hero = preload("res://campaign/character/hero_domain.gd")
const Canon = preload("res://contracts/canonical.gd")
const WORLD := "world/estate-characters"
const SOURCE := "quest/liuxi/ledger-example"
var checks := 0
var failures := 0

func check(passed: bool, description: String) -> bool:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ",description)
	return passed

func exercise() -> void:
	check(People.visit_people({})=={"player_id":null,"can_visit":false,"members":{}}, "no invented guest or NPC")
	var built := People.plan({},null,"create",{"appearance":"plum"},WORLD,0,"birth")
	if not check(built.ok,"create household"): return
	var repo: Dictionary = built.value.repo
	var actor: String = repo.household.leader
	var people := People.visit_people(repo)
	check(people.player_id==actor and people.can_visit and people.members.size()==2,"household visit authority")
	check(people.members[repo.household.members[1]].appearance=="plum","visitor sees existing person's appearance")
	people.members[actor].name="changed"
	check(repo.heroes[actor].name!="changed","read model does not alias the domain")
	var ordinary := Hero.apply(repo.heroes[actor],"outcome",{"kind":"skill","source":SOURCE,"skill":"charm","amount":1},0)
	if not check(ordinary.ok,"legacy authority could use any source string"): return
	repo.heroes[actor]=ordinary.value
	check(People.validate_commission_reward(repo,null,"",false).ok,"legacy event keeps independent meaning")
	var measured := Hero.apply(ordinary.value,"outcome",{"kind":"skill","source":"test/units","skill":"stewardship","amount":60},0)
	var earned := People.commission_reward(repo,actor,SOURCE,0)
	if not check(earned.ok and measured.ok,"pay earned service"): return
	check(Canon.encode(earned.value).ok,"paid character state can be encoded into a physical save")
	check(earned.value.heroes[actor].skills==measured.value.skills and earned.value.heroes[actor].skills!=repo.heroes[actor].skills, "pay exactly 60 use-XP through existing growth rules")
	check(earned.value.heroes[actor].sources==ordinary.value.sources, "legacy source pages preserved")
	check(not repo.has("estate_reward") and People.commission_reward(earned.value,actor,SOURCE,0).value==earned.value, "immutable proposal and single receipt")
	check(People.validate_commission_reward(earned.value,actor,SOURCE,true).ok and not People.validate_commission_reward(earned.value,actor,SOURCE,false).ok,"cross-domain claim flag")
	check(not People.validate_commission_reward(repo,actor,SOURCE,true).ok and not People.commission_reward(repo,repo.household.members[1],SOURCE,0).ok,"missing receipt and wrong claimant")
	var journey := Hero.apply(repo.heroes[actor],"outcome",{"kind":"join","source":"travel","location":"party/12121212-1212-4212-8212-121212121212"},0)
	if not check(journey.ok,"actual travel"): return
	repo.heroes[actor]=journey.value
	check(not People.visit_people(repo).can_visit and not People.commission_reward(repo,actor,SOURCE,0).ok,"away actor cannot visit or claim")
	var damaged: Dictionary=earned.value.duplicate(true)
	damaged.estate_reward = {"actor_id":"not-a-hero","source":SOURCE}
	check(not People.validate(damaged,built.value.inventory,WORLD,0).ok,"invalid receipt identity cannot cold-load")

func _initialize() -> void:
	exercise()
	print("VISIT_PEOPLE checks=%d failures=%d" % [checks,failures])
	quit(int(failures!=0))
