extends SceneTree

const Registry = preload("res://shared/definitions/registry.gd")
const Canonical = preload("res://contracts/canonical.gd")
var failed := 0

func check(condition: bool, name: String) -> void:
	if not condition:
		failed += 1
		printerr("FAIL ", name)

func row(id: String, fields: Dictionary = {}) -> Dictionary:
	var definition := {"id":id, "schema_version":1, "source_package":"marsh"}
	match id.get_slice(":", 1).get_slice("/", 0):
		"troop": definition.merge({"culture_id":"marsh:culture/reed","tier":1,"role":"infantry","equipment_set_ids":["marsh:equipment/patrol"],"skills":{},"wage_per_day":1,"recruit_cost":1,"upgrade_edges":[],"tags":[]})
		"item": definition.merge({"category":"armor","base_value":4,"weight":1,"quality_policy":"standard","slot_tags":[],"asset_ref":"marsh/coat"})
		"action": definition.merge({"duration_ticks":8,"active_windows":[],"cancel_rules":{},"trajectory_ref":"marsh/arc"})
	definition.merge(fields, true)
	return definition

func _initialize() -> void:
	var rows := [
		row("marsh:culture/reed", {"tags":["delta"]}),
		row("marsh:item/coat", {"slot_tags":["body"]}),
		row("marsh:equipment/patrol", {"slots":{"body":"marsh:item/coat"}}),
		row("marsh:troop/recruit", {"culture_id":"marsh:culture/reed","equipment_set_ids":["marsh:equipment/patrol"],
			"tags":["shield","melee","shield"],"skills":{"spear":15},"tier":1,"recruit_cost":8,
			"upgrade_edges":[{"target_id":"marsh:troop/patrol","xp":20,"gold":4}]}),
		row("marsh:troop/patrol", {"tags":["shield"]}),
		row("marsh:part/grip")
	]
	var before := failed
	var cyclic := rows.duplicate(true)
	cyclic[4]["upgrade_edges"] = [{"target_id":"marsh:troop/recruit"}]
	var registry := Registry.new()
	var bad := registry.build(cyclic)
	check(not bad.ok and bad.error.code == "Conflict", "reject cycle")
	if not bad.ok:
		check(bad.error.detail == ["marsh:troop/patrol","marsh:troop/recruit","marsh:troop/patrol"], "cycle path")
	check(not registry.get_definition("marsh:troop/recruit").ok, "no partial state")
	var perks := [row("marsh:perk/a", {"prerequisite_ids":["marsh:perk/b"]}), row("marsh:perk/b", {"prerequisite_ids":["marsh:perk/a"]})]
	check(not Registry.new().build(perks).ok, "perk cycle")
	print("T-DEF-01 ", "PASS" if failed == before else "FAIL")
	before = failed
	check(registry.build(rows).ok, "publish after failed compile")
	check(registry.validate_references().ok, "published reference graph is valid")
	var alternate := Registry.new()
	var reverse := rows.duplicate(true)
	reverse.reverse()
	check(alternate.build(reverse).ok, "reverse load")
	for data in rows:
		check(registry.resolve_index(data.id).value == alternate.resolve_index(data.id).value, "stable indices")
	var troops := registry.list_by_tag("troop", ["shield","melee"])
	check(troops.size() == 1 and troops[0].id == "marsh:troop/recruit", "query original content")
	check(registry.get_definition("marsh:equipment/patrol","equipment").ok and registry.get_definition("marsh:culture/reed","culture").ok,"typed lookup")
	check(not registry.get_definition("marsh:troop/recruit", "item").ok,"wrong type")
	check(not registry.build([]).ok, "snapshot cannot be rebuilt")
	check(troops.is_read_only() and troops[0].is_read_only() and troops[0].tags.is_read_only() and troops[0].upgrade_edges[0].is_read_only(), "deep immutable")
	rows[3].skills["spear"] = 900
	check(troops[0].skills.spear == 15, "input isolated")
	print("T-DEF-02 ", "PASS" if failed == before else "FAIL")
	before = failed
	var crafted := row("world:item/cane", {"part_ids":["marsh:part/grip"], "rule_snapshot":{"quality":80}, "base_value":17})
	check(registry.validate_dynamic_definition(crafted, {}).ok, "valid dynamic item")
	var parsed := Canonical.decode(Canonical.encode(crafted).value)
	check(parsed.ok and parsed.value.id == crafted.id and parsed.value.rule_snapshot.quality == 80 and registry.validate_dynamic_definition(parsed.value, {}).ok, "restore canonical overlay")
	check(not registry.get_definition(crafted.id).ok, "separate world truth")
	var changed := crafted.duplicate(true)
	changed.rule_snapshot.quality = 81
	var overlay := {}
	overlay[crafted.id] = crafted
	check(not registry.validate_dynamic_definition(changed, overlay).ok, "collision")
	changed.part_ids = ["marsh:part/missing"]
	check(not registry.validate_dynamic_definition(changed, {}).ok, "missing part")
	print("T-DEF-03-SLICE ", "PASS" if failed == before else "FAIL")
	before = failed
	var broken := reverse.duplicate(true)
	broken.append(rows[0])
	check(not Registry.new().build(broken).ok, "duplicate")
	check(not Registry.new().build([row("marsh:troop/w",{"culture_id":"marsh:culture/gone"})]).ok, "bad reference")
	check(not Registry.new().build([row("marsh:troop/w",{"culture_id":"marsh:item/coat"}),rows[1]]).ok, "wrong reference type")
	check(not Registry.new().build([row("marsh:action/w",{"duration_ticks":8,"active_windows":[[2,9]]})]).ok, "action bounds")
	check(not Registry.new().build([row("marsh:equipment/w",{"slots":{"foot":"marsh:item/coat"}}),rows[1]]).ok, "incompatible slot")
	check(not Registry.new().build([row("bad-id")]).ok, "malformed ID")
	check(not Registry.new().build([{"id":"marsh:troop/x","schema_version":true,"source_package":"base"}]).ok,"strict version")
	broken = rows.duplicate(true)
	broken[3]["role"] = true
	check(not Registry.new().build(broken).ok,"role type")
	broken = rows.duplicate(true)
	broken[3]["culture_ids"] = ["marsh:culture/gone"]
	check(not Registry.new().build(broken).ok,"unknown critical field")
	broken = rows.duplicate(true)
	broken[3].upgrade_edges = [{"target_id":"marsh:troop/patrol","xp":20,"gld":40}]
	var invalid_edge := Registry.new().build(broken)
	check(not invalid_edge.ok and invalid_edge.error.field == "marsh:troop/recruit.upgrade_edges[0].gld", "misspelled edge cost")
	broken = rows.duplicate(true)
	broken[3].erase("skills")
	check(not Registry.new().build(broken).ok,"required troop data")
	check(not Registry.new().build([row("marsh:item/bad",{"category":true})]).ok, "item category type")
	check(Registry.new().build([row("marsh:culture/basic",{"metadata":{"marsh:origin":"south"}})]).ok,"metadata extension")
	print("P1-DEF-BOUNDARIES ", "PASS" if failed == before else "FAIL")
	quit(0 if not failed else 1)
