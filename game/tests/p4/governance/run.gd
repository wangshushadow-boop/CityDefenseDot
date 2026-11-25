extends SceneTree
const Gov = preload("res://campaign/settlement/ports/governance.gd")
const V = preload("res://contracts/values.gd")
const C = preload("res://contracts/canonical.gd")
const WORLD := "world/governance-test"
const CLAN := "clan/00000000-0000-4000-8000-000000000001"
const LEADER := "hero/00000000-0000-4000-8000-000000000001"
const COUSIN := "hero/00000000-0000-4000-8000-000000000002"
const SECOND := "hero/00000000-0000-4000-8000-000000000003"
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func changed(source: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy := source.duplicate(true)
	copy[key] = value
	return copy

func run() -> void:
	var no_house := {"clan_id":null, "can_manage":false, "members":[]}
	var facts := {"clan_id":CLAN, "can_manage":true, "members":[
		{"id":LEADER,"name":"家主","eligible":false,"reason":"家主","stewardship":9,"leadership":1},
		{"id":COUSIN,"name":"堂妹","eligible":true,"reason":"","stewardship":4,"leadership":8},
		{"id":SECOND,"name":"堂兄","eligible":true,"reason":"","stewardship":12,"leadership":0}]}
	check(Gov.daily({}, 27, no_house).value.is_empty(), "no estate, no backdated settlement")
	check(not Gov.plan({}, "governor_open", {}, WORLD, 27, no_house).ok, "no household cannot take estate")
	check(not Gov.plan({}, "governor_open", {"grant":true}, WORLD, 27, facts).ok, "strict open args")
	check(not Gov.view({}, WORLD, 27, no_house).established and Gov.view({}, WORLD, 27, no_house).next_report.is_empty(), "legacy view")
	var first := Gov.plan({}, "governor_open", {}, WORLD, 27, facts)
	if not first.ok:
		check(false, "open"); return
	var estate: Dictionary = first.value
	var id: String = estate.settlement_id
	var target := {"settlement_id":id}
	check(V.typed_id(id, "settlement"), "typed ID")
	check(Gov.plan({}, "governor_open", {}, WORLD, 0, facts).value.settlement_id == id, "stable per world")
	check(Gov.plan({}, "governor_open", {}, WORLD+"2", 27, facts).value.settlement_id != id, "different worlds")
	check(estate.last_day == 27 and estate.last_report.is_empty() and Gov.validate(estate, WORLD, 27, facts).ok, "late opening at current day")
	check(not Gov.plan(estate, "governor_open", {}, WORLD, 27, facts).ok, "cannot reset estate")
	check(not Gov.plan(estate, "governor_dismiss", target, WORLD, 27, facts).ok, "vacant dismissal")
	check(not Gov.plan(estate, "governor_assign", changed(target,"hero_id",LEADER), WORLD, 27, facts).ok, "ineligible leader")
	check(not Gov.plan(estate, "governor_assign", changed(target,"hero_id",id), WORLD, 27, facts).ok, "wrong ID type")
	check(not Gov.plan(estate, "governor_assign", changed(target,"hero_id",COUSIN), WORLD, 27, changed(facts,"can_manage",false)).ok, "unavailable leader")
	var unknown_owner := changed(facts, "clan_id", "clan/00000000-0000-4000-8000-000000000002")
	check(not Gov.plan(estate, "governor_assign", changed(target,"hero_id",COUSIN), WORLD, 27, unknown_owner).ok, "foreign household")
	check(not Gov.plan(estate, "governor_assign", {"settlement_id":id+"!", "hero_id":COUSIN}, WORLD, 27, facts).ok, "wrong estate")
	check(not Gov.plan(estate, "governor_assign", {"settlement_id":id, "hero_id":COUSIN, "leadership":99}, WORLD, 27, facts).ok, "skill injection")
	var appointment := Gov.plan(estate, "governor_assign", changed(target,"hero_id",COUSIN), WORLD, 27, facts)
	if not appointment.ok:
		check(false, "valid appointment"); return
	var assigned: Dictionary = appointment.value
	check(assigned.governor_id == COUSIN and estate.governor_id == null, "appointment candidate isolation")
	check(not Gov.plan(assigned, "governor_assign", changed(target,"hero_id",COUSIN), WORLD, 27, facts).ok, "same assignment")
	var forecast := Gov.view(assigned, WORLD, 27, facts)
	check(forecast.candidates.size()==3 and forecast.next_report.prosperity_bonus==5 and forecast.next_report.loyalty_bonus==9, "skills reach projection")
	forecast.candidates[0].name="伪造"
	check(facts.members[0].name=="家主", "projection isolates character facts")
	var vacant: Dictionary = Gov.daily(estate, 28, facts).value
	var governed: Dictionary = Gov.daily(assigned, 28, facts).value
	check(vacant.prosperity==501 and vacant.loyalty==499 and vacant.last_report.governor_id==null, "vacant day")
	check(governed.prosperity==506 and governed.loyalty==508 and governed.last_report==forecast.next_report, "applied report is the forecast")
	check(assigned.last_day==27 and assigned.last_report.is_empty(), "daily never publishes in place")
	check(not Gov.daily(governed,28,facts).ok and not Gov.daily(governed,30,facts).ok, "no duplicate, skipped, or backdated day")
	check(Gov.validate(governed, WORLD, 28, facts).ok, "valid latest report")
	var restored: Dictionary = C.decode(C.encode(governed).value).value
	check(Gov.validate(restored, WORLD, 28, facts).ok and restored==governed, "canonical save roundtrip")
	var replacement: Dictionary = Gov.plan(governed, "governor_assign", changed(target,"hero_id",SECOND), WORLD, 28, facts).value
	check(replacement.last_report.governor_id==COUSIN and replacement.governor_id==SECOND, "governor changes, yesterday preserved")
	var replaced: Dictionary = Gov.daily(replacement, 29, changed(facts,"can_manage",false)).value
	check(replaced.prosperity==520 and replaced.loyalty==508, "different governor, leader unavailability does not cancel existing appointment")
	var dismissed: Dictionary = Gov.plan(replaced, "governor_dismiss", target, WORLD, 29, facts).value
	check(dismissed.governor_id==null and dismissed.last_report.governor_id==SECOND and Gov.validate(dismissed,WORLD,29,facts).ok, "dismiss, preserve and load report")
	var unavailable := facts.duplicate(true)
	unavailable.members[2].eligible=false
	unavailable.members[2].reason="已被俘"
	var released := Gov.reconcile(replaced, unavailable)
	check(released.governor_id==null and released.last_report==replaced.last_report and replaced.governor_id==SECOND, "release on changed eligibility, leave history")
	check(Gov.validate(released,WORLD,29,unavailable).ok and not Gov.validate(replaced,WORLD,29,unavailable).ok, "restore detects ineligible incumbent")
	check(Gov.daily(replaced,30,unavailable).value.last_report.governor_id==null, "no contribution from invalid incumbent")
	check(not Gov.validate(governed, WORLD+"2",28,facts).ok and not Gov.validate(governed,WORLD,28,unknown_owner).ok,"cold world/owner mismatch")
	for bad in [changed(governed,"schema_version",2),changed(governed,"governor_id",id),changed(governed,"governor_id","hero/00000000-0000-4000-8000-000000000004"),changed(governed,"prosperity",1001),changed(governed,"loyalty",-1),changed(governed,"last_day",29),changed(governed,"last_day",27),changed(governed,"opened_day",29),changed(governed,"opened_day",28),changed(governed,"last_report",{}),changed(governed,"extra",0)]:
		check(not Gov.validate(bad,WORLD,28,facts).ok,"bad snapshot: "+str(bad.keys()))
	for bad_report in [changed(governed.last_report,"day",27),changed(governed.last_report,"governor_id",null),changed(governed.last_report,"governor_id",id),changed(governed.last_report,"prosperity_base",-5),changed(governed.last_report,"prosperity_before",501),changed(governed.last_report,"loyalty_bonus",0),changed(governed.last_report,"loyalty_after",507),changed(governed.last_report,"extra",true)]:
		check(not Gov.validate(changed(governed,"last_report",bad_report),WORLD,28,facts).ok,"bad historical rollup")
	for d in range(29, 530):
		governed=Gov.daily(governed,d,facts).value
		vacant=Gov.daily(vacant,d,facts).value
	check(governed.prosperity==1000 and governed.loyalty==1000 and Gov.validate(governed,WORLD,529,facts).ok, "upper bounds and applied daily audit")
	check(vacant.prosperity==1000 and vacant.loyalty==0 and Gov.validate(vacant,WORLD,529,facts).ok, "vacant lower and upper bounds")
	check(governed.last_report.prosperity_before==1000 and governed.last_report.prosperity_bonus==5 and governed.last_report.prosperity_after==1000, "report retains raw bonus at upper limit")
	var invented := changed(governed.last_report, "prosperity_bonus", 9999)
	check(not Gov.validate(changed(governed,"last_report",invented),WORLD,529,facts).ok, "clipping cannot conceal an impossible contribution")
	var outsider := changed(governed.last_report, "governor_id", "hero/00000000-0000-4000-8000-000000000004")
	check(not Gov.validate(changed(governed,"last_report",outsider),WORLD,529,facts).ok, "unknown historical hero cannot appear in account")
	var trained := facts.duplicate(true)
	trained.members[1].stewardship += 2
	check(Gov.validate(governed,WORLD,529,trained).ok and Gov.view(governed,WORLD,529,trained).next_report.prosperity_bonus==7, "later training improves forecast without changing historical report")

func _initialize() -> void:
	run()
	print("P4_GOVERNANCE ",checks-failures,"/",checks," failures=",failures)
	quit(1 if failures else 0)
