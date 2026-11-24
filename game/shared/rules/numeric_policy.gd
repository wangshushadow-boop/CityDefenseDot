extends RefCounted
## Pure generic calculations. Specific prices and combat formulas belong to their domains.
const R = preload("res://contracts/result.gd")
const V = preload("res://contracts/values.gd")

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) and absf(float(value)) <= V.MAX_INTEGER

static func _ratio(value: Variant) -> bool:
	return typeof(value) == TYPE_DICTIONARY and V.integer(value.get("numerator")) and V.integer(value.get("denominator"), 1)

static func round_money(value: Variant, direction: String) -> Dictionary:
	if direction not in ["buy", "sell"]:
		return R.fail("InvalidArgument", "direction")
	if _ratio(value):
		var n: int = value.numerator
		var d: int = value.denominator
		@warning_ignore("integer_division")
		var units: int = n / d
		return R.ok(units + int(direction == "buy" and n % d != 0))
	if not _number(value) or value < 0:
		return R.fail("InvalidArgument", "amount")
	return R.ok(ceili(value) if direction == "buy" else floori(value))

static func validate_config(rule_key: String, config: Dictionary) -> Dictionary:
	if rule_key == "chance":
		return R.ok() if _ratio(config) and config.numerator <= config.denominator else R.fail("InvalidArgument","chance")
	if rule_key != "effects":
		return R.fail("NotFound", "rule_key")
	var low: Variant = config.get("min", -V.MAX_INTEGER)
	var high: Variant = config.get("max", V.MAX_INTEGER)
	if not _number(low) or not _number(high) or low > high or not V.integer(config.get("version", 1), 1):
		return R.fail("InvalidArgument", "bounds")
	return R.ok()

static func _priority(a: Dictionary, b: Dictionary) -> bool:
	if a.priority != b.priority:
		return a.priority > b.priority
	return a.source_id < b.source_id

static func apply_effects(base: Variant, modifiers: Array, scope: String, config: Dictionary = {}) -> Dictionary:
	var valid := validate_config("effects", config)
	if not valid.ok:
		return valid
	if not _number(base) or scope.is_empty():
		return R.fail("InvalidArgument", "base_or_scope")
	var candidates: Array[Dictionary] = []
	var seen := {}
	for entry in modifiers:
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("source_id")) != TYPE_STRING or entry.source_id.is_empty():
			return R.fail("InvalidArgument", "source_id")
		if typeof(entry.get("scope")) != TYPE_STRING or typeof(entry.get("group")) != TYPE_STRING or not V.integer(entry.get("priority"), -V.MAX_INTEGER):
			return R.fail("InvalidArgument", "modifier")
		if entry.get("operation") not in ["add","multiply"]:
			return R.fail("InvalidArgument", "operation")
		if entry.operation == "add" and not _number(entry.get("value")) or entry.operation == "multiply" and not _ratio(entry.get("value")):
			return R.fail("InvalidArgument", "value")
		if entry.scope != scope:
			continue
		if seen.has(entry.source_id):
			return R.fail("Conflict", "source_id")
		seen[entry.source_id] = true
		candidates.append(entry)
	candidates.sort_custom(_priority)
	var groups := {}
	var selected: Array[Dictionary] = []
	for entry in candidates:
		if not entry.group.is_empty():
			if groups.has(entry.group):
				continue
			groups[entry.group] = entry.source_id
		selected.append(entry)
	var current: float = float(base)
	var steps := []
	for op in ["add", "multiply"]:
		for entry in selected:
			if entry.operation != op:
				continue
			var before := current
			if op == "add":
				current += entry.value
			else:
				current *= float(entry.value.numerator) / entry.value.denominator
			if not _number(current):
				return R.fail("InvalidArgument", "overflow")
			steps.append({"source_id":entry.source_id,"operation":op,"before":before,"after":current})
	var final := clampf(current, config.get("min", -V.MAX_INTEGER), config.get("max", V.MAX_INTEGER))
	return R.ok({"base":base,"steps":steps,"final":final,"clamped":final != current,"config_version":config.get("version",1)})

static func evaluate(rule_key: String, input: Dictionary, config: Dictionary, rng: Variant = null) -> Dictionary:
	var valid := validate_config(rule_key, config)
	if not valid.ok:
		return valid
	if rule_key == "effects":
		if typeof(input.get("modifiers")) != TYPE_ARRAY or typeof(input.get("scope")) != TYPE_STRING:
			return R.fail("InvalidArgument","input")
		return apply_effects(input.get("base"),input.modifiers,input.scope,config)
	if rng == null or typeof(rng) != TYPE_OBJECT or not rng.has_method("next_u32"):
		return R.fail("InvalidArgument","rng")
	var roll: Variant = rng.next_u32()
	if not V.integer(roll,0,0xffffffff):
		return R.fail("InvalidState","rng")
	return R.ok(float(roll) / 4294967296.0 < float(config.numerator) / config.denominator)
