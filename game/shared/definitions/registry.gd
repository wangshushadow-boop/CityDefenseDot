extends RefCounted

const Canonical = preload("res://contracts/canonical.gd")
const Result = preload("res://contracts/result.gd")
const Values = preload("res://contracts/values.gd")

const SINGLE_REFS := {"culture_id":"culture", "scene_id":"scene", "quest_id":"quest", "map_id":"map", "item_id":"item", "action_id":"action", "ruleset_id":"ruleset"}
const LIST_REFS := {"equipment_set_ids":"equipment", "item_ids":"item", "part_ids":"part", "scene_ids":"scene", "quest_ids":"quest", "troop_tree_ids":"troop", "prerequisite_ids":"perk", "prerequisites":"perk", "references":""}
const COMMON_FIELDS := {"id":"text", "schema_version":"uint", "source_package":"text", "tags":"texts", "references":"texts", "name":"text", "description":"text", "metadata":"map"}
const TYPE_FIELDS := {
	"troop":{"culture_id":"text","tier":"uint","role":"text","equipment_set_ids":"texts","skills":"map","wage_per_day":"uint","recruit_cost":"uint","upgrade_edges":"array"},
	"item":{"category":"text","base_value":"uint","weight":"uint","quality_policy":"policy","slot_tags":"texts","asset_ref":"text"},
	"action":{"duration_ticks":"uint","active_windows":"array","cancel_rules":"policy","trajectory_ref":"text"},
	"equipment":{"slots":"map","item_ids":"texts"},
	"perk":{"prerequisites":"texts","prerequisite_ids":"texts","exclusive_group":"text","scope":"text","effects":"array"},
	"culture":{"language_keys":"texts","visual_theme":"text","troop_tree_ids":"texts","settlement_theme":"text","economic_tags":"texts"},
	"scene":{"asset_ref":"text","spawn_zones":"array","nav_profiles":"array","links":"array","objectives":"array","interactions":"array","exit_zones":"array"},
	"ruleset":{"parameters":"map","rules":"map","mode":"text"},
	"hero":{"culture_id":"text","equipment_set_ids":"texts","skills":"map"},
	"part":{"category":"text","weight":"uint","length":"uint","asset_ref":"text","slot_tags":"texts"},
	"map":{"scene_ids":"texts","quest_ids":"texts"},
	"quest":{"scene_id":"text","map_id":"text","item_id":"text","action_id":"text","ruleset_id":"text","quest_id":"text"},
}
const REQUIRED_FIELDS := {
	"troop":["culture_id","tier","role","equipment_set_ids","skills","wage_per_day","recruit_cost","upgrade_edges","tags"],
	"item":["category","base_value","weight","quality_policy","slot_tags","asset_ref"],
	"action":["duration_ticks","active_windows","cancel_rules","trajectory_ref"],
}
const DYNAMIC_FIELDS := {"part_ids":"texts","rule_snapshot":"map"}
var _definitions := {}
var _indices := {}
var _by_tag := {}
var _published := false


static func _type_of(id: String) -> String:
	return id.get_slice(":", 1).get_slice("/", 0)


static func _failure(code: String, field: String, detail: Variant = null) -> Dictionary:
	var result := Result.fail(code, field)
	result.error.detail = detail
	return result


static func _text_list(value: Variant) -> bool:
	if not Canonical.is_json_array(value):
		return false
	for tag in value:
		if typeof(tag) != TYPE_STRING or tag.is_empty():
			return false
	return true


static func _has_type(value: Variant, expected: String) -> bool:
	match expected:
		"text": return typeof(value) == TYPE_STRING and not value.strip_edges().is_empty()
		"texts": return _text_list(value)
		"uint": return Values.integer(value)
		"map": return typeof(value) == TYPE_DICTIONARY
		"array": return Canonical.is_json_array(value)
		"policy": return (typeof(value) == TYPE_STRING and not value.is_empty()) or typeof(value) == TYPE_DICTIONARY or Canonical.is_json_array(value)
	return false


