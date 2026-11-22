extends "res://game/player/tests/blue_villager_test.gd"
## Headless checks that the auntie (purple villager) shares the red rig and clips and plays every clip.
## Owner: S19 (auntie villager). Public API: none; run through tools/tests/auntie_villager_test.sh.
## NET: offline. Reuses every check from blue_villager_test.gd with the auntie's paths and meshes.


func _init() -> void:
	BLUE_MESH_PATH = "res://game/player/villager/auntie/auntie-purple.glb"
	BLUE_SCENE_PATH = "res://game/player/villager/auntie_villager.tscn"
	BLUE_MESHES = ["Auntie_Accessories", "Auntie_Body", "Auntie_Face_Hair_Headband", "Auntie_Outfit"]
	LABEL = "AUNTIE VILLAGER"
