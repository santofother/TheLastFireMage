@tool
extends EditorScenePostImport
const LOOPS = ["idle", "walk", "run", "sprint"]
func _post_import(scene: Node) -> Object:
 var player = scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
 if player:
  for name in player.get_animation_list():
   player.get_animation(name).loop_mode = Animation.LOOP_LINEAR if name in LOOPS else Animation.LOOP_NONE
 return scene
