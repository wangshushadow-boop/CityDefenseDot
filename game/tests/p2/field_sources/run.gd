extends SceneTree

const Fields = preload("res://contracts/field_sources.gd")
const Schema = preload("res://contracts/schema.gd")
const UUID := "b48883c0-79fb-4cd3-96fe-43bb44dfddbb"
const END := 4294967296
var checks := 0
var failures := 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		printerr("FAIL ", label)
		failures += 1


func source(first: int, stop: int) -> Dictionary:
	return {"source_party_id":"party/" + UUID, "troop_def_id":"base:troop/guard", "hero_id":null,
		"count":stop - first, "source_slot_range":[first,stop], "loadout_snapshot_id":"stock"}


func side(key: Variant, bounds: Array) -> Dictionary:
	var allocations := []
	for pair in bounds:
		allocations.append({"source_slot_range":pair})
	return {"team_key":key, "faction_id":"base:faction/garrison", "commander_hero_id":null,
		"roster_allocations":allocations}


func spec(sides: Array, sources: Array) -> Dictionary:
	return {"schema_version":1, "encounter_id":"encounter/" + UUID, "reservation_revision":1,
		"mode":"campaign", "scene_def_id":"base:scene/field", "ruleset_id":"base:rule/field",
		"environment":{}, "rng_seed":0, "sides":sides, "reserved_sources":sources,
		"battle_limit":500, "deployment_constraints":{}, "siege_snapshot":null}


func rejects(input: Dictionary, code: String, label: String) -> void:
	var result := Fields.build(input)
	check(not result.ok and result.error.code == code and not result.error.field.is_empty(), label)


func _initialize() -> void:
	var grouped := [source(10,14), source(0,2), source(2,4)]
	var input := spec([side(0, [[11,13],[0,1]]), side("0", [[1,4],[13,14]]), side("ally", [[10,11]])], grouped)
	var built := Fields.build(input)
	check(built.ok, "split one party/troop between three teams, adjacent reservations")
	if built.ok:
		var index: RefCounted = built.value
		input.sides[0].team_key = "mutated"
		input.sides[0].roster_allocations[1].source_slot_range[0] = 2
		for pair in [[0,0],[1,"0"],[3,"0"],[10,"ally"],[11,0],[12,0],[13,"0"]]:
			var found: Dictionary = index.team_for_slot(pair[0])
			check(found.ok and is_same(found.value, pair[1]), "stable typed key lookup " + str(pair))
		for gap in [4,9,14,END-1]:
			check(index.team_for_slot(gap).error.code == "NotFound", "gap or exclusive end")
		for invalid in [-1,END,true,"0",1.0,null]:
			check(index.team_for_slot(invalid).error.code == "InvalidArgument", "non-uint32 lookup")

	var huge := Fields.build(spec([side("left", [[0,END-1]]), side("right", [[END-1,END]])], [source(0,END)]))
	check(huge.ok, "entire uint32 domain, two allocation ranges")
	if huge.ok:
		check(huge.value.team_for_slot(END-2).value == "left" and huge.value.team_for_slot(END-1).value == "right", "upper boundary")

	var two := [source(0,4)]
	var historical := spec([side(0,[]), side(1,[])], two)
	var encoded := Schema.encode_value("EncounterSpec", historical)
	check(encoded.ok and Schema.decode_value("EncounterSpec", encoded.value).ok, "historical allocation-free v1 read")
	rejects(historical, "InvalidArgument", "field preparation rejects historical missing ownership")
	rejects(spec([],two), "InvalidArgument", "missing sides")
	rejects(spec([side(0, [[0,4]])],two), "InvalidArgument", "one side")
	rejects(spec([side(0, []),side(1, [])],[]), "InvalidArgument", "missing sources")
	rejects(spec([side(0, [[0,4]]), side(1, [])],two), "InvalidArgument", "empty one side")
	rejects(spec([side(1, [[0,2]]),side(1, [[2,4]])],two), "Conflict", "repeated key")
	rejects(spec([side(0, [[0,2],[1,2]]),side(1, [[2,4]])],two), "Conflict", "same-team overlap")
	rejects(spec([side(0, [[0,3]]),side(1, [[2,4]])],two), "Conflict", "cross-team overlap")
	rejects(spec([side(0, [[0,1]]),side(1, [[2,4]])],two), "InvalidArgument", "unclaimed slot")
	rejects(spec([side(0, [[0,2]]),side(1, [[2,5]])],two), "InvalidArgument", "outside reservations")
	rejects(spec([side(0, [[0,3]]),side(1, [[4,5]])],[source(0,2),source(4,6)]),
		"InvalidArgument", "equal cardinality but shifted through gap")

	for invalid in [true,{},{"other":[0,2]},{"source_slot_range":[0,2],"extra":1},
			{"source_slot_range":[0]}, {"source_slot_range":[0,true]}, {"source_slot_range":[0,"2"]},
			{"source_slot_range":[0,2.0]}, {"source_slot_range":[-1,2]}, {"source_slot_range":[2,2]},
			{"source_slot_range":[2,1]}, {"source_slot_range":[0,END+1]}]:
		var bad := spec([side(0, [[0,2]]),side(1, [[2,4]])],two)
		bad.sides[0].roster_allocations[0] = invalid
		rejects(bad, "InvalidArgument", "invalid allocation " + str(invalid))
	var hero := source(0,1)
	hero.hero_id = "hero/" + UUID
	hero.troop_def_id = null
	var hero_index := Fields.build(spec([side(0, [[0,1]]),side(1, [[1,4]])], [hero,source(1,4)]))
	check(hero_index.ok and is_same(hero_index.value.team_for_slot(0).value, 0), "hero singleton")
	print("FIELD_SOURCES checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
