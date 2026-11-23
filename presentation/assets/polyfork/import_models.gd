@tool
extends EditorScenePostImport
## 原模型以线性顶点色保存衣甲和建筑颜色，导入时启用，并让移动片段连续循环。
func _post_import(scene: Node) -> Object:
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			material.vertex_color_use_as_albedo = true
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for clip in [&"Idle", &"Walk", &"Run"]:
			if player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return scene
