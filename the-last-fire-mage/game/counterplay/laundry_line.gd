class_name LaundryLine
extends Node3D
## Reusable map piece: a washing line. A villager pulls the sheet across the path to block the mage's view
## for `tuning.sheet_time` seconds. Owner: S15. Place `laundry_line.tscn` between two walls (sheet is
## visual only, it does not block movement).
## NET: server decides on `interacted`, every peer shows the sheet via `_rpc_set_sheet` (same node path).

var sheet_up := false
var _left := 0.0


func _ready() -> void:
	var area := $Interactable as Interactable
	area.interacted.connect(_on_interacted)
	area.condition = func(_p: Node) -> bool: return not sheet_up
	$Sheet.visible = false


func _physics_process(delta: float) -> void:
	if sheet_up and Net.is_server(self):
		_left -= delta
		if _left <= 0.0:
			Net.broadcast(self, &"_rpc_set_sheet", [false])


func _on_interacted(player: Node) -> void: # NET: server only
	var manager := GameEvents.system(&"counterplay") as CounterplayManager
	_left = manager.tuning.sheet_time if manager else 10.0
	print("[Counterplay] %s sheet pulled by %d" % [name, player.peer_id])
	Net.broadcast(self, &"_rpc_set_sheet", [true])


@rpc("authority", "call_local", "reliable")
func _rpc_set_sheet(on: bool) -> void:
	sheet_up = on
	$Sheet.visible = on
