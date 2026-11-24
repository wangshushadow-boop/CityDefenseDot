extends "res://contracts/ports/content_port.gd"

const C = preload("res://contracts/canonical.gd")
const V = preload("res://contracts/values.gd")
const F = preload("res://infrastructure/content/package_files.gd")
const Patches = preload("res://infrastructure/content/patch_set.gd")
const Registry = preload("res://shared/definitions/registry.gd")
const BASE_PACKAGE := "res://infrastructure/content/base"
const EXTENSIONS := ["world","rule","quest","dialogue","mission","formation","tactic","ui"]
var _extensions := {}


func scan_packages(paths: Array) -> Array:
	return F.scan(paths)


func validate_package(package: Dictionary) -> Dictionary:
	return F.validate(package)


func resolve_packages(selection: Array, game_api: int) -> Dictionary:
	if selection.is_empty() or selection.size() > 1024:
		return Result.fail("InvalidArgument","packages")
	var packs := {}
	var deps := {}
	for pack in selection:
		if typeof(pack) != TYPE_DICTIONARY:
			return Result.fail("InvalidArgument","manifest")
		var checked := validate_package(pack)
		if not checked.ok:
			return checked
		if packs.has(pack.id):
			return F.fail("Conflict",pack.id,"id")
		if pack.game_api_version != game_api:
			return F.fail("StaleVersion",pack.id,"game_api_version")
		packs[pack.id] = pack
	for pack: Dictionary in packs.values():
		var after := {}
		for entry in pack.requires:
			var id: String = entry if typeof(entry) == TYPE_STRING else entry.id
			if not packs.has(id):
				return F.fail("NotFound",pack.id,id)
			if typeof(entry) == TYPE_DICTIONARY and packs[id].version != entry.version:
				return F.fail("StaleVersion",pack.id,id)
			after[id] = true
		for id in pack.conflicts:
			if packs.has(id):
				return F.fail("Conflict",pack.id,id)
		for id in pack.load_after:
			if packs.has(id):
				after[id] = true
		deps[pack.id] = after
	var remaining := packs.keys()
	remaining.sort()
	var order := []
	while not remaining.is_empty():
		var ready := ""
		for id: String in remaining:
			if deps[id].is_empty():
				ready = id
				break
		if ready.is_empty():
			return F.fail("Conflict",remaining[0],{"cycle":remaining})
		order.append(packs[ready])
		remaining.erase(ready)
		for id in remaining:
			deps[id].erase(ready)
	return Result.ok(order)


static func _immutable(value: Variant) -> Variant:
	if C.is_nul_text(value):
		return C.nul_text(value)
	if typeof(value) == TYPE_ARRAY:
		var entries := []
		for item in value:
			entries.append(_immutable(item))
		entries.make_read_only()
		return entries
	if typeof(value) == TYPE_DICTIONARY:
		var result := {}
		for key in value:
			result[key] = _immutable(value[key])
		result.make_read_only()
		return result
	return value


static func _read_entries(pack: Dictionary, rows: Dictionary, patch_set: RefCounted) -> Dictionary:
	for group in ["definitions","patches"]:
		for path in pack.entrypoints.get(group,[]):
			var loaded := F.read_json(pack.root,path)
			if not loaded.ok or not C.is_json_array(loaded.value):
				return F.fail("InvalidArgument",pack.id,path)
			for row in loaded.value:
				if group == "patches":
					var applied: Dictionary = patch_set.apply(rows,row,pack.id)
					if not applied.ok:
						return applied
				else:
					if typeof(row) != TYPE_DICTIONARY or not V.def_id(row.get("id")):
						return F.fail("InvalidArgument",pack.id,path)
					if row.id.get_slice(":",0) != pack.id or row.get("source_package",pack.id) != pack.id or rows.has(row.id):
						return F.fail("Conflict",pack.id,row.id)
					row["source_package"] = pack.id
					rows[row.id] = row
	return Result.ok()


static func _read_resources(pack: Dictionary, resources: Dictionary, markers: Dictionary) -> Dictionary:
	for path: String in pack.entrypoints.get("resources", []):
		var file := F.read_bytes(pack.root,path)
		if not file.ok:
			return F.fail("NotFound",pack.id,path)
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA256)
		h.update(file.value)
		var key: String = pack.id + "/" + path
		resources[key] = h.finish().hex_encode()
		if path.ends_with(".scene.json"):
			var parsed := C.decode_source(file.value)
			if not parsed.ok or typeof(parsed.value) != TYPE_DICTIONARY or not C.is_json_array(parsed.value.get("markers")):
				return F.fail("InvalidArgument",pack.id,path)
			var found := {}
			for marker in parsed.value.markers:
				if typeof(marker) != TYPE_DICTIONARY or not F.identifier(marker.get("id")) or not F.identifier(marker.get("kind")) or found.has(marker.id):
					return F.fail("InvalidArgument",pack.id,path)
				var position: Variant = marker.get("position_mm")
				if not C.is_json_array(position) or position.size() != 3:
					return F.fail("InvalidArgument",pack.id,path)
				for axis in position:
					if not V.integer(axis,-2147483648,2147483647):
						return F.fail("InvalidArgument",pack.id,path)
				found[marker.id] = marker.kind
			markers[key] = found
	return Result.ok()


