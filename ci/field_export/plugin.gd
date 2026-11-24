@tool
extends EditorPlugin

class FieldExport extends EditorExportPlugin:
	const FIELD := "res://content/base/field/"

	func _get_name() -> String:
		return "FieldPackageSources"

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIELD + "manifest.json"))
		for relative: String in manifest.entrypoints.resources:
			# Godot exports imported scenes for GLBs. The content hash also covers their source bytes.
			if relative.get_extension() in ["glb", "md"]:
				var source := FIELD + relative
				add_file(source, FileAccess.get_file_as_bytes(source), false)

var field_export := FieldExport.new()

func _enter_tree() -> void:
	add_export_plugin(field_export)

func _exit_tree() -> void:
	remove_export_plugin(field_export)
