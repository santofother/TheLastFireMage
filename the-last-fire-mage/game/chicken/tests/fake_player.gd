extends Node3D
## Test stand-in for a Player (group "players"). Owner: S06 tests. Only has what chickens read:
## `peer_id`, `is_alive`, `carry_socket`.

@export var peer_id := 999
@export var is_alive := true
@onready var carry_socket: Node3D = $CarrySocket
