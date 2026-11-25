extends RefCounted
## Pure campaign hero transitions. The caller owns authorization, world time and commit.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const C = preload("res://contracts/canonical.gd")
const Numeric = preload("res://shared/rules/numeric_policy.gd")
const RULES := "res://campaign/character/hero_rules.json"
const BACKGROUNDS := ["culture", "childhood", "occupation", "identity"]
const SCOPES := ["self", "captain", "party", "army", "settlement", "clan"]
const TRAITS := ["bravery", "honor", "caution", "mercy"]
const HOME := "character:place/home"
const HERO_KEYS := ["version","id","name","age","created_day","culture","childhood","occupation","identity",
	"appearance","banner","attributes","skills","traits","perks","level","skill_gains","focus_points",
	"perk_points","wounds","captive","location_ref","life_status","cause","recovery_day",
	"practice_day","practice_counts","sources"]
static var _rules := {}

static func _shape(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and value.has_all(keys)

static func _text(value: Variant, limit: int) -> bool:
	if not value is String or value.is_empty() or value.length() > limit or value != value.strip_edges():
		return false
	for index in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127:
			return false
	return C.encode(value).ok

static func _key(value: Variant) -> bool:
	return C.Reader.valid_key(value) and value.length() <= 240 and value==value.strip_edges()

static func _world_location(value: Variant) -> bool:
	return value == HOME or V.typed_id(value,"party") or V.typed_id(value,"settlement")

static func _rules_valid(r: Variant) -> bool:
	if not _shape(r, ["version","defaults","options","age_min","age_max","skills","attributes","perks","origins","learning","health"]):
		return false
	if r.version != 1 or not V.integer(r.age_min, 1, 100) or not V.integer(r.age_max, r.age_min, 100):
		return false
	if not _shape(r.options, BACKGROUNDS + ["appearance","banner"]) or not _shape(r.defaults, r.options.keys()+["age","name"]):
		return false
	if not _text(r.defaults.name,32) or not V.integer(r.defaults.age,r.age_min,r.age_max):
		return false
	if not r.attributes is Dictionary or r.attributes.size()!=6 or not r.skills is Dictionary or r.skills.size()<18 or not r.skills.has("medicine") or not r.perks is Dictionary or r.perks.is_empty() or not _shape(r.origins,BACKGROUNDS):
		return false
	for group in r.options:
		var choices: Variant = r.options[group]
		if not choices is Dictionary or not choices.has(r.defaults[group]):
			return false
		for key in choices:
			if not _key(key) or not _text(choices[key],48):
				return false
		if group not in BACKGROUNDS:
			continue
		if not _shape(r.origins[group],choices.keys()):
			return false
		for origin in r.origins[group].values():
			if not origin is Array or origin.size()!=3 or not r.attributes.has(origin[0]) or not r.skills.has(origin[1]) or origin[2] not in TRAITS:
				return false
	for a in r.attributes:
		if not _key(a) or not _text(r.attributes[a],32):
			return false
	for s in r.skills:
		var row: Variant = r.skills[s]
		if not _key(s) or not _shape(row,["attribute","label"]) or not r.attributes.has(row.attribute) or not _text(row.label,32):
			return false
	for p in r.perks:
		var row: Variant = r.perks[p]
		if not _key(p) or not _shape(row,["label","skill","level","group","scope","effect","bonus"]):
			return false
		if not _text(row.label,32) or not r.skills.has(row.skill) or not _key(row.group) or row.scope not in SCOPES or not r.skills.has(row.effect) or not V.integer(row.level,1,300) or not V.integer(row.bonus,1,100):
			return false
	if not _shape(r.learning,["base_xp","level_step","practice_units","per_attribute","per_focus","cap_attribute","cap_focus","levels_per_rank","focus_max","skill_max"]):
		return false
	if not _shape(r.health,["base_recovery","medicine_divisor","rest_bonus","fatal_percent"]) or not V.integer(r.health.fatal_percent,0,100):
		return false
	for n in r.learning.values() + [r.health.base_recovery,r.health.medicine_divisor,r.health.rest_bonus]:
		if not V.integer(n,1,1000): return false
	return true

static func catalog() -> Dictionary:
	if _rules.is_empty():
		var parsed := C.decode_source(FileAccess.get_file_as_bytes(RULES))
		if not parsed.ok or not _rules_valid(parsed.value):
			return {}
		_rules = parsed.value
	return _rules.duplicate(true)

static func create(id: String, choices: Dictionary, day: int) -> Dictionary:
	if _rules.is_empty() and catalog().is_empty(): return R.fail("Unavailable","hero_rules")
	if not V.typed_id(id,"hero") or not V.integer(day): return R.fail("InvalidArgument","hero.identity")
	var picked: Dictionary = _rules.defaults.duplicate()
	for key in choices:
		if not picked.has(key): return R.fail("InvalidArgument","choices.field")
		picked[key]=choices[key]
	if not _text(picked.name,32) or not V.integer(picked.age,_rules.age_min,_rules.age_max): return R.fail("InvalidArgument","name_or_age")
	for key in _rules.options:
		if not _rules.options[key].has(picked[key]): return R.fail("InvalidArgument",key)
	var h := {"version":1,"id":id,"created_day":day,"attributes":{},"skills":{},"traits":{},"perks":[],
		"level":1,"skill_gains":0,"focus_points":1,"perk_points":1,"wounds":0,"captive":false,
		"location_ref":HOME,"life_status":"Healthy","cause":"","recovery_day":day,
		"practice_day":day,"practice_counts":{},"sources":{}}
	h.merge(picked)
	for key in _rules.attributes: h.attributes[key]=1
	for key in _rules.skills: h.skills[key]={"level":0,"xp":0,"focus":0}
	for trait_id in TRAITS: h.traits[trait_id]=0
	for group in BACKGROUNDS:
		var origin: Array = _rules.origins[group][h[group]]
		h.attributes[origin[0]] += 1
		h.skills[origin[1]].level += 2
		h.traits[origin[2]] += 1
	return R.ok(h)

static func _threshold(level: int) -> int:
	return _rules.learning.base_xp + level * _rules.learning.level_step

static func _cap(h: Dictionary, skill: String) -> int:
	return h.attributes[_rules.skills[skill].attribute] * _rules.learning.cap_attribute + h.skills[skill].focus * _rules.learning.cap_focus

static func _active_status(h: Dictionary) -> String:
	if h.captive: return "Captive"
	return "Wounded" if h.wounds>0 else "Healthy"

static func validate(hero: Variant) -> Dictionary:
	if _rules.is_empty() and catalog().is_empty():return R.fail("Unavailable","hero_rules")
	if not _shape(hero,HERO_KEYS) or not V.integer(hero.version,1,1) or not V.typed_id(hero.id,"hero"):
		return R.fail("InvalidArgument","hero")
	var h: Dictionary=hero
	if not _text(h.name,32) or not V.integer(h.age,_rules.age_min,_rules.age_max) or not V.integer(h.created_day):
		return R.fail("InvalidArgument","identity")
	for key in _rules.options:
		if not _rules.options[key].has(h[key]): return R.fail("InvalidArgument",key)
	if not _shape(h.attributes,_rules.attributes.keys()) or not _shape(h.skills,_rules.skills.keys()) or not _shape(h.traits,TRAITS):
		return R.fail("InvalidArgument","build")
	var base_attributes := {}
	var base_skills := {}
	var base_traits := {}
	for a in _rules.attributes: base_attributes[a]=1
	for s in _rules.skills: base_skills[s]=0
	for t in TRAITS: base_traits[t]=0
	for group in BACKGROUNDS:
		var o: Array = _rules.origins[group][h[group]]
		base_attributes[o[0]]+=1
		base_skills[o[1]]+=2
		base_traits[o[2]]+=1
	if h.attributes != base_attributes or h.traits != base_traits:
		return R.fail("InvalidArgument","origins")
	var gained := 0
	var invested := 0
	for skill in h.skills:
		var row: Variant=h.skills[skill]
		if not _shape(row,["level","xp","focus"]) or not V.integer(row.level,base_skills[skill],_rules.learning.skill_max) or not V.integer(row.focus,0,_rules.learning.focus_max):
			return R.fail("InvalidArgument","skill")
		if not V.integer(row.xp,0,_threshold(row.level)-1) or (row.level==_rules.learning.skill_max and row.xp!=0):
			return R.fail("InvalidArgument","skill_xp")
		gained+=row.level-base_skills[skill]
		invested+=row.focus
	if not V.integer(h.skill_gains,gained,gained) or not V.integer(h.level,1) or h.level != 1 + floori(float(gained)/_rules.learning.levels_per_rank):
		return R.fail("InvalidArgument","rank")
	if not V.integer(h.focus_points) or h.focus_points + invested != h.level or not C.is_json_array(h.perks) or not V.integer(h.perk_points) or h.perk_points+h.perks.size()!=h.level:
		return R.fail("InvalidArgument","points")
	var groups := {}
	for id in h.perks:
		if not _rules.perks.has(id): return R.fail("InvalidArgument","perk")
		var p: Dictionary = _rules.perks[id]
		if groups.has(p.group) or h.skills[p.skill].level < p.level: return R.fail("Conflict","perk_group")
		groups[p.group]=true
	if not V.integer(h.wounds,0,100) or not h.captive is bool or not h.cause is String or (not h.cause.is_empty() and not _key(h.cause)):
		return R.fail("InvalidArgument","condition")
	if h.life_status in ["Retired","Dead"]:
		if h.captive or h.location_ref!="character:place/archive" or h.cause.is_empty():return R.fail("InvalidArgument","terminal")
	elif h.life_status!=_active_status(h) or not _world_location(h.location_ref) or (h.captive and h.location_ref==HOME) or (h.wounds>0 and h.cause.is_empty()):
		return R.fail("InvalidArgument","life_status")
	if not V.integer(h.recovery_day,h.created_day) or not V.integer(h.practice_day,h.created_day) or not h.practice_counts is Dictionary or not h.sources is Dictionary:
		return R.fail("InvalidArgument","history")
	for skill in h.practice_counts:
		if not h.skills.has(skill) or not V.integer(h.practice_counts[skill],1,4):return R.fail("InvalidArgument","practice_counts")
	# Shard event receipts so long campaigns remain representable by the canonical save format.
	for prefix in h.sources:
		var page: Variant=h.sources[prefix]
		if not V.hex(prefix,2) or not page is Dictionary or page.is_empty() or page.size()>C.MAX_ITEMS:
			return R.fail("InvalidArgument","source_page")
		for event in page:
			if not _key(event) or event.sha256_text().left(2)!=prefix or not V.hex(page[event],64):
				return R.fail("InvalidArgument","source")
	return R.ok()

static func _advance(h: Dictionary, skill: String, units: int, divisor: int) -> void:
	var row: Dictionary=h.skills[skill]
	var attr: int=h.attributes[_rules.skills[skill].attribute]
	var rules: Dictionary=_rules.learning
	var rate: int=100 + attr*rules.per_attribute + row.focus*rules.per_focus
	divisor *= 1 + maxi(0,row.level-_cap(h,skill))
	row.xp += floori(float(units*rate)/(100*divisor))
	while row.level < rules.skill_max and row.xp>=_threshold(row.level):
		row.xp-=_threshold(row.level)
		row.level+=1
		h.skill_gains+=1
		if h.skill_gains%rules.levels_per_rank==0:
			h.level+=1
			h.focus_points+=1
			h.perk_points+=1
	if row.level==rules.skill_max: row.xp=0

static func _perk_eligible(h: Dictionary, id: String) -> bool:
	var p: Dictionary=_rules.perks[id]
	if h.perk_points<1 or h.skills[p.skill].level<p.level: return false
	for old in h.perks:
		if _rules.perks[old].group==p.group: return false
	return true

static func _resolved_skill(hero: Dictionary, skill: String, scope: String) -> Dictionary:
	if _rules.is_empty() and catalog().is_empty():return R.fail("Unavailable","hero_rules")
	var skills: Variant=hero.get("skills",{})
	if not skills is Dictionary or not _rules.skills.has(skill) or scope not in SCOPES:
		return R.fail("InvalidArgument","skill")
	var progress: Variant=skills.get(skill)
	if not progress is Dictionary or not V.integer(progress.get("level"),0,_rules.learning.skill_max):
		return R.fail("InvalidArgument","skill_level")
	var perks: Variant=hero.get("perks",[])
	if not C.is_json_array(perks):return R.fail("InvalidArgument","perks")
	var modifiers: Array=[]
	for id in perks:
		if not _rules.perks.has(id):return R.fail("InvalidArgument","perk")
		var p: Dictionary=_rules.perks[id]
		if p.effect==skill:
			modifiers.append({"source_id":id,"scope":p.scope,"group":p.group,"priority":1,"operation":"add","value":p.bonus})
	return Numeric.apply_effects(progress.level,modifiers,scope)

static func effective_skill(hero: Dictionary, skill: String, scope: String="self") -> int:
	var resolved:=_resolved_skill(hero,skill,scope)
	return int(resolved.value.final) if resolved.ok else 0

static func _terminal(h: Dictionary, status: String, cause: String) -> void:
	h.life_status=status
	h.captive=false
	h.location_ref="character:place/archive"
	h.cause=cause

static func _outcome(h: Dictionary, args: Dictionary, day: int) -> Dictionary:
	var kind: Variant=args.get("kind")
	match kind:
		"skill":
			if not _shape(args,["source","kind","skill","amount"]) or not h.skills.has(args.skill) or not V.integer(args.amount,1,1000):
				return R.fail("InvalidArgument","skill_outcome")
			if h.life_status!="Healthy": return R.fail("InvalidState","skill_outcome")
			_advance(h,args.skill,args.amount,1)
		"wound", "casualty":
			if not _shape(args,["source","kind","severity"]) or not V.integer(args.severity,1,100):
				return R.fail("InvalidArgument","severity")
			h.wounds=mini(100,h.wounds+args.severity)
			h.recovery_day=day
			h.cause=args.source
			# A confirmed potentially fatal outcome has one deterministic roll per hero and result.
			if kind=="casualty":
				var roll := C.hash_value([h.id,args.source,"mortality"])
				if not roll.ok: return roll
				if roll.value.left(8).hex_to_int()%100 < _rules.health.fatal_percent:
					_terminal(h,"Dead",args.source)
					return R.ok()
		"capture","join","release","leave":
			var releasing: bool = kind=="release"
			if not _shape(args,["source","kind","location"]) and not (releasing and _shape(args,["source","kind"])):
				return R.fail("InvalidArgument","location")
			var location: Variant=args.get("location",HOME)
			if not _world_location(location) or (kind=="join" and not V.typed_id(location,"party")) or (kind=="capture" and location==HOME):
				return R.fail("InvalidArgument","location")
			if (kind=="capture" and h.captive) or (releasing and not h.captive) or (kind=="join" and h.life_status!="Healthy"):
				return R.fail("InvalidState","location")
			if kind=="join" and V.typed_id(h.location_ref,"party"):return R.fail("Conflict","party_membership")
			if kind=="leave" and (h.captive or not V.typed_id(h.location_ref,"party") or V.typed_id(location,"party")):
				return R.fail("InvalidState","party_membership")
			h.captive=kind=="capture"
			h.location_ref=location
		"death":
			if not _shape(args,["source","kind"]):return R.fail("InvalidArgument","death")
			_terminal(h,"Dead",args.source)
			return R.ok()
		_:
			return R.fail("InvalidArgument","outcome.kind")
	h.life_status=_active_status(h)
	return R.ok()

static func apply(hero: Dictionary, op: String, args: Dictionary, day: int) -> Dictionary:
	var valid := validate(hero)
	if not valid.ok: return valid
	if not V.integer(day,hero.created_day): return R.fail("InvalidArgument","day")
	var digest := ""
	var prefix := ""
	if op in ["practice","outcome"]:
		var source: Variant=args.get("source")
		if not _key(source):return R.fail("InvalidArgument","source")
		var hashed:=C.hash_value([op,args])
		if not hashed.ok:return hashed
		digest=hashed.value
		prefix=source.sha256_text().left(2)
		var page: Dictionary=hero.sources.get(prefix,{})
		if page.has(source):
			return R.ok(hero.duplicate(true)) if page[source]==digest else R.fail("Conflict","source")
		if page.size()>=C.MAX_ITEMS: return R.fail("Unavailable","source_page")
	if hero.life_status in ["Dead","Retired"]:return R.fail("InvalidState","terminal")
	if day<maxi(hero.recovery_day,hero.practice_day): return R.fail("StaleVersion","day")
	var h:=hero.duplicate(true)
	match op:
		"focus":
			if not _shape(args,["skill"]) or not h.skills.has(args.skill):return R.fail("InvalidArgument","skill")
			if h.focus_points<1 or h.skills[args.skill].focus>=_rules.learning.focus_max:return R.fail("InsufficientResource","focus")
			h.skills[args.skill].focus+=1
			h.focus_points-=1
		"perk":
			if not _shape(args,["perk"]) or not _rules.perks.has(args.perk):return R.fail("InvalidArgument","perk")
			if not _perk_eligible(h,args.perk):return R.fail("InvalidState","perk")
			h.perks.append(args.perk)
			h.perk_points-=1
		"practice":
			if not _shape(args,["skill","source"]) or not h.skills.has(args.skill):return R.fail("InvalidArgument","practice")
			if h.life_status!="Healthy":return R.fail("InvalidState","practice")
			if h.practice_day!=day:
				h.practice_day=day
				h.practice_counts={}
			var count: int=h.practice_counts.get(args.skill,0)
			if count<4:
				_advance(h,args.skill,_rules.learning.practice_units,1<<count)
				h.practice_counts[args.skill]=count+1
		"rest":
			if not args.is_empty() and not (_shape(args,["resting"]) and is_same(args.resting,true)):
				return R.fail("InvalidArgument","rest")
			var elapsed: int=mini(day-h.recovery_day,100)
			var rate: int=_rules.health.base_recovery
			if args.get("resting",false) and not h.captive:rate+=_rules.health.rest_bonus
			var medicine:=effective_skill(h,"medicine")
			var divisor: int=_rules.health.medicine_divisor
			# Measure fractional healing on world-day boundaries, so small perks count across days.
			var remainder: int=(((day-elapsed)%divisor)*medicine)%divisor
			@warning_ignore("integer_division")
			var healing: int=elapsed*rate+(elapsed*medicine+remainder)/divisor
			h.wounds=maxi(0,h.wounds-healing)
			h.recovery_day=day
			if h.wounds==0: h.cause=""
			h.life_status=_active_status(h)
		"outcome":
			var applied:=_outcome(h,args,day)
			if not applied.ok: return applied
		"retire":
			if not args.is_empty():return R.fail("InvalidArgument","retire")
			if h.captive:return R.fail("InvalidState","retire")
			_terminal(h,"Retired","voluntary_retirement")
		_:
			return R.fail("NotFound","hero.operation")
	if not digest.is_empty():
		if not h.sources.has(prefix): h.sources[prefix]={}
		h.sources[prefix][args.source]=digest
	return R.ok(h)

static func view(hero: Dictionary) -> Dictionary:
	if not validate(hero).ok:return {}
	var result:=hero.duplicate(true)
	result.erase("sources")
	result.erase("practice_counts")
	result["can_fight"]=hero.life_status=="Healthy"
	result["can_join"]=result.can_fight and not V.typed_id(hero.location_ref,"party")
	result["available_perks"]=[]
	result["effects"]={}
	for skill in result.skills:
		var row: Dictionary=result.skills[skill]
		row["next_xp"]=_threshold(row.level)
		row["soft_cap"]=_cap(hero,skill)
	for perk in _rules.perks:
		if hero.life_status not in ["Dead","Retired"] and _perk_eligible(hero,perk):result.available_perks.append(perk)
	# Show the same scoped skill calculation used by equipment and recovery.
	for id in hero.perks:
		var p: Dictionary=_rules.perks[id]
		if not result.effects.has(p.scope):result.effects[p.scope]={}
		if result.effects[p.scope].has(p.effect):continue
		var resolved:=_resolved_skill(hero,p.effect,p.scope)
		if not resolved.ok:continue
		var sources: Array=[]
		for step in resolved.value.steps:sources.append(step.source_id)
		result.effects[p.scope][p.effect]={"bonus":int(resolved.value.final-resolved.value.base),"sources":sources}
	return result
