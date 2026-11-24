extends RefCounted
const C = preload("res://contracts/canonical.gd")
const F = preload("res://infrastructure/content/package_files.gd")
const V = preload("res://contracts/values.gd")
const R = preload("res://contracts/result.gd")

var _writes := {}

func apply(rows: Dictionary, patch: Variant, package: String) -> Dictionary:
	if typeof(patch) != TYPE_DICTIONARY or not V.def_id(patch.get("def_id")) or patch.get("op") not in ["add","replace","remove"]:
		return F.fail("InvalidArgument", package, "patch")
	for key in patch:
		if key not in ["op","def_id","path","value","source"]:
			return F.fail("InvalidArgument",package,key)
	if patch.get("source", package) != package or patch.has("value") == (patch.op == "remove"):
		return F.fail("InvalidArgument",package,"source/value")
	var parts: Variant = patch.get("path")
	if not C.is_json_array(parts):
		return F.fail("InvalidArgument",package,"path")
	for key in parts:
		if not F.identifier(key):
			return F.fail("InvalidArgument",package,"path")
	if not parts.is_empty() and parts[0] in ["id","schema_version","source_package"]:
		return F.fail("InvalidArgument",package,parts[0])
	var id: String = patch.def_id
	var path := "/".join(parts)
	var previous: Dictionary = _writes.get(id,{})
	for other: String in previous:
		if previous[other] != package and (path == other or path.is_empty() or other.is_empty() or path.begins_with(other+"/") or other.begins_with(path+"/")):
			return F.fail("Conflict", package, [previous[other], id, path])
	var parent: Variant = rows
	var key: String = id
	if not parts.is_empty():
		parent = rows.get(id)
		for i in range(parts.size()-1):
			if typeof(parent) != TYPE_DICTIONARY:
				return F.fail("NotFound", package, [id,path])
			parent = parent.get(parts[i])
		key = parts[-1]
	if typeof(parent) != TYPE_DICTIONARY or parent.has(key) == (patch.op == "add"):
		return F.fail("Conflict", package,[id,path])
	if patch.op == "remove":
		parent.erase(key)
	else:
		if parts.is_empty():
			if typeof(patch.value) != TYPE_DICTIONARY or patch.value.get("id") != id:
				return F.fail("InvalidArgument", package, id)
			var replacement: Dictionary = patch.value.duplicate(true)
			var owner: String = rows[id].source_package if rows.has(id) else package
			if id.get_slice(":",0) != owner or replacement.get("source_package",owner) != owner:
				return F.fail("Conflict",package,id)
			replacement["source_package"] = owner
			parent[key] = replacement
		else:
			parent[key] = patch.value
	previous[path] = package
	_writes[id] = previous
	return R.ok()
