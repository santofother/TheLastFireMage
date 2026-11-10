extends Node3D
## Test stub with the replicated Player vars the audio code reads. Owner: S18 (tests only).
var peer_id := 900
var role: int = Enums.Role.VILLAGER
var is_alive := true
var is_sprinting := false
var is_crouching := false
var is_airborne := false
var is_mantling := false
var is_tumbling := false
var voice: AudioStreamPlayer3D


func is_local() -> bool:
	return false
