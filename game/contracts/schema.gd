extends RefCounted

const R = preload("res://contracts/result.gd")
const C = preload("res://contracts/canonical.gd")
const V = preload("res://contracts/values.gd")

# Payload semantics belong to the receiving domain. All fields, including
# nullable ones, are present on the canonical wire as required by ADR-012.
const SHAPES := {
	"CommandEnvelope": {"command_id":"id","actor_ref":"id","scope_id":"id","expected_revision":"uint?","issued_tick":"uint?","sequence":"uint?","payload":"map"},
	"CommandReceipt": {"command_id":"id","status":"id","committed_revision":"uint?","errors":"*DomainError","view_changes":"array"},
	"DomainError": {"code":"error","message_key":"id","field":"text?","detail":"any?","retryable":"bool"},
	"QueryEnvelope": {"scope_id":"id","visibility_context":"map","payload":"map"},
	"ReadModel": {"scope_id":"id","revision":"uint","tick":"uint?","content_hash":"hash","data":"any"},
	"EventEnvelope": {"event_id":"id","scope_id":"id","revision":"uint","tick":"uint?","type":"id","payload":"map"},
	"SnapshotStamp": {"scope_id":"id","revision":"uint","tick":"uint?","nav_revision":"uint?"},
	"ChangeSet": {"expected_versions":"array","operations":"array","invariant_checks":"array","committed_events":"*EventEnvelope"},
	"IntentBatch": {"mission_id":"id","source_tick":"uint","control_revision":"uint","inputs":"*intent"},
	"AgentHandle": {"index":"u32","generation":"generation"},
	"MoveIntent": {"actor_handle":"AgentHandle","desired_direction":"vector","speed_fraction":"fraction","stance":"id?"},
	"LookIntent": {"actor_handle":"AgentHandle","yaw":"integer","pitch":"integer"},
	"AttackIntent": {"actor_handle":"AgentHandle","input_phase":"id","direction":"id","weapon_slot":"u32","target_hint":"AgentHandle?"},
	"BlockIntent": {"actor_handle":"AgentHandle","direction":"id","held":"bool"},
	"EquipIntent": {"actor_handle":"AgentHandle","slot":"u32","item_ref":"id?"},
	"InteractionIntent": {"actor_handle":"AgentHandle","target_ref":"id","action":"id"},
	"EncounterSpec": {"schema_version":"v1","encounter_id":"encounter","reservation_revision":"uint","mode":"id","scene_def_id":"def","ruleset_id":"def","environment":"map","rng_seed":"seed","sides":"*Side","reserved_sources":"*ReservedSource","battle_limit":"positive","deployment_constraints":"map","siege_snapshot":"map?"},
	"Side": {"team_key":"key","faction_id":"id","commander_hero_id":"hero?","roster_allocations":"array"},
	"ReservedSource": {"source_party_id":"party","troop_def_id":"def?","hero_id":"hero?","count":"positive","source_slot_range":"range","loadout_snapshot_id":"id"},
	"MissionResult": {"schema_version":"v1","result_id":"id","encounter_id":"encounter?","mission_id":"id","reservation_revision":"uint?","outcome":"id","duration_ticks":"uint","winner_team_keys":"*key","objective_results":"array","slot_outcomes":"*SlotOutcome","loot_claims":"array","hero_outcomes":"array","siege_changes":"map?","reward_intents":"array","stats":"map","integrity_hash":"hash"},
	"SlotOutcome": {"source_slot_id":"u32","end_status":"status","wounded":"bool","captor_team_key":"key?","xp":"uint"},
	"FormationOrder": {"mission_id":"id","order_id":"id","issuer_id":"id","client_sequence":"uint","issued_tick":"uint","formation_ids":"*u32","order_type":"id","target_position":"vector?","target_formation_id":"u32?","parameters":"map"},
	"Handshake": {"protocol_version":"uint","content_api_version":"uint","content_hash":"hash"},
	"SaveHeader": {"schema_version":"v1","game_minute":"uint"},
}
const SPEED_SCALE := 1_000_000
const INTENT_FIELDS := {"speed_fraction":"MoveIntent", "yaw":"LookIntent", "input_phase":"AttackIntent", "held":"BlockIntent", "slot":"EquipIntent", "action":"InteractionIntent"}
const ERRORS := ["InvalidArgument","Unauthorized","InsufficientResource","InvalidState","StaleVersion","NotFound","Conflict","Unavailable"]
const SLOT_STATES := ["alive","wounded","dead","captured","withdrawn","not_spawned"]

