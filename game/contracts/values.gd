extends RefCounted

const R = preload("res://contracts/result.gd")
const MAX_INTEGER := 9007199254740991
const MAX_U32 := 4294967295

static func integer(value: Variant, lower: int = 0, upper: int = MAX_INTEGER) -> bool:
	return typeof(value) == TYPE_INT and value >= lower and value <= upper

static func hex(value: Variant, count: int) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != count:
		return false
	for ch in value:
		if not ch in "0123456789abcdef":
			return false
	return true

static func typed_id(value: Variant, kind: String) -> bool:
	if typeof(value) != TYPE_STRING or not value.begins_with(kind + "/"):
		return false
	var raw: String = value.substr(kind.length() + 1)
	if raw.length() != 36 or raw[14] != "4" or not raw[19] in "89ab":
		return false
	for i in [8, 13, 18, 23]:
		if raw[i] != "-":
			return false
	return hex(raw.replace("-", ""), 32)

static func def_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var sections: PackedStringArray = value.split(":")
	if sections.size() != 2:
		return false
	var path := sections[1].split("/")
	if path.size() != 2:
		return false
	for component in [sections[0], path[0], path[1]]:
		if component.is_empty() or component in [".", ".."]:
			return false
		for ch in component:
			if not ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.":
				return false
	return true

static func millimeters(meters: Variant) -> Dictionary:
	if typeof(meters) not in [TYPE_FLOAT, TYPE_INT]:
		return R.fail("InvalidArgument", "meters")
	var value := roundf(float(meters) * 1000.0)
	if not is_finite(value) or value < -2147483648.0 or value > 2147483647.0:
		return R.fail("InvalidArgument", "meters")
	return R.ok(int(value))

static func yaw_microradians(radians: Variant) -> Dictionary:
	if typeof(radians) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(radians)):
		return R.fail("InvalidArgument", "yaw")
	return R.ok(roundi(wrapf(radians, -PI, PI) * 1000000.0))

static func resolve_handle(mission: String, handle: Variant, current_mission: String, generations: Dictionary) -> Dictionary:
	if typeof(handle) != TYPE_DICTIONARY or handle.size() != 2 or not integer(handle.get("index"), 0, MAX_U32) or not integer(handle.get("generation"), 1, MAX_U32):
		return R.fail("InvalidArgument", "actor_handle")
	if mission != current_mission or generations.get(handle.index) != handle.generation:
		return R.fail("NotFound", "actor_handle")
	return R.ok(handle.index)
