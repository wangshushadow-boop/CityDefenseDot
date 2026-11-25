extends RefCounted

const C = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const S = preload("res://contracts/schema.gd")
const V = preload("res://contracts/values.gd")

# The input port supplies native fractions and integer formation keys. Command
# identity uses the v1 integer/string wire representation.
static func prepare(envelope: Dictionary) -> Dictionary:
	var raw: Variant = envelope.get("payload")
	if not raw is Dictionary:
		return R.fail("InvalidArgument","payload")
	var wire: Dictionary = raw.duplicate()
	var batch := {}
	var revisions := {}
	match raw.get("type"):
		"field.input":
			if raw.size()!=2:
				return R.fail("InvalidArgument","field.input")
			var encoded := C.encode(raw.get("batch"))
			if not encoded.ok:
				encoded = S.encode_value("IntentBatch",raw.get("batch"))
			if not encoded.ok:
				return encoded
			var decoded := S.decode_value("IntentBatch",encoded.value)
			if not decoded.ok:
				return decoded
			wire.batch = C.decode(encoded.value).value
			batch = decoded.value
		"field.order":
			if raw.size() != (3 if raw.has("revisions") else 2):
				return R.fail("InvalidArgument","field.order")
			var order := S.validate_shape("FormationOrder",raw.get("order"))
			if not order.ok:
				return order
			if raw.has("revisions"):
				if not raw.revisions is Dictionary:
					return R.fail("InvalidArgument","field.order.revisions")
				var keys := {}
				for key in raw.revisions:
					var id: Variant=key
					if key is String and key.length()<=10 and key.is_valid_int() and str(key.to_int())==key:
						id=key.to_int()
					if not V.integer(id,0,V.MAX_U32) or revisions.has(id) or not V.integer(raw.revisions[key]):
						return R.fail("InvalidArgument","field.order.revisions")
					keys[str(id)] = raw.revisions[key]
					revisions[id] = raw.revisions[key]
				wire.revisions = keys
				revisions.make_read_only()
		"field.deploy":
			if raw.size()!=2 or not C.is_json_array(raw.get("placements")):
				return R.fail("InvalidArgument","field.deploy")
		"field.withdraw":
			if raw.size()!=1:
				return R.fail("InvalidArgument","field.withdraw")
		"field.downed":
			if raw.size()!=2 or raw.get("mode") not in ["spectate","delegate","withdraw"]:
				return R.fail("InvalidArgument","field.downed")
		_:
			return R.fail("InvalidArgument","field.operation")
	var normalized := envelope.duplicate()
	normalized.payload = wire
	var checked := S.validate_shape("CommandEnvelope",normalized)
	if not checked.ok:
		return checked
	var cmd: Dictionary = checked.value
	if cmd.expected_revision==null:
		return R.fail("InvalidArgument","expected_revision")
	var local: Dictionary = cmd.payload.duplicate()
	if raw.type=="field.input":
		if batch.mission_id!=cmd.scope_id:
			return R.fail("Unauthorized","batch.mission_id")
		local.batch=batch
	elif raw.type=="field.order":
		if local.order.mission_id!=cmd.scope_id or local.order.issuer_id!=cmd.actor_ref:
			return R.fail("Unauthorized","order.authority")
		if raw.has("revisions"):
			local.revisions=revisions
	local.scope_id=cmd.scope_id
	local.revision=cmd.expected_revision
	local.make_read_only()
	return R.ok({"cmd":cmd,"local":local})
