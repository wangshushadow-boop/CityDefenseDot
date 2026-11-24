extends SceneTree

const FIELD := "res://content/base/field/"

func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIELD + "manifest.json"))
	var models: Array[String] = []
	for relative: String in manifest.entrypoints.resources:
		if relative.get_extension() != "glb":
			continue
		var packed := load(FIELD + relative) as PackedScene
		if packed == null:
			quit(1)
			return
		var node := packed.instantiate()
		if not node is Node3D or node.find_children("*", "MeshInstance3D", true, false).is_empty():
			node.free()
			quit(1)
			return
		node.free()
		models.append(relative)
	print("FIELD_MODELS ", JSON.stringify(models))
	quit(0 if not models.is_empty() else 1)
