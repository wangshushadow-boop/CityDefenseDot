extends RefCounted
const R = preload("res://contracts/result.gd")
const C = preload("res://contracts/canonical.gd")

static func insert(entries: Dictionary, descriptor: Dictionary) -> Dictionary:
	var id: Variant=descriptor.get("id")
	if not C.Reader.valid_key(id) or not C.is_json_array(descriptor.get("requires")) or not descriptor.has("version"):
		return R.fail("InvalidArgument","module")
	var version: Variant=descriptor.version
	if not ((typeof(version)==TYPE_INT and version>0) or (typeof(version)==TYPE_STRING and not version.is_empty())):
		return R.fail("InvalidArgument","version")
	for key in ["factory","shutdown"]:
		if not descriptor.get(key) is Callable or not descriptor[key].is_valid():
			return R.fail("InvalidArgument",key)
	if entries.has(id):
		return R.fail("Conflict",id)
	var seen := {}
	for dependency in descriptor.requires:
		if not C.Reader.valid_key(dependency) or seen.has(dependency):
			return R.fail("InvalidArgument","requires")
		seen[dependency]=true
	entries[id]=descriptor.duplicate(true)
	return R.ok()

static func order(entries: Dictionary) -> Dictionary:
	var result := []
	var done := {}
	var active := []
	var ids := entries.keys()
	ids.sort()
	for id in ids:
		var visited:=_visit(id,entries,result,done,active)
		if not visited.ok:
			return visited
	return R.ok(result)

static func _visit(id: String, entries: Dictionary, result: Array, done: Dictionary, active: Array) -> Dictionary:
	if done.has(id):
		return R.ok()
	if id in active:
		var cycle:=active.slice(active.find(id))
		cycle.append(id)
		var err:=R.fail("Conflict","dependency_cycle")
		err.error.detail=cycle
		return err
	if not entries.has(id):
		var err:=R.fail("Unavailable",id)
		err.error.detail=active.duplicate()
		return err
	active.append(id)
	var dependencies: Array=entries[id].requires.duplicate()
	dependencies.sort()
	for dependency in dependencies:
		var visited:=_visit(dependency,entries,result,done,active)
		if not visited.ok:
			return visited
	active.pop_back()
	done[id]=true
	result.append(id)
	return R.ok()
