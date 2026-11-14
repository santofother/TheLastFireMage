@tool
extends EditorPlugin
## Copies res://steam_appid.txt next to the exported executable (Windows) / .app or .zip (macOS), and stamps
## the git commit into the pack as res://build_commit.txt (NetworkManager.build_id uses it for the join check).

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
		var out: Array = []
		var commit := "unknown"
		if OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short", "HEAD"], out) == 0 \
				and not out.is_empty():
			commit = String(out[0]).strip_edges()
		add_file("res://build_commit.txt", commit.to_utf8_buffer(), false)
		print("[Export] build commit ", commit)

	func _export_end() -> void:
		if _out_dir.is_empty():
			return
		var dst := _out_dir.path_join("steam_appid.txt")
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path("res://steam_appid.txt"), dst)
		print("[Export] steam_appid.txt -> ", dst, " (", error_string(err), ")")
