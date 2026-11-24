extends RefCounted

const R = preload("res://contracts/result.gd")
const NFC = preload("res://contracts/unicode_nfc.gd")
const MAX_INTEGER := 9007199254740991
const MAX_DEPTH := 64
const MAX_ITEMS := 65536

static func _quote(s: String) -> String:
	var out := "\""
	for i in s.length():
		var cp := s.unicode_at(i)
		match cp:
			34: out += "\\\""
			92: out += "\\\\"
			8: out += "\\b"
			9: out += "\\t"
			10: out += "\\n"
			12: out += "\\f"
			13: out += "\\r"
			_:
				if cp < 32:
					out += "\\u%04x" % cp
				else:
					out += s[i]
	return out + "\""

# Godot String replaces NUL. The immutable host form is a typed array of
# StringName segments. An ordinary JSON array always decodes as untyped Array.
static func is_nul_text(value: Variant) -> bool:
	return typeof(value) == TYPE_PACKED_STRING_ARRAY or (typeof(value) == TYPE_ARRAY and value.get_typed_builtin() == TYPE_STRING_NAME)

static func is_json_array(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY and not is_nul_text(value)

static func is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or (is_nul_text(value) and value.size() >= 2)

static func nul_text(segments: Variant) -> Array[StringName]:
	var text: Array[StringName] = []
	for segment: String in segments:
		text.append(StringName(segment))
	text.make_read_only()
	return text

static func _write_nul(parts: Variant, chunks: PackedStringArray) -> bool:
	if parts.size() < 2:
		return false
	var quoted := PackedStringArray()
	for segment in parts:
		var text := String(segment)
		if not NFC.is_nfc(text):
			return false
		var part := _quote(text)
		quoted.append(part.substr(1, part.length() - 2))
	chunks.append('"'+ "\\u0000".join(quoted) + '"')
	return true

static func _write(value: Variant, depth: int, chunks: PackedStringArray) -> bool:
	if depth > MAX_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL: chunks.append("null")
		TYPE_BOOL: chunks.append("true" if value else "false")
		TYPE_INT:
			if value < -MAX_INTEGER or value > MAX_INTEGER:
				return false
			chunks.append(str(value))
		TYPE_STRING:
			if not NFC.is_nfc(value):
				return false
			chunks.append(_quote(value))
		TYPE_PACKED_STRING_ARRAY:
			return _write_nul(value, chunks)
		TYPE_ARRAY:
			if is_nul_text(value):
				return _write_nul(value, chunks)
			if value.size() > MAX_ITEMS:
				return false
			chunks.append("[")
			for i in value.size():
				if i:
					chunks.append(",")
				if not _write(value[i], depth + 1, chunks):
					return false
			chunks.append("]")
		TYPE_DICTIONARY:
			if value.size() > MAX_ITEMS:
				return false
			var keys: Array = value.keys()
			for key in keys:
				if not Reader.valid_key(key):
					return false
			keys.sort()
			chunks.append("{")
			for i in keys.size():
				if i:
					chunks.append(",")
				chunks.append(_quote(keys[i]) + ":")
				if not _write(value[keys[i]], depth + 1, chunks):
					return false
			chunks.append("}")
		_:
			return false
	return true

static func encode(value: Variant) -> Dictionary:
	var chunks := PackedStringArray()
	if not _write(value, 0, chunks):
		return R.fail("InvalidArgument", "canonical")
	return R.ok("".join(chunks).to_utf8_buffer())

static func hash_value(value: Variant) -> Dictionary:
	var encoded := encode(value)
	if not encoded.ok:
		return encoded
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(encoded.value)
	return R.ok(digest.finish().hex_encode())

static func decode_source(bytes: PackedByteArray) -> Dictionary:
	var parser := Reader.new()
	parser.source = bytes.get_string_from_utf8()
	if bytes != parser.source.to_utf8_buffer():
		return R.fail("InvalidArgument", "utf8")
	var value: Variant = parser.value_at(0)
	parser.space()
	if parser.invalid or parser.pos != parser.source.length():
		return R.fail("InvalidArgument", "json@%d" % parser.pos)
	return R.ok(value)

static func decode(bytes: PackedByteArray) -> Dictionary:
	var parsed := decode_source(bytes)
	if not parsed.ok:
		return parsed
	var encoded := encode(parsed.value)
	if not encoded.ok or encoded.value != bytes:
		return R.fail("InvalidArgument", "canonical")
	return parsed

# Read integers from their lexemes and observe keys before insertion.
# Godot's generic JSON.parse loses both distinctions.
class Reader:
	static func valid_key(key: Variant) -> bool:
		if typeof(key) != TYPE_STRING or key.is_empty():
			return false
		for i in key.length():
			if key.unicode_at(i) < 32 or key.unicode_at(i) > 126:
				return false
		return true

	var source: String
	var pos := 0
	var invalid := false

	func reject() -> Variant:
		invalid = true
		return null

	func space() -> void:
		while pos < source.length() and source.unicode_at(pos) in [9, 10, 13, 32]:
			pos += 1

	func take(ch: String) -> bool:
		if pos < source.length() and source[pos] == ch:
			pos += 1
			return true
		return false

	func hex4() -> int:
		var raw := source.substr(pos, 4)
		if raw.length() != 4 or not raw.is_valid_hex_number(false) or raw[0] in ["+", "-"]:
			invalid = true
			return -1
		pos += 4
		return raw.hex_to_int()

	func string_value() -> Variant:
		var out := ""
		var segments := PackedStringArray()
		while pos < source.length():
			var ch := source[pos]
			pos += 1
			if ch == "\"":
				if not NFC.is_nfc(out):
					invalid = true
				if not segments.is_empty():
					segments.append(out)
					var marked: Array[StringName] = []
					for item: String in segments:
						marked.append(StringName(item))
					marked.make_read_only()
					return marked
				return out
			if ch.unicode_at(0) < 32:
				break
			if ch != "\\":
				out += ch
				continue
			if pos == source.length():
				break
			var esc := source[pos]
			pos += 1
			match esc:
				"\"", "\\", "/": out += esc
				"b": out += "\b"
				"f": out += "\f"
				"n": out += "\n"
				"r": out += "\r"
				"t": out += "\t"
				"u":
					var cp := hex4()
					if cp >= 0xd800 and cp <= 0xdbff:
						if not take("\\") or not take("u"):
							break
						var tail := hex4()
						if tail < 0xdc00 or tail > 0xdfff:
							break
						cp = 0x10000 + ((cp - 0xd800) << 10) + tail - 0xdc00
					if cp == 0:
						if not NFC.is_nfc(out):
							break
						segments.append(out)
						out = ""
						continue
					if cp < 0 or (cp >= 0xdc00 and cp <= 0xdfff):
						break
					out += String.chr(cp)
				_: break
		invalid = true
		return ""

	func value_at(depth: int) -> Variant:
		space()
		if depth > MAX_DEPTH or pos == source.length():
			return reject()
		if take("\""):
			return string_value()
		if take("{"):
			var obj := {}
			space()
			if take("}"):
				return obj
			while not invalid:
				space()
				if not take("\""):
					return reject()
				var key: Variant = string_value()
				space()
				if invalid or not valid_key(key) or obj.has(key) or obj.size() >= MAX_ITEMS or not take(":"):
					return reject()
				obj[key] = value_at(depth + 1)
				space()
				if take("}"):
					return obj
				if not take(","):
					return reject()
			return null
		if take("["):
			var items := []
			space()
			if take("]"):
				return items
			while not invalid:
				if items.size() >= MAX_ITEMS:
					return reject()
				items.append(value_at(depth + 1))
				space()
				if take("]"):
					return items
				if not take(","):
					return reject()
			return null
		for literal in ["true", "false", "null"]:
			if source.substr(pos, literal.length()) == literal:
				pos += literal.length()
				if literal == "null":
					return null
				return literal == "true"
		var start := pos
		take("-")
		var first := pos
		while pos < source.length() and source.unicode_at(pos) >= 48 and source.unicode_at(pos) <= 57:
			pos += 1
		var digits := pos - first
		if digits == 0 or digits > 16 or (digits > 1 and source[first] == "0"):
			return reject()
		var n := source.substr(start, pos - start).to_int()
		if n < -MAX_INTEGER or n > MAX_INTEGER:
			return reject()
		return n
