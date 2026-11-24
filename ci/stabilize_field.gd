extends SceneTree
## Godot 4.7 assigns fresh scene-local node IDs on every GLB import.
## Normalize only self-contained imports in the temporary build project.
const FIELD := "res://content/base/field/"

func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIELD + "manifest.json"))
	for relative: String in manifest.entrypoints.resources:
		if relative.get_extension() != "glb":
			continue
		var source := FIELD + relative
		var config := ConfigFile.new()
		if config.load(source + ".import") != OK:
			quit(1)
			return
		var scene := load(source) as PackedScene
		if not scene or not stabilize(scene, config.get_value("remap", "path")):
			printerr("Could not stabilize field model ", source)
			quit(1)
			return
	quit(0)

func stabilize(scene: PackedScene, imported: String) -> bool:
	var bundle := scene._bundled
	if not bundle.id_paths.is_empty():
		return false
	var ids: PackedInt32Array = bundle.node_ids
	for i in ids.size():
		ids[i] = i + 1
	bundle.node_ids = ids
	scene._bundled = bundle
	return ResourceSaver.save(scene, imported, ResourceSaver.FLAG_COMPRESS) == OK
