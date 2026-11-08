@tool
extends EditorScenePostImport
## Import script for red-villager-animations.glb: glTF has no looping flag, so set it here. Owner: villager model.
## NET: editor/import time only. Public API: none (Godot calls `_post_import`).

const LOOPS: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"jump_air", &"carry_idle", &"carry_walk"]


func _post_import(scene: Node) -> Object:
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		for clip: StringName in player.get_animation_list():
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip in LOOPS else Animation.LOOP_NONE
	return scene
