extends SceneTree

func _initialize() -> void:
	var failures := 0
	for file in ["general", "spear_soldier", "crossbowman"]:
		var packed := load("res://%s.glb" % file) as PackedScene
		if not packed:
			failures += 1
			continue
		var model := packed.instantiate()
		root.add_child(model)
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		var skin_count := 0
		for mesh in meshes:
			if mesh.skin != null and mesh.mesh != null:
				skin_count += 1
		var tracks := {}
		if not players.is_empty():
			var player: AnimationPlayer = players[0]
			for clip in ["Idle","Walk","Run"]:
				if player.has_animation(clip):
					player.play(clip)
					player.advance(0.2)
					tracks[clip] = player.get_animation(clip).get_track_count()
		var bones := 0
		for rig in skeletons:
			bones = maxi(bones, rig.get_bone_count())
		if bones < 1 or skin_count == 0 or tracks.size() != 3 or 0 in tracks.values():
			failures += 1
		print("P2_ART ", JSON.stringify({"asset":file,"bones":bones,"skinned_meshes":skin_count,"animation_tracks":tracks}))
		model.free()
	print("P2_ART_IMPORT ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
