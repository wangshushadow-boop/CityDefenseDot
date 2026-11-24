extends SceneTree

const LIMIT := 9007199254740991


func valid_label(value: String) -> bool:
	# This subset is closed under NFC. It intentionally has no combining marks or Jamo.
	for i in value.length():
		var cp := value.unicode_at(i)
		if not (cp >= 32 and cp <= 126 or cp >= 0x4e00 and cp <= 0x9fff or cp == 0xe9):
			return false
	return true


func canonical_input(bytes: PackedByteArray) -> Dictionary:
	var parsed := JSON.new()
	if parsed.parse(bytes.get_string_from_utf8()) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		return {}
	var fields: Dictionary = parsed.data
	if fields.size() != 3 or not fields.has_all(["delta", "enabled", "label"]):
		return {}
	if typeof(fields.enabled) != TYPE_BOOL or typeof(fields.label) != TYPE_STRING or not valid_label(fields.label):
		return {}
	var n: Variant = fields.delta
	if typeof(n) != TYPE_INT and typeof(n) != TYPE_FLOAT:
		return {}
	if not is_finite(float(n)) or n < -LIMIT or n > LIMIT or floor(n) != n:
		return {}
	fields.delta = int(n)
	# Restoring an integer erases its lexeme; validate the original bytes before acceptance.
	if JSON.stringify(fields).to_utf8_buffer() != bytes:
		return {}
	return fields


func _initialize() -> void:
	var folder := OS.get_cmdline_user_args()[0]
	var observations := {}
	for token in ["1", "1.0", "true", "9007199254740991", "9007199254740992", "9007199254740993"]:
		var number: Variant = JSON.parse_string(token)
		observations[token] = [type_string(typeof(number)), JSON.stringify(number, "", true, true)]
	var duplicate: Dictionary = JSON.parse_string('{"n":1,"n":2}')
	observations["duplicate"] = [duplicate.size(), int(duplicate.n)]
	print("DEFAULT ", JSON.stringify(observations))

	var decisions := {}
	for filename in DirAccess.get_files_at(folder):
		if not filename.ends_with(".in"):
			continue
		var bytes := FileAccess.get_file_as_bytes(folder.path_join(filename))
		var value := canonical_input(bytes)
		if value.is_empty():
			decisions[filename] = null
		else:
			var encoded := JSON.stringify(value)
			decisions[filename] = encoded.sha256_text()
			FileAccess.open(folder.path_join(filename + ".out"), FileAccess.WRITE).store_buffer(encoded.to_utf8_buffer())

	# Construct a fresh message in Godot for the reverse direction.
	var origin := JSON.stringify({"label": "编队é", "enabled": false, "delta": -LIMIT})
	FileAccess.open(folder.path_join("origin.json"), FileAccess.WRITE).store_buffer(origin.to_utf8_buffer())
	print("ORIGIN ", origin.sha256_text())
	print("DECISIONS ", JSON.stringify(decisions))
	quit(0)