static func _identifier(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty():
		return false
	for i in value.length():
		var cp: int = value.unicode_at(i)
		if cp < 32 or (cp >= 127 and cp <= 159):
			return false
	return true

static func _accept(kind: String, value: Variant) -> bool:
	match kind:
		"any": return true
		"bool": return typeof(value) == TYPE_BOOL
		"map": return typeof(value) == TYPE_DICTIONARY
		"array": return C.is_json_array(value)
		"key": return _identifier(value) or V.integer(value, 0, V.MAX_U32)
		"text": return C.is_text(value)
		"id": return _identifier(value)
		"def": return V.def_id(value)
		"hero", "party", "encounter": return V.typed_id(value, kind)
		"u32": return V.integer(value, 0, V.MAX_U32)
		"generation": return V.integer(value, 1, V.MAX_U32)
		"uint": return V.integer(value)
		"integer": return V.integer(value, -V.MAX_INTEGER)
		"positive": return V.integer(value, 1)
		"v1": return V.integer(value, 1, 1)
		"hash": return V.hex(value, 64)
		"seed": return V.hex(value, 16) or V.integer(value)
		"error": return typeof(value) == TYPE_STRING and value in ERRORS
		"status": return typeof(value) == TYPE_STRING and value in SLOT_STATES
		"fraction": return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value >= 0 and value <= 1
		"range": return C.is_json_array(value) and value.size() == 2 and V.integer(value[0], 0, V.MAX_U32) and V.integer(value[1], 1, V.MAX_U32 + 1) and value[0] < value[1]
		"vector":
			return C.is_json_array(value) and value.size() == 3 and value.all(func(n): return V.integer(n, -2147483648, 2147483647))
	return false

static func _field(spec: String, value: Variant, path: String) -> Dictionary:
	if C.is_json_array(value) and value.size() > C.MAX_ITEMS:
		return R.fail("InvalidArgument",path)
	var kind := spec.trim_suffix("?")
	if spec != kind and value == null:
		return R.ok()
	if kind.begins_with("*") and C.is_json_array(value):
		for i in value.size():
			var item := _field(kind.substr(1), value[i], "%s[%d]" % [path,i])
			if not item.ok:
				return item
		return R.ok()
	if kind == "intent" and typeof(value) == TYPE_DICTIONARY:
		for field: String in INTENT_FIELDS:
			if value.has(field):
				return _field(INTENT_FIELDS[field],value,path)
	if SHAPES.has(kind) and typeof(value) == TYPE_DICTIONARY:
		var fields: Dictionary = SHAPES[kind]
		for key in value:
			if not fields.has(key):
				return R.fail("InvalidArgument", path + "." + str(key))
		for key: String in fields:
			if not value.has(key):
				return R.fail("InvalidArgument", path + "." + key)
			var child := _field(fields[key], value[key], path + "." + key)
			if not child.ok:
				return child
		return R.ok()
	if _accept(kind,value):
		return R.ok()
	return R.fail("StaleVersion" if kind == "v1" and typeof(value) == TYPE_INT else "InvalidArgument", path)

# Copy every container and close every writable reference, including text with NUL.
static func _freeze(value: Variant) -> Variant:
	if C.is_nul_text(value):
		return C.nul_text(value)
	if typeof(value) == TYPE_DICTIONARY:
		var result := {}
		for key in value:
			result[key] = _freeze(value[key])
		result.make_read_only()
		return result
	if typeof(value) == TYPE_ARRAY:
		var result := []
		for item in value:
			result.append(_freeze(item))
		result.make_read_only()
		return result
	return value

static func _convert_speed(kind: String, value: Variant, to_wire: bool) -> Dictionary:
	if kind not in ["MoveIntent", "IntentBatch"]:
		return R.ok(value)
	if typeof(value) != TYPE_DICTIONARY:
		return R.fail("InvalidArgument", kind)
	if kind == "IntentBatch":
		var inputs: Variant = value.get("inputs")
		if not C.is_json_array(inputs) or inputs.size() > C.MAX_ITEMS:
			return R.fail("InvalidArgument","inputs")
		var items := []
		for input in inputs:
			if typeof(input) == TYPE_DICTIONARY and input.has("speed_fraction"):
				var move := _convert_speed("MoveIntent", input, to_wire)
				if not move.ok:
					return move
				items.append(move.value)
			else:
				items.append(input)
		var batch: Dictionary = value.duplicate()
		batch["inputs"] = items
		return R.ok(batch)
	var fraction: Variant = value.get("speed_fraction")
	if to_wire and not _accept("fraction",fraction):
		return R.fail("InvalidArgument","speed_fraction")
	if not to_wire and not V.integer(fraction, 0, SPEED_SCALE):
		return R.fail("InvalidArgument","speed_fraction")
	var move: Dictionary = value.duplicate()
	if to_wire:
		move["speed_fraction"] = roundi(float(fraction) * SPEED_SCALE)
	else:
		move["speed_fraction"] = float(fraction) / SPEED_SCALE
	return R.ok(move)

static func validate_shape(kind: String, value: Variant, version: Variant = 1) -> Dictionary:
	if typeof(version) != TYPE_INT:
		return R.fail("InvalidArgument", "schema_version")
	if version != 1:
		return R.fail("StaleVersion", "schema_version")
	if not SHAPES.has(kind):
		return R.fail("InvalidArgument", "type")
	var checked := _field(kind, value, kind)
	if not checked.ok:
		return checked
	# Also validate generic payloads before copying. This rejects non-data objects,
	# cyclic container graphs, non-NFC texts and non-portable numeric values.
	var wire := _convert_speed(kind,value,true)
	if not wire.ok:
		return wire
	var encoded := C.encode(wire.value)
	if not encoded.ok:
		return encoded
	if kind == "EncounterSpec":
		var ranges := []
		for source in value.reserved_sources:
			var bounds: Array = source.source_slot_range
			if source.count != bounds[1] - bounds[0] or (source.hero_id != null and source.count != 1):
				return R.fail("InvalidArgument", "reserved_sources.count")
			ranges.append(bounds)
		ranges.sort_custom(func(a,b): return a[0] < b[0])
		for i in range(1,ranges.size()):
			if ranges[i][0] < ranges[i-1][1]:
				return R.fail("Conflict","reserved_sources.source_slot_range")
	elif kind == "MissionResult":
		var seen := {}
		for row in value.slot_outcomes:
			if seen.has(row.source_slot_id):
				return R.fail("Conflict","slot_outcomes.source_slot_id")
			if row.end_status == "not_spawned" and (row.xp != 0 or row.wounded or row.captor_team_key != null):
				return R.fail("InvalidArgument","slot_outcomes.not_spawned")
			seen[row.source_slot_id] = true
		var covered: Dictionary = value.duplicate()
		covered.erase("integrity_hash")
		var digest := C.hash_value(covered)
		if not digest.ok or digest.value != value.integrity_hash:
			return R.fail("Conflict","integrity_hash")
	elif kind == "FormationOrder":
		var seen := {}
		if value.formation_ids.is_empty():
			return R.fail("InvalidArgument","formation_ids")
		for id in value.formation_ids:
			if seen.has(id):
				return R.fail("Conflict","formation_ids")
			seen[id] = true
	return R.ok(_freeze(value))

static func encode_value(kind: String, value: Variant) -> Dictionary:
	var checked := validate_shape(kind,value)
	if not checked.ok:
		return checked
	var wire := _convert_speed(kind,checked.value,true)
	return C.encode(wire.value)

static func decode_value(kind: String, bytes: PackedByteArray, version: Variant = 1) -> Dictionary:
	var parsed := C.decode(bytes)
	if not parsed.ok:
		return parsed
	if typeof(version) != TYPE_INT:
		return R.fail("InvalidArgument","schema_version")
	if kind == "SaveHeader" and version == 0:
		if typeof(parsed.value) != TYPE_DICTIONARY or parsed.value.size() != 2 or not V.integer(parsed.value.get("schema_version"),0,0) or not V.integer(parsed.value.get("minutes")):
			return R.fail("InvalidArgument","SaveHeader.v0")
		return validate_shape(kind, {"schema_version":1, "game_minute":parsed.value.minutes})
	if version != 1:
		return R.fail("StaleVersion","schema_version")
	var domain := _convert_speed(kind,parsed.value,false)
	if not domain.ok:
		return domain
	return validate_shape(kind,domain.value,version)

static func map_error(code: String, args: Dictionary = {}) -> String:
	return R.map_error(code,args)

static func check_compatible(local: Dictionary, remote: Dictionary) -> Dictionary:
	for side in [local,remote]:
		var checked := validate_shape("Handshake",side)
		if not checked.ok:
			return checked
	for field: String in SHAPES.Handshake:
		if local[field] != remote[field]:
			var err := R.fail("StaleVersion",field)
			err.error.detail = local.duplicate(true)
			return err
	return R.ok()

static func validate_settlement(encounter: Dictionary, result: Dictionary) -> Dictionary:
	for pair in [["EncounterSpec",encounter],["MissionResult",result]]:
		var checked := validate_shape(pair[0],pair[1])
		if not checked.ok:
			return checked
	if encounter.encounter_id != result.encounter_id:
		return R.fail("NotFound","encounter_id")
	if encounter.reservation_revision != result.reservation_revision:
		return R.fail("StaleVersion","reservation_revision")
	var ranges := []
	var expected := 0
	for source in encounter.reserved_sources:
		ranges.append(source.source_slot_range)
		expected += source.count
	if expected != result.slot_outcomes.size():
		return R.fail("Conflict", "slot_outcomes")
	ranges.sort_custom(func(a,b): return a[0] < b[0])
	var ids := []
	for row in result.slot_outcomes:
		ids.append(row.source_slot_id)
	ids.sort()
	var i := 0
	for bounds in ranges:
		for slot in range(bounds[0],bounds[1]):
			if ids[i] != slot:
				return R.fail("Conflict","slot_outcomes.source_slot_id")
			i += 1
	return R.ok(_freeze(result))