static func _header(row: Variant, dynamic_item: bool = false) -> Dictionary:
	if typeof(row) != TYPE_DICTIONARY or not Values.def_id(row.get("id")):
		return Result.fail("InvalidArgument", "id")
	if not Values.integer(row.get("schema_version"), 1, 1):
		return Result.fail("InvalidArgument", row.id + ".schema_version")
	if not _has_type(row.get("source_package"), "text"):
		return Result.fail("InvalidArgument", row.id + ".source_package")
	var kind := _type_of(row.id)
	var fields: Dictionary = TYPE_FIELDS.get(kind, {})
	var required: Array = DYNAMIC_FIELDS.keys() if dynamic_item else REQUIRED_FIELDS.get(kind, [])
	for field in required:
		if not row.has(field):
			return Result.fail("InvalidArgument", row.id + "." + field)
	for key in row:
		if typeof(key) != TYPE_STRING:
			return Result.fail("InvalidArgument", row.id)
		var expected: String = fields.get(key, COMMON_FIELDS.get(key, ""))
		if dynamic_item and DYNAMIC_FIELDS.has(key):
			expected = DYNAMIC_FIELDS[key]
		if not _has_type(row[key], expected):
			return Result.fail("InvalidArgument", row.id + "." + key)
	if row.has("skills"):
		if typeof(row.skills) != TYPE_DICTIONARY:
			return Result.fail("InvalidArgument", row.id + ".skills")
		for level in row.skills.values():
			if not Values.integer(level):
				return Result.fail("InvalidArgument", row.id + ".skills")
	return Result.ok()


# Freeze a private copy so callers can safely retain lookup results across ticks.
static func _immutable(value: Variant) -> Variant:
	if Canonical.is_nul_text(value):
		return Canonical.nul_text(value)
	if typeof(value) == TYPE_ARRAY:
		var array := []
		for item in value:
			array.append(_immutable(item))
		array.make_read_only()
		return array
	if typeof(value) == TYPE_DICTIONARY:
		var object := {}
		for key in value:
			object[key] = _immutable(value[key])
		object.make_read_only()
		return object
	return value


static func _ref(defs: Dictionary, target: Variant, kind: String, field: String) -> Dictionary:
	if not Values.def_id(target) or (not kind.is_empty() and _type_of(target) != kind):
		return _failure("InvalidArgument", field, target)
	if not defs.has(target):
		return _failure("NotFound", field, target)
	return Result.ok()


static func _references(row: Dictionary, defs: Dictionary, graph: Dictionary) -> Dictionary:
	var id: String = row.id
	var outgoing := []
	for key: String in SINGLE_REFS:
		if row.has(key):
			var res := _ref(defs, row[key], SINGLE_REFS[key], id + "." + key)
			if not res.ok:
				return res
	for key: String in LIST_REFS:
		if not row.has(key):
			continue
		var targets: Variant = row[key]
		if not Canonical.is_json_array(targets):
			return Result.fail("InvalidArgument", id + "." + key)
		for target in targets:
			var res := _ref(defs, target, LIST_REFS[key], id + "." + key)
			if not res.ok:
				return res
			if key in ["prerequisite_ids","prerequisites"]:
				outgoing.append(target)
	var upgrades: Variant = row.get("upgrade_edges", [])
	if not Canonical.is_json_array(upgrades):
		return Result.fail("InvalidArgument", id + ".upgrade_edges")
	for index in upgrades.size():
		var edge: Variant = upgrades[index]
		var path := "%s.upgrade_edges[%d]" % [id, index]
		if typeof(edge) != TYPE_DICTIONARY:
			return Result.fail("InvalidArgument", path)
		for field in edge:
			if field not in ["target_id", "xp", "gold"]:
				return Result.fail("InvalidArgument", path + "." + str(field))
		for cost in ["xp", "gold"]:
			if not Values.integer(edge.get(cost, 0)):
				return Result.fail("InvalidArgument", path + "." + cost)
		var res := _ref(defs, edge.get("target_id"), "troop", path + ".target_id")
		if not res.ok:
			return res
		outgoing.append(edge.target_id)
	var windows: Variant = row.get("active_windows", [])
	if not Canonical.is_json_array(windows):
		return Result.fail("InvalidArgument", id + ".active_windows")
	for window in windows:
		if not Canonical.is_json_array(window) or window.size() != 2 or not Values.integer(window[0]) or not Values.integer(window[1]) or window[0] >= window[1] or window[1] > row.get("duration_ticks", 0):
			return Result.fail("InvalidArgument", id + ".active_windows")
	var slots: Variant = row.get("slots", {})
	if typeof(slots) != TYPE_DICTIONARY:
		return Result.fail("InvalidArgument", id + ".slots")
	for key in slots:
		var item: Variant = slots[key]
		var res := _ref(defs, item, "item", id + ".slots." + key)
		if not res.ok:
			return res
		if key not in defs[item].get("slot_tags", []):
			return _failure("Conflict", id + ".slots." + key, item)
	graph[id] = outgoing
	return Result.ok()


