extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func has_socket(rig: Skeleton3D, bone: String, socket: String) -> bool:
	if not bone.is_valid_identifier() or not socket.is_valid_identifier():
		return false
	var joint := rig.find_bone(bone)
	if joint < 0:
		return false
	var tip := rig.find_bone(socket)
	if tip >= 0 and rig.get_bone_parent(tip) == joint:
		return true
	for attachment in rig.find_children("*", "BoneAttachment3D", true, false):
		if attachment.bone_name == bone:
			if attachment.name == socket or attachment.find_child(socket, true, false):
				return true
	return false

func validate(definition: Dictionary, scene: Node) -> String:
	if definition.get("schema_version") != 1 or definition.get("usage") != "recollection internal technical validation":
		return "provenance"
	for field in ["source", "author", "id"]:
		if not definition.get(field) is String or definition[field].strip_edges().is_empty():
			return "provenance"
	if not definition.get("markers") is Array or definition.markers.size() != 2:
		return "marker"
	for index in definition.markers.size():
		var marker = definition.markers[index]
		var prefix := "Spawn_" if index == 0 else "Gate_"
		if not marker is String or not marker.is_valid_identifier() or not marker.begins_with(prefix):
			return "marker"
		if not scene.find_child(marker, true, false) is Node3D:
			return "marker"
	var animated_rigs := {}
	for mesh_node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = mesh_node
		var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if not rig or not mesh.skin or not mesh.mesh:
			continue
		var arrays = mesh.mesh.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		if arrays[Mesh.ARRAY_WEIGHTS].size() > 0 and mesh.skin.get_bind_count() >= 2:
			animated_rigs[rig] = true
	if animated_rigs.size() != 2:
		return "skin"
	if not definition.get("rigs") is Array or definition.rigs.size() != animated_rigs.size():
		return "socket"
	var bound := {}
	for entry in definition.rigs:
		if not entry is Dictionary or not entry.get("bone") is String or not entry.get("socket") is String:
			return "socket"
		var found := false
		for rig in animated_rigs:
			if not bound.has(rig) and has_socket(rig, entry.bone, entry.socket):
				bound[rig] = true
				found = true
		if not found:
			return "socket"
	var action = definition.get("action")
	if not action is Dictionary or not action.get("clip") is String:
		return "clip"
	if typeof(action.get("start_s")) not in [TYPE_INT, TYPE_FLOAT] or typeof(action.get("end_s")) not in [TYPE_INT, TYPE_FLOAT]:
		return "window"
	var clip: String = action.clip
	for player in scene.find_children("*", "AnimationPlayer", true, false):
		if player.has_animation(clip):
			var animation: Animation = player.get_animation(clip)
			var start: float = definition.action.start_s
			var end: float = definition.action.end_s
			if start < 0 or start >= end or end > animation.length:
				return "window"
			var driven := {}
			for index in animation.get_track_count():
				var target := animation.track_get_path(index)
				var rig := player.get_node(player.root_node).get_node_or_null(NodePath(target.get_concatenated_names())) as Skeleton3D
				if rig in animated_rigs and target.get_subname_count() > 0 and rig.find_bone(target.get_subname(0)) >= 0 and animation.track_get_key_count(index) >= 2:
					driven[rig] = true
			if driven.size() == animated_rigs.size():
				return ""
	return "clip"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var problem := "definition"
	if manifest is Dictionary:
		problem = "reference"
		var path = manifest.get("scene")
		if path is String and path.begins_with("res://") and ResourceLoader.exists(path, "PackedScene"):
			var scene: Node = load(path).instantiate()
			root.add_child(scene)
			problem = validate(manifest, scene)
			scene.free()
	if not problem.is_empty():
		print("CONTENT_REJECT ", problem)
		quit(2)
		return
	# Isolated compiled definition. P0 proposes no persistent game format.
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	if not output:
		quit(3)
		return
	output.store_var(manifest)
	output.close()
	var input := FileAccess.open(args[1], FileAccess.READ)
	if not input or input.get_var() != manifest:
		quit(3)
		return
	print("CONTENT_OK rigs=2 animated=2 sockets=2 markers=2 compiled_reload=true")
	quit(0)

