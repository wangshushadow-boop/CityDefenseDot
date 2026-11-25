extends SceneTree

const Hero=preload("res://campaign/character/hero_domain.gd")
const Canon=preload("res://contracts/canonical.gd")
const ID:="hero/7806bd7d-b55f-4a61-b049-621ede778297"
var checks:=0
var failures:=0

func check(condition: bool, label:String)->void:
	checks+=1
	if not condition:
		failures+=1
		printerr("FAIL ",label)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var defs:=Hero.catalog()
	check(not defs.is_empty(),"validated authored rules")
	if defs.is_empty():
		quit(1)
		return
	check(defs.skills.size()==18 and defs.attributes.size()==6,"six attributes and eighteen original skills")
	for kind in defs.options:
		for key in defs.options[kind]:
			var choices:Dictionary=defs.defaults.duplicate()
			choices[kind]=key
			var c:=Hero.create(ID,choices,0)
			check(c.ok and Hero.validate(c.value).ok and c.value[kind]==key,"creation option "+str(key))
	check(not Hero.create("party/7806bd7d-b55f-4a61-b049-621ede778297",{},0).ok,"typed hero identity")
	check(not Hero.create(ID,{"age":12},0).ok and not Hero.create(ID,{"age":22.0},0).ok,"age and type")
	check(not Hero.create(ID,{"culture":"unknown"},0).ok and not Hero.create(ID,{"hp":30},0).ok,"unknown background or field")
	check(not Hero.create(ID,{"name":"\n"},0).ok and not Hero.create(ID,{},-1).ok,"valid name and day")
	var made:=Hero.create(ID,defs.defaults,2)
	check(made.ok,"default hero")
	if not made.ok:
		quit(1)
		return
	var h:Dictionary=made.value
	var before:=Canon.hash_value(h)
	var invested:=Hero.apply(h,"focus",{"skill":"one_handed"},2)
	check(invested.ok and invested.value.focus_points==0 and h.skills.one_handed.focus==0,"allocate focus on candidate only")
	check(not Hero.apply(invested.value,"focus",{"skill":"bow"},2).ok,"no unearned point")
	var drill:={"skill":"one_handed","source":"command/sparring/1"}
	var practiced:=Hero.apply(invested.value,"practice",drill,2)
	check(practiced.ok and practiced.value.skills.one_handed.level==3,"actual practice crosses first threshold")
	var unfocused:=Hero.apply(h,"practice",drill,2)
	check(practiced.value.skills.one_handed.xp>unfocused.value.skills.one_handed.xp,"focus affects learning")
	check(Canon.hash_value(h).value==before.value and not h.sources.has(drill.source),"unchanged input")
	var again:=Hero.apply(practiced.value,"practice",drill,3)
	check(again.ok and again.value==practiced.value,"same source idempotent beyond day")
	var conflict:=Hero.apply(practiced.value,"practice",{"skill":"bow","source":drill.source},2)
	check(not conflict.ok and conflict.error.code=="Conflict","reused source conflict")
	check(not Hero.apply(h,"practice",{"skill":"bow","source":"e","amount":999},2).ok,"practice cannot select XP")
	var selected:=Hero.apply(practiced.value,"perk",{"perk":"one_handed_hand"},2)
	check(selected.ok and Hero.validate(selected.value).ok,"prerequisite and point accepted")
	var fork:=Hero.apply(selected.value,"perk",{"perk":"one_handed_lead"},2)
	check(not fork.ok,"exclusive branch")
	var projection:=Hero.view(selected.value)
	check(projection.can_join and projection.effects.self.one_handed=={"bonus":2,"sources":["one_handed_hand"]},"effect scope and provenance")
	check(not projection.effects.has("captain") and not projection.has("sources"),"projection boundary")
	projection.skills.one_handed.level=300
	check(selected.value.skills.one_handed.level==3,"independent projection")
	var held:Dictionary=selected.value
	for n in range(2,7):
		var result:=Hero.apply(held,"practice",{"skill":"one_handed","source":"practice/%d"%n},2)
		check(result.ok,"repeat practice")
		if n>4:check(result.value.skills==held.skills,"no endless risk-free gain")
		held=result.value
	var xp:=Hero.apply(held,"outcome",{"kind":"skill","skill":"polearm","source":"battle/1","amount":1000},3)
	check(xp.ok and xp.value.level>held.level and xp.value.focus_points>held.focus_points and Hero.validate(xp.value).ok,"trusted action and permanent rank")
	var wound:={"kind":"wound","severity":40,"source":"battle/2"}
	var wounded:=Hero.apply(xp.value,"outcome",wound,4)
	check(wounded.ok and wounded.value.life_status=="Wounded" and not Hero.view(wounded.value).can_join,"wound prevents enlistment")
	var captured:=Hero.apply(wounded.value,"outcome",{"kind":"capture","source":"battle/3","location":"party/01234567-89ab-4cde-8123-456789abcdef"},4)
	check(captured.ok and captured.value.wounds==40 and captured.value.life_status=="Captive","wounds orthogonal to custody")
	check(not Hero.apply(captured.value,"outcome",{"kind":"join","source":"x","location":"party/12345678-89ab-4cde-8123-456789abcdef"},4).ok,"captive cannot join")
	check(not Hero.apply(captured.value,"retire",{},4).ok,"no voluntary retirement in captivity")
	var rested:=Hero.apply(captured.value,"rest",{},5)
	check(rested.ok and rested.value.wounds<40 and rested.value.wounds>0 and rested.value.captive,"medic recovery while captive")
	var repeat:=Hero.apply(rested.value,"rest",{},5)
	check(repeat.ok and repeat.value==rested.value,"once per day")
	check(not Hero.apply(rested.value,"rest",{},4).ok,"no time travel")
	var well:=Hero.apply(rested.value,"rest",{},20)
	check(well.ok and well.value.wounds==0 and well.value.life_status=="Captive" and well.value.location_ref=="party/01234567-89ab-4cde-8123-456789abcdef","recovered prisoner still present")
	var released:=Hero.apply(well.value,"outcome",{"kind":"release","source":"prison/1"},20)
	check(released.ok and released.value.location_ref==Hero.HOME and Hero.view(released.value).can_join,"one location after release")
	var invalid_location:=Hero.apply(released.value,"outcome",{"kind":"join","source":"join/1","location":"party/not-a-uuid"},20)
	check(not invalid_location.ok,"typed party location")
	var party_id:="party/01234567-89ab-4cde-8123-456789abcdef"
	var joined:=Hero.apply(released.value,"outcome",{"kind":"join","source":"join/1","location":party_id},20)
	check(joined.ok and joined.value.location_ref==party_id,"join exactly one party")
	check(not Hero.apply(joined.value,"outcome",{"kind":"join","source":"join/2","location":party_id},20).ok,"already enlisted")
	var left:=Hero.apply(joined.value,"outcome",{"kind":"leave","source":"leave/1","location":Hero.HOME},20)
	check(left.ok and left.value.location_ref==Hero.HOME,"left active party")
	var retired:=Hero.apply(released.value,"retire",{},20)
	check(retired.ok and Hero.validate(retired.value).ok and retired.value.life_status=="Retired" and not Hero.apply(retired.value,"rest",{},21).ok,"retirement terminal")
	var loss:={"kind":"death","source":"battle/4"}
	var dead:=Hero.apply(captured.value,"outcome",loss,5)
	check(dead.ok and dead.value.life_status=="Dead" and not dead.value.captive,"dead prisoner leaves captivity")
	check(Hero.apply(dead.value,"outcome",loss,20).ok and Hero.apply(dead.value,"outcome",wound,20).ok,"terminal accepts earlier committed replay")
	check(not Hero.apply(dead.value,"outcome",{"kind":"release","source":"other"},5).ok,"no resurrection")
	var state:=Canon.decode(Canon.encode(dead.value).value)
	check(state.ok and Hero.validate(state.value).ok,"canonical reload")
	var tamper:Dictionary=h.duplicate(true)
	tamper.focus_points+=1
	check(not Hero.validate(tamper).ok,"forged focus points")
	tamper=h.duplicate(true)
	tamper.skills.bow.level=3
	check(not Hero.validate(tamper).ok,"forged skill")
	tamper=h.duplicate(true)
	tamper.life_status="Captive"
	check(not Hero.validate(tamper).ok,"contradictory custody")
	tamper=h.duplicate(true)
	tamper.location_ref="character:place/archive"
	check(not Hero.validate(tamper).ok,"archive belongs only to terminal heroes")
	var low:Dictionary=held
	for n in 22:
		var grant:=Hero.apply(low,"outcome",{"kind":"skill","skill":"one_handed","source":"threshold/%d"%n,"amount":1000},3)
		check(grant.ok,"soft limit remains permeable")
		low=grant.value
	check(low.skills.one_handed.level>Hero.view(low).skills.one_handed.soft_cap,"soft cap without hard blocking")
	var fresh_day:=Hero.apply(held,"practice",{"skill":"one_handed","source":"new-day"},4)
	check(fresh_day.ok and fresh_day.value.skills.one_handed!=held.skills.one_handed,"new day restores training yield")
	var saw_wound:=false
	var saw_death:=false
	for n in 50:
		var injury:={"kind":"casualty","source":"wounded/%d"%n,"severity":75}
		var first:=Hero.apply(h,"outcome",injury,2)
		var second:=Hero.apply(h,"outcome",injury,2)
		check(first.ok and first==second,"reproducible severity outcome")
		saw_wound=saw_wound or first.value.life_status=="Wounded"
		saw_death=saw_death or first.value.life_status=="Dead"
		if saw_death and saw_wound:break
	check(saw_wound and saw_death,"configured decision produces fatal and nonfatal outcomes")
	print("P3_HERO checks=",checks," failures=",failures)
	quit(1 if failures else 0)