# Iterative DFS preserves the failing path even for long mod-supplied upgrade trees.
static func _check_graph(graph: Dictionary) -> Dictionary:
	var finished := {}
	for start in graph:
		if finished.has(start):
			continue
		var stack := [start]
		var next := [0]
		var visiting := {start: 0}
		while not stack.is_empty():
			var id: String = stack.back()
			var index: int = next.back()
			if index == graph[id].size():
				finished[id] = true
				visiting.erase(id)
				stack.pop_back()
				next.pop_back()
				continue
			next[-1] = index + 1
			var target: String = graph[id][index]
			if visiting.has(target):
				var cycle := stack.slice(visiting[target])
				cycle.append(target)
				return _failure("Conflict", id + ".cycle", cycle)
			if not finished.has(target):
				visiting[target] = stack.size()
				stack.append(target)
				next.append(0)
	return Result.ok()


static func _validate_all(defs: Dictionary, ids: Array) -> Dictionary:
	var graph := {}
	for id in ids:
		var checked := _references(defs[id], defs, graph)
		if not checked.ok:
			return checked
	return _check_graph(graph)


func build(rows: Array) -> Dictionary:
	if _published:
		return Result.fail("InvalidState", "registry")
	if not Canonical.is_json_array(rows) or rows.size() > Canonical.MAX_ITEMS:
		return Result.fail("InvalidArgument", "definitions")
	var defs := {}
	for input in rows:
		var header := _header(input)
		if not header.ok:
			return header
		if defs.has(input.id):
			return _failure("Conflict", "id", input.id)
		var checked := Canonical.encode(input)
		if not checked.ok:
			return _failure("InvalidArgument", input.id, checked.error)
		defs[input.id] = _immutable(input)
	var ids := defs.keys()
	ids.sort()
	var valid := _validate_all(defs, ids)
	if not valid.ok:
		return valid
	for index in ids.size():
		var id: String = ids[index]
		var kind := _type_of(id)
		_indices[id] = index
		if not _by_tag.has(kind):
			_by_tag[kind] = {"": []}
		var bucket: Dictionary = _by_tag[kind]
		bucket[""].append(defs[id])
		for tag in defs[id].get("tags", []):
			if not bucket.has(tag):
				bucket[tag] = []
			if bucket[tag].is_empty() or bucket[tag].back().id != id:
				bucket[tag].append(defs[id])
	_definitions = defs
	_published = true
	return Result.ok()


func validate_references() -> Dictionary:
	if not _published:
		return Result.fail("InvalidState", "registry")
	return _validate_all(_definitions, _indices.keys())


func get_definition(id: String, expected_type: String = "") -> Dictionary:
	if not _published:
		return Result.fail("InvalidState", "registry")
	var checked := _ref(_definitions, id, expected_type, "id")
	if not checked.ok:
		return checked
	return Result.ok(_definitions[id])


func resolve_index(id: String, expected_type: String = "") -> Dictionary:
	var checked := get_definition(id, expected_type)
	if not checked.ok:
		return checked
	return Result.ok(_indices[id])


func list_by_tag(kind: String, tags: Array = []) -> Array:
	var matches := []
	if _text_list(tags):
		var bucket: Dictionary = _by_tag.get(kind, {})
		for row in bucket.get("" if tags.is_empty() else tags[0], []):
			var all_match := true
			for tag in tags:
				if tag not in row.get("tags", []):
					all_match = false
					break
			if all_match:
				matches.append(row)
	matches.make_read_only()
	return matches


func validate_dynamic_definition(definition: Dictionary, world_overlay: Dictionary) -> Dictionary:
	if not _published:
		return Result.fail("InvalidState", "registry")
	var header := _header(definition, true)
	if not header.ok:
		return header
	var id: String = definition.id
	if _type_of(id) != "item" or _definitions.has(id):
		return _failure("Conflict", "id", id)
	if world_overlay.has(id) and world_overlay[id] != definition:
		return _failure("Conflict", "id", id)
	if not Canonical.is_json_array(definition.get("part_ids")) or definition.part_ids.is_empty():
		return Result.fail("InvalidArgument", id + ".part_ids")
	if typeof(definition.get("rule_snapshot")) != TYPE_DICTIONARY or definition.rule_snapshot.is_empty():
		return Result.fail("InvalidArgument", id + ".rule_snapshot")
	var checked := Canonical.encode(definition)
	if not checked.ok:
		return Result.fail("InvalidArgument", id)
	return _references(definition, _definitions, {})
