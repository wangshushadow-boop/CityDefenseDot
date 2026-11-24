extends SceneTree

const C = preload("res://contracts/canonical.gd")
const NFC = preload("res://contracts/unicode_nfc.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var corpus: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var failures := 0
	for row in corpus.nfc:
		if NFC.is_nfc(row[0]) != row[1]:
			if failures < 3:
				printerr("NFC mismatch at ", row[0].to_utf8_buffer().hex_encode())
			failures += 1
	for row in corpus.wire:
		var bytes: PackedByteArray = row[0].to_utf8_buffer()
		var decoded := C.decode(bytes)
		if not decoded.ok or C.encode(decoded.value).value != bytes or C.hash_value(decoded.value).value != row[1]:
			failures += 1
	# Construct a domain object in Godot and independently compare emitted bytes in Python.
	var native := {"list":["",""], "nul":PackedStringArray(["","é","","猫",""]),
		"integer":9007199254740991,"astral":"🚀","controls":"\b\t\n\f\r"}
	var output := FileAccess.open(args[1],FileAccess.WRITE)
	output.store_buffer(C.encode(native).value)
	output.close()
	print("CON_ORACLE nfc=",corpus.nfc.size()," wire=",corpus.wire.size()," errors=",failures)
	quit(0 if failures==0 else 1)
