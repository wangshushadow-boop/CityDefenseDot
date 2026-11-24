extends SceneTree

const Codec = preload("res://contracts/canonical.gd")

func _initialize() -> void:
	var file := FileAccess.open("res://vectors.tsv", FileAccess.READ)
	var count := 0
	var bad := 0
	while true:
		var row := file.get_line()
		if row.is_empty():
			break
		var fields := row.split("\t", true)
		var raw := fields[1].hex_decode()
		var src: Dictionary = Codec.decode_source(raw)
		var strict: Dictionary = Codec.decode(raw)
		var passed: bool = src.ok == (fields[2] != "-") and strict.ok == (fields[3] == "1")
		if src.ok and fields[2] != "-":
			var back: Dictionary = Codec.encode(src.value)
			var hashv: Dictionary = Codec.hash_value(src.value)
			passed = passed and back.ok and back.value.hex_encode() == fields[2] and hashv.ok and hashv.value == fields[4]
		if not passed:
			if bad < 15:
				print("QA_BAD ",fields[0]," src=",src.ok," strict=",strict.ok," exp=",fields[2] != "-", "/",fields[3]," hex=",fields[1])
			bad += 1
		count += 1
	print("QA_CANONICAL ",count," candidates, mismatches=",bad)
	quit(1 if bad else 0)
