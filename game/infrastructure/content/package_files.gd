extends RefCounted

const C = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")
const MAX_BYTES := 64 * 1024 * 1024

static func fail(code: String, package: String, reason: Variant) -> Dictionary:
	var error := R.fail(code, package)
	error.error.detail = reason
	return error

static func identifier(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value in [".",".."]:
		return false
	for ch in value:
		if ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.":
			return false
	return true

static func relative_file(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty():
		return false
	for segment: String in value.split("/"):
		if not identifier(segment) or segment.ends_with("."):
			return false
		var device := segment.get_slice(".", 0).to_upper()
		if device in ["CON","PRN","AUX","NUL"] or (device.length() == 4 and device.left(3) in ["COM","LPT"] and device[-1] in "123456789"):
			return false
	return true

static func read_bytes(root: String, relative: String) -> Dictionary:
	if not relative_file(relative):
		return fail("InvalidArgument",root,relative)
	var parent := root
	for segment in relative.split("/"):
		var dir := DirAccess.open(parent)
		if dir == null or dir.is_link(segment):
			return fail("InvalidArgument",root,relative)
		parent = parent.path_join(segment)
	var file := FileAccess.open(parent, FileAccess.READ)
	if file == null:
		return fail("NotFound",root,relative)
	var length := file.get_length()
	if length > MAX_BYTES:
		return fail("InvalidArgument",root,relative)
	var bytes := file.get_buffer(length)
	if bytes.size() != length:
		return fail("Unavailable",root,relative)
	return R.ok(bytes)

static func read_json(root: String, relative: String) -> Dictionary:
	var bytes := read_bytes(root, relative)
	if not bytes.ok:
		return bytes
	var parsed := C.decode_source(bytes.value)
	if not parsed.ok:
		return fail("InvalidArgument",root,relative)
	return parsed

static func pack_at(root: String) -> Dictionary:
	var result := read_json(root, "manifest.json")
	if not result.ok:
		return {"scan_error":result}
	var manifest: Variant = result.value
	if typeof(manifest) != TYPE_DICTIONARY or manifest.has("root") or manifest.has("scan_error"):
		return {"scan_error":fail("InvalidArgument", root, "manifest")}
	manifest["root"] = root
	return manifest

static func scan(paths: Array) -> Array:
	var packs := []
	for path in paths:
		if typeof(path) != TYPE_STRING or not path.is_absolute_path() or path.get_slice_count("..") > 1:
			packs.append({"scan_error":fail("InvalidArgument","root",path)})
			continue
		var dir := DirAccess.open(path)
		if dir == null or FileAccess.file_exists(path.path_join("manifest.json")):
			packs.append(pack_at(path))
			continue
		var children := dir.get_directories()
		children.sort()
		var found := false
		for child in children:
			var base: String = path.path_join(child)
			if not dir.is_link(child) and FileAccess.file_exists(base.path_join("manifest.json")):
				found = true
				packs.append(pack_at(base))
		if not found:
			packs.append({"scan_error":fail("NotFound",path,"manifest.json")})
	return packs

static func validate(pack: Dictionary) -> Dictionary:
	if pack.has("scan_error"):
		return fail("InvalidArgument","manifest",pack.get("scan_error"))
	var id: Variant = pack.get("id")
	if not identifier(id) or typeof(pack.get("root")) != TYPE_STRING or not pack.root.is_absolute_path():
		return fail("InvalidArgument","manifest","id/root")
	for key in pack:
		if key not in ["id","root","version","game_api_version","license","requires","conflicts","load_after","entrypoints","config"]:
			return fail("InvalidArgument",id,key)
	if typeof(pack.get("version")) != TYPE_STRING or pack.version.is_empty() or not V.integer(pack.get("game_api_version"),1):
		return fail("InvalidArgument",id,"version")
	if typeof(pack.get("license")) != TYPE_STRING or pack.license.strip_edges().is_empty():
		return fail("InvalidArgument",id,"license")
	for field in ["requires","conflicts","load_after"]:
		if not C.is_json_array(pack.get(field)):
			return fail("InvalidArgument",id,field)
		for value in pack[field]:
			if field == "requires" and typeof(value) == TYPE_DICTIONARY:
				if value.size() == 2 and identifier(value.get("id")) and typeof(value.get("version")) == TYPE_STRING and not value.version.is_empty():
					continue
			if not identifier(value):
				return fail("InvalidArgument",id,field)
	if typeof(pack.get("entrypoints")) != TYPE_DICTIONARY or typeof(pack.get("config",{})) != TYPE_DICTIONARY:
		return fail("InvalidArgument",id,"entrypoints/config")
	for key in pack.entrypoints:
		if key not in ["definitions","resources","patches"] or not C.is_json_array(pack.entrypoints[key]):
			return fail("InvalidArgument",id,key)
		var seen := {}
		for path in pack.entrypoints[key]:
			if not relative_file(path) or seen.has(path):
				return fail("InvalidArgument",id,path)
			seen[path] = true
	return R.ok()
