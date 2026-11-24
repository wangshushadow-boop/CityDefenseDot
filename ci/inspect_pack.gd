extends SceneTree

func _initialize() -> void:
	var ok := not DirAccess.dir_exists_absolute("res://tests") and FileAccess.file_exists("res://build_info.json")
	if ok:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
		ok = typeof(data) == TYPE_DICTIONARY
		if ok:
			print("PACK_STAMP ", JSON.stringify(data))
	quit(0 if ok else 1)