static func _asset_refs(rows: Array, resources: Dictionary, markers: Dictionary) -> Dictionary:
	for row: Dictionary in rows:
		var asset: Variant = row.get("asset_ref")
		var key: String = row.source_package + "/" + asset if typeof(asset) == TYPE_STRING else ""
		if row.has("asset_ref") and not resources.has(key):
			return F.fail("NotFound",row.source_package,[row.id,"asset_ref"])
		if row.id.get_slice(":",1).get_slice("/",0) != "scene":
			continue
		var points: Dictionary = markers.get(key,{})
		for field: String in ["spawn_zones","objectives"]:
			var refs: Variant = row.get(field)
			var kind := "spawn" if field == "spawn_zones" else "objective"
			if not C.is_json_array(refs) or refs.is_empty():
				return F.fail("InvalidArgument",row.source_package,[row.id,field])
			for ref in refs:
				if not F.identifier(ref) or points.get(ref) != kind:
					return F.fail("NotFound",row.source_package,[row.id,field,ref])
	return Result.ok()


static func _config(values: Variant, source: String, config: Dictionary, sources: Dictionary, declared: bool) -> Dictionary:
	if typeof(values) != TYPE_DICTIONARY or not C.encode(values).ok:
		return F.fail("InvalidArgument",source,"config")
	for key in values:
		if key == "battle_limit" and not V.integer(values[key], 1):
			return F.fail("InvalidArgument",source,key)
		if declared and not config.has(key):
			return F.fail("InvalidArgument",source,key)
		if config.has(key) and _config_kind(config[key]) != _config_kind(values[key]):
			return F.fail("InvalidArgument",source,key)
		config[key] = values[key]
		sources[key] = source
	return Result.ok()


static func _config_kind(value: Variant) -> int:
	return TYPE_STRING if C.is_text(value) else typeof(value)


func compile(order: Array, overrides: Dictionary) -> Dictionary:
	var resolved := resolve_packages(order,VERSION)
	if not resolved.ok:
		return resolved
	var rows := {}
	var resources := {}
	var markers := {}
	var config := {}
	var sources := {}
	var packages := []
	var patch_set := Patches.new()
	for pack: Dictionary in resolved.value:
		var entries := _read_entries(pack, rows, patch_set)
		if not entries.ok:
			return entries
		var files := _read_resources(pack,resources,markers)
		if not files.ok:
			return files
		var merged := _config(pack.get("config",{}).duplicate(true), pack.id, config, sources, false)
		if not merged.ok:
			return merged
		packages.append({"id":pack.id,"version":pack.version})
	var updated := _config(overrides.duplicate(true),"session",config,sources,true)
	if not updated.ok:
		return updated
	var ids := rows.keys()
	ids.sort()
	var definitions := []
	for id in ids:
		definitions.append(rows[id])
	var registry := Registry.new()
	var built := registry.build(definitions)
	if not built.ok:
		return built
	var located := _asset_refs(definitions,resources,markers)
	if not located.ok:
		return located
	var keys := _extensions.keys()
	keys.sort()
	var digest := C.hash_value({"game_api_version":VERSION,"packages":packages,"definitions":definitions,"resources":resources,"config":config,"extension_points":keys})
	if not digest.ok:
		return digest
	var compiled := {"game_api_version":VERSION,"packages":packages,"registry":registry,"resources":resources,
		"hash":digest.value,"content_hash":digest.value,"config":config,"config_provenance":sources,"extension_points":keys}
	return Result.ok(_immutable(compiled))


func _register_trusted_extension(key: String, implementation: Variant) -> Dictionary:
	var category := key.get_slice(".",0)
	if category not in EXTENSIONS or not F.identifier(key) or not implementation is Callable or not implementation.is_valid():
		return Result.fail("InvalidArgument","extension")
	if _extensions.has(key):
		return Result.fail("Conflict",key)
	_extensions[key] = implementation
	return Result.ok()


func get_extension(key: String) -> Dictionary:
	if not _extensions.has(key):
		return Result.fail("NotFound",key)
	return Result.ok(_extensions[key])


func check_save_or_network_compatibility(manifest: Dictionary, compiled: Dictionary) -> Dictionary:
	if not V.integer(compiled.get("game_api_version"),VERSION,VERSION) or not V.hex(compiled.get("hash"),64):
		return Result.fail("InvalidArgument","compiled")
	if not V.integer(manifest.get("game_api_version"),VERSION,VERSION):
		return F.fail("StaleVersion","game_api_version",VERSION)
	if manifest.has("packages") and manifest.packages != compiled.get("packages"):
		return F.fail("Conflict","packages",compiled.get("packages"))
	if manifest.get("content_hash") != compiled.hash:
		return F.fail("Conflict","content_hash",compiled.hash)
	return Result.ok()
