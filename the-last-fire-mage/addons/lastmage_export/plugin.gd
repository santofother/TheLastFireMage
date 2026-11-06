@tool
extends EditorPlugin
## Copies res://steam_appid.txt next to the exported executable (Windows) / .app or .zip (macOS).

var _exporter: SteamAppIdExporter


func _enter_tree() -> void:
	_exporter = SteamAppIdExporter.new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	remove_export_plugin(_exporter)


class SteamAppIdExporter extends EditorExportPlugin:
	var _out_dir := ""

	func _get_name() -> String:
		return "SteamAppIdExporter"

	func _export_begin(_features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
		_out_dir = path.get_base_dir()

	func _export_end() -> void:
		if _out_dir.is_empty():
			return
		var dst := _out_dir.path_join("steam_appid.txt")
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path("res://steam_appid.txt"), dst)
		print("[Export] steam_appid.txt -> ", dst, " (", error_string(err), ")")
