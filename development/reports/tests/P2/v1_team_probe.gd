extends SceneTree
const Schema = preload("res://contracts/schema.gd")

func _initialize() -> void:
	var side := {"team_key":"north","faction_id":"faction-a","commander_hero_id":null,"roster_allocations":[]}
	var other := side.duplicate(true)
	other.team_key = "south"
	other.faction_id = "faction-b"
	var squad := {"source_party_id":"party/b48883c0-79fb-4cd3-96fe-43bb44dfddbb",
		"troop_def_id":"base:troop/infantry","hero_id":null,"count":4,"source_slot_range":[0,4],
		"loadout_snapshot_id":"loadout"}
	var spec := {"schema_version":1,"encounter_id":"encounter/b48883c0-79fb-4cd3-96fe-43bb44dfddbb",
		"reservation_revision":1,"mode":"campaign","scene_def_id":"base:scene/field",
		"ruleset_id":"base:rule/field","environment":{},"rng_seed":"0123456789abcdef",
		"sides":[side,other],"reserved_sources":[squad],"battle_limit":4,
		"deployment_constraints":{},"siege_snapshot":null}
	var accepted: bool = Schema.validate_shape("EncounterSpec", spec).ok
	print("P2_V1_TEAM_PREFLIGHT ", "PASS" if accepted else "FAIL",
		" v1_accepts_unspecified_team_owners=", accepted, " teams=2 sources=4")
	quit(0 if accepted else 1)
