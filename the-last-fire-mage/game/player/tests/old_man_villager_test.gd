extends "res://game/player/tests/blue_villager_test.gd"
## Headless checks that the old man (elderly villager) shares the red rig and clips and plays every clip.
## Owner: S19 (old man villager). Public API: none; run through tools/tests/old_man_villager_test.sh.
## NET: offline. Reuses every check from blue_villager_test.gd with the old man's paths and meshes.


func _init() -> void:
	BLUE_MESH_PATH = "res://game/player/villager/elderly/elderly-villager.glb"
	BLUE_SCENE_PATH = "res://game/player/villager/old_man_villager.tscn"
	BLUE_MESHES = ["Elder_Body", "Elder_Clothing", "Elder_Headwear_and_Face"]
	LABEL = "OLD MAN VILLAGER"
