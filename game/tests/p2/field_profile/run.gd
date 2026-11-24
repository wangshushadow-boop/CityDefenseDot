extends SceneTree

func _initialize() -> void:
	var atlas: Variant = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")
	var tts: Variant = ProjectSettings.get_setting("audio/general/text_to_speech")
	var renderer: Variant = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	var valid: bool = is_same(atlas,2048) and is_same(tts,true) and renderer=="forward_plus"
	print("P2-FIELD-PROFILE ","PASS" if valid else "FAIL"," shadow=",atlas," renderer=",renderer," tts=",tts)
	quit(0 if valid else 1)
