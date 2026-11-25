extends SceneTree
const Characters = preload("res://campaign/character/ports/characters.gd")
const Inventory = preload("res://shared/inventory/inventory.gd")
const C = preload("res://contracts/canonical.gd")
const WORLD := "world/p3-character-flow"
const PARTY := "party/01234567-89ab-4cde-8123-456789abcdef"
var state := {"repo":{},"inventory":null,"minute":0}
var checks := 0
var failures := 0

func check(condition: bool, detail: String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		printerr("FAIL ",detail)
	return condition

func action(op: String, args: Dictionary, txn: String, accept := true) -> bool:
	var before: String = C.hash_value(state.repo).value
	var inv: Variant = state.inventory
	var old: Variant = inv.snapshot() if inv!=null else null
	var result := Characters.plan(state.repo,inv,op,args,WORLD,state.minute,txn)
	check(before==C.hash_value(state.repo).value and (inv==null or inv.snapshot()==old),"candidate does not publish "+op)
	if not check(result.ok==accept,op+" "+str(result.get("error",{}))):
		return false
	if result.ok:
		state=result.value
	return true

func model() -> Dictionary:
	return Characters.view(state.repo,state.inventory,WORLD,state.minute).value

func execute() -> void:
	var initial := model()
	check(initial.hero==null and not initial.ended,"empty legacy world can create")
	if not action("create",{"name":"时雨","occupation":"caravan"},"create/1"):
		return
	var legacy:=Inventory.new()
	check(legacy.initialize({"@chr.holder/old_mod":{"kind":"inventory","capacity":10}},[]).ok and Characters.validate({},legacy,WORLD,0).ok,"old P1 custom holder name is not a CHR endowment")
	var m:=model()
	var founder: String=m.player_id
	var heir: String=m.heirs[0].id
	check(m.hero.id!=heir and m.family.size()==2 and m.hero.name=="时雨","separate founder, player control and adult family member")
	check(m.practice.size()==18 and not m.practice.trade.has("answer"),"practice exposes options, no answer key")
	check(Characters.validate(state.repo,state.inventory,WORLD,state.minute).ok,"validate new world")
	check(not Characters.validate({},state.inventory,WORLD,state.minute).ok,"orphan gear cannot masquerade as an empty legacy world")
	var future: Dictionary = state.repo.duplicate(true)
	future.heroes[founder].recovery_day = 10
	check(not Characters.validate(future,state.inventory,WORLD,state.minute).ok,"future recovery clock rejected")
	action("create",{},"create/2",false)
	var wrong_world:=Characters.validate(state.repo,state.inventory,"world/else",state.minute)
	check(not wrong_world.ok,"foreign world rejected")
	var damaged:Dictionary=state.repo.duplicate(true)
	damaged.household.members[1]=founder
	check(not Characters.validate(damaged,state.inventory,WORLD,state.minute).ok,"duplicate household membership rejected")
	damaged=state.repo.duplicate(true)
	damaged.schema_version=2
	check(not Characters.validate(damaged,state.inventory,WORLD,state.minute).ok,"future repository rejected")
	var problem: Dictionary=m.practice.trade
	var nums:=RegEx.new()
	nums.compile("[0-9]+")
	var parts:=nums.search_all(problem.prompt)
	var total:int=int(parts[0].get_string())*int(parts[1].get_string())-int(parts[2].get_string())
	var answer:int=problem.options.find(str(total))
	check(answer>=0,"solve trade exercise using visible numbers")
	if not action("practice",{"skill":"trade","answer":answer},"attempt/first"):
		return
	check(model().last_practice.correct and state.minute==15 and model().hero.skills.trade!=m.hero.skills.trade,"successful action consumes time and records unique earned event")
	action("practice",{"skill":"trade","answer":1,"amount":999},"invalid",false)
	var bow: Dictionary=model().practice.bow
	check(bow.kind=="aim" and bow.radius>0,"bow exercise exposes target geometry")
	action("practice",{"skill":"bow","aim":[0,0]},"shot/miss")
	check(not model().last_practice.correct and state.minute==30,"miss costs time and gives no skill XP")
	bow=model().practice.bow
	var before_shot: Dictionary=model().hero.skills.bow
	action("practice",{"skill":"bow","aim":bow.target},"shot/hit")
	check(model().last_practice.correct and model().hero.skills.bow!=before_shot and state.minute==45,"direct aim earns skill XP only on actual impact")
	action("practice",{"skill":"bow","aim":[-1,500]},"shot/invalid",false)
	var wound:={"hero_id":founder,"source":"battle/result-a","kind":"wound","severity":20}
	action("outcome",wound,"outcome-a")
	var health:int=state.repo.heroes[founder].wounds
	action("outcome",wound,"outcome-b")
	check(state.repo.heroes[founder].wounds==health and not Characters.can_deploy(state.repo,founder).ok,"same fact once, wounded unavailable")
	action("outcome",{"hero_id":founder,"source":"battle/result-a","kind":"death"},"outcome-c",false)
	action("outcome",{"hero_id":heir,"source":"battle/capture","kind":"capture","location":PARTY},"capture")
	check(model().heirs.is_empty(),"captive heir excluded")
	action("retire",{"heir_id":heir},"retire-early",false)
	action("outcome",{"hero_id":heir,"source":"release/one","kind":"release","location":"character:place/home"},"release")
	var day := Characters.recover(state.repo,WORLD,1)
	if not check(day.ok,"recover one day"):return
	check(day.value.heroes[founder].wounds<health and state.repo.heroes[founder].wounds==health,"recovery staged independently")
	state.repo=day.value
	state.minute=1440
	check(Characters.recover(state.repo,WORLD,1).value==state.repo,"same day replay")
	var old_items: Dictionary = model().gear.items
	if not action("retire",{"heir_id":heir},"retire-1"):
		return
	m=model()
	check(m.player_id==heir and state.repo.heroes[founder].life_status=="Retired","controller bound to successor")
	for item in old_items:
		check(m.gear.items.has(item)==(old_items[item].ownership=="family"),"retired ownership "+item)
	check(not Characters.can_deploy(state.repo,founder).ok and Characters.can_deploy(state.repo,heir).ok,"terminal founder cannot enter another battle")
	var cold:=Inventory.new()
	check(cold.restore(state.inventory.snapshot()).ok and Characters.validate(state.repo,cold,WORLD,1440).ok,"cold equipment and character state validate")
	action("outcome",{"hero_id":heir,"source":"battle/death","kind":"death"},"death")
	check(not Characters.can_deploy(state.repo,heir).ok and model().heirs.is_empty(),"dead heir cannot deploy")
	action("outcome",{"hero_id":heir,"source":"battle/join","kind":"join","location":PARTY},"resurrect",false)
	action("retire",{"heir_id":""},"end-house")
	check(model().ended and model().player_id==null and model().hero==null,"end without a successor")
	check(Characters.validate(state.repo,state.inventory,WORLD,state.minute).ok,"closed household restores")

func _initialize() -> void:
	execute()
	print("CHARACTER_FLOW checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 and checks>=40 else 1)
