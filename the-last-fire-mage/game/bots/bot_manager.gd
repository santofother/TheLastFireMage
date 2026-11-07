class_name BotManager
extends Node
## Headless bots for tests. Owner: S07. Registered as GameEvents.system(&"bots").
## `--bot` (client): drive the local player with a BotBrain (set `player.input_driver` on
## GameEvents.local_player_ready). `--bots=N` (host): spawn N server-side bot players through
## `GameEvents.system(&"main").spawn_player(id, name, true)` with ids from Players.BOT_ID_BASE, then set
## their `input_driver`.
## NET: `--bots` runs on the server only; `--bot` on its own client.

func _enter_tree() -> void:
	GameEvents.register_system(&"bots", self)


func _ready() -> void:
	pass # TODO(S07): read NetworkManager.args "bot" / "bots"
