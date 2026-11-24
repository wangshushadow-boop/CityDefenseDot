extends SceneTree

const Schema = preload("res://contracts/schema.gd")
const Canonical = preload("res://contracts/canonical.gd")
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr(message)


func _initialize() -> void:
	var decoded := {}
	for filename in DirAccess.get_files_at("res://inputs"):
		var kind := filename.get_basename()
		var wire := FileAccess.get_file_as_bytes("res://inputs/" + filename)
		var value := Schema.decode_value(kind, wire)
		check(value.ok, "decode " + kind)
		if not value.ok:
			continue
		decoded[kind] = value.value
		var encoded := Schema.encode_value(kind, value.value)
		check(encoded.ok and encoded.value == wire, "encode " + kind)
		if encoded.ok:
			var output := FileAccess.open("res://outputs/" + filename, FileAccess.WRITE)
			output.store_buffer(encoded.value)
			output.close()

	check(decoded.size() == Schema.SHAPES.size(), "fixtures cover all public schemas")
	for kind in Schema.SHAPES:
		check(decoded.has(kind), "missing fixture " + kind)
	if failures.is_empty():
		check(Schema.validate_settlement(decoded.EncounterSpec, decoded.MissionResult).ok,
				"source slot at the upper uint32 boundary")
		check(decoded.MoveIntent.speed_fraction == 0.5, "domain speed")
		check(decoded.IntentBatch.inputs[0].speed_fraction == 0.5, "nested domain speed")
		check(decoded.MoveIntent.is_read_only() and decoded.MoveIntent.actor_handle.is_read_only()
				and decoded.MoveIntent.desired_direction.is_read_only(), "deeply immutable intent")
		check(decoded.DomainError.field.is_read_only(), "immutable NUL text")
		var invalid := FileAccess.get_file_as_bytes("res://invalid.json")
		check(not Schema.decode_value("CommandReceipt", invalid).ok, "NUL text cannot satisfy an array field")
		var list := []
		list.resize(Canonical.MAX_ITEMS)
		check(Canonical.encode(list).ok, "array length at the limit")
		list.append(null)
		check(not Canonical.encode(list).ok, "array length beyond the limit")
	if failures.is_empty():
		print("P1_SCHEMA_INTEROP PASS ", decoded.size())
	quit(0 if failures.is_empty() else 1)
