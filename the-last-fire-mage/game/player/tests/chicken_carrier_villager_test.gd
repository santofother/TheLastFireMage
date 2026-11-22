extends "res://game/player/tests/blue_villager_test.gd"
## Headless checks that the yellow chicken carrier shares the red rig and clips and plays every clip.
## Owner: S19 (chicken carrier villager). Public API: none; run through tools/tests/chicken_carrier_villager_test.sh.
## NET: offline. Reuses every check from blue_villager_test.gd with the chicken carrier's paths and meshes.


func _init() -> void:
	BLUE_MESH_PATH = "res://game/player/villager/chicken_carrier/yellow-chicken-carrier.glb"
	BLUE_SCENE_PATH = "res://game/player/villager/chicken_carrier_villager.tscn"
	BLUE_MESHES = ["Carrier_Accessories", "Carrier_Body", "Carrier_Face_Hair", "Carrier_Outfit"]
	LABEL = "CHICKEN CARRIER VILLAGER"
