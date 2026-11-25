extends SceneTree

const Characters = preload("res://campaign/character/ports/characters.gd")
const Hero = preload("res://campaign/character/hero_domain.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
	return ok

func exercise() -> void:
	check(Characters.governor_facts({},0).members.is_empty(), "no household before creation")
	var creation := Characters.plan({},null,"create",{"culture":"river"},"world/governor",0,"birth")
	if not check(creation.ok, "create actual household"): return
	var repo: Dictionary = creation.value.repo
	var facts := Characters.governor_facts(repo,0)
	var cousin: String = repo.household.members[1]
	check(facts.can_manage and facts.members.size()==2 and not facts.members[0].eligible, "leader manages but cannot serve")
	check(facts.members[1].eligible and facts.members[1].stewardship==2, "river household member contributes actual skill")
	var trained := Hero.apply(repo.heroes[cousin],"outcome",{"kind":"skill","skill":"leadership","amount":1000,"source":"service/day-1"},0)
	if not check(trained.ok, "genuine leadership award"): return
	var level: int = trained.value.skills.leadership.level
	var personal := Hero.apply(trained.value,"perk",{"perk":"leadership_hand"},0)
	var settlement := Hero.apply(trained.value,"perk",{"perk":"leadership_lead"},0)
	if not check(personal.ok and settlement.ok, "two alternative legitimate perks"): return
	repo.heroes[cousin] = personal.value
	check(Characters.governor_facts(repo,0).members[1].leadership==level, "personal talent excluded from office")
	repo.heroes[cousin] = settlement.value
	check(Characters.governor_facts(repo,0).members[1].leadership==level+3, "settlement talent applied to office")
	var wound := Hero.apply(settlement.value,"outcome",{"kind":"wound","severity":1,"source":"service/wound"},0)
	if not check(wound.ok, "wound recorded"): return
	repo.heroes[cousin] = wound.value
	check(Characters.governor_facts(repo,0).members[1].eligible, "wounded free family member can serve")
	var capture := Hero.apply(wound.value,"outcome",{"kind":"capture","location":"party/11111111-1111-4111-8111-111111111111","source":"service/capture"},0)
	if not check(capture.ok, "captivity recorded"): return
	repo.heroes[cousin] = capture.value
	check(not Characters.governor_facts(repo,0).members[1].eligible, "captive cannot serve")
	repo.household.leader = null
	facts = Characters.governor_facts(repo,0)
	check(not facts.can_manage and not facts.members[0].eligible and not facts.members[1].eligible, "ended career has no appointment authority")

func _initialize() -> void:
	exercise()
	print("GOVERNOR_FACTS checks=%d failures=%d" % [checks,failures])
	quit(int(failures!=0))
