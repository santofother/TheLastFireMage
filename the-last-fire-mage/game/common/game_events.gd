extends Node
## GameEvents autoload: the game-level signal bus + system registry. Owner: S02 (head engineer).
## Loaded after the core autoloads. `core/` never uses this.
##
## CONTRACT (how to use the bus):
## - Emitting is a LOCAL call. The system that owns an event is responsible for making it fire on the right
##   peers, normally: server decides → owner system calls its own `@rpc("authority", "call_local", "reliable")`
##   → that RPC emits here. So listeners never need to care about networking.
## - Each signal says on which peers it fires. "all peers" = server + every client.
## - Only the listed owner card emits a signal (tests may emit anything to fake events).
## - Adding a new signal = contract change (head engineer). Never change an existing signature.
##
## System registry: every system root in main.tscn calls `GameEvents.register_system(&"name", self)` in
## `_enter_tree`. Look systems up with `GameEvents.system(&"match") as MatchManager`. May return null in
## test scenes that don't instance that system, so always null-check.

# ------------------------------------------------------------------ match (owner: S04)

## Phase changed. `duration` = seconds this phase lasts (0 = untimed). Fires on: all peers.
signal phase_changed(phase: int, duration: float)
## A role was set for a player (once per player at ROLE_REVEAL, and for late joiners). Fires on: all peers,
## after `Player.set_role()` has run, so the player's Abilities are already in place.
signal role_assigned(peer_id: int, role: int)
## Round decided. `winner` is Enums.Winner. `reason` e.g. "timeout", "all_dead", "mage_died", "mage_left".
## Fires on: all peers, just before phase RESULTS.
signal round_ended(winner: int, reason: String)

# ------------------------------------------------------------------ health / players (owner: S02 player stub, S03)

## A player took damage. `source_id` = attacker peer id (0 = environment). `cause` e.g. &"knife",
## &"ignite", &"fire_wave", &"firestorm", &"fall", &"test". Fires on: all peers.
signal player_damaged(peer_id: int, amount: float, source_id: int, cause: StringName)
## A player died. `killer_id` 0 = environment (firestorm, fall). Fires on: all peers.
signal player_died(peer_id: int, killer_id: int, cause: StringName)
## A dead player was brought back (round reset). Fires on: all peers.
signal player_revived(peer_id: int)
## A player got stunned (server decided). Fires on: all peers.
signal player_stunned(peer_id: int, seconds: float)
## The local human player's node is ready (camera, HUD and spectator hook in here). Fires on: that peer only.
signal local_player_ready(player: Node)

# ------------------------------------------------------------------ chickens / interact (owners: S06, S10)

## A chicken died. `killer_id` = peer id (0 = environment). Fires on: all peers. Owner: S06.
signal chicken_killed(killer_id: int, pos: Vector3)
## What a player carries changed. `kind` = &"" (nothing), &"chicken", or an item kind. Fires on: all peers.
## Owner: S10.
signal carry_changed(peer_id: int, kind: StringName)
## The local interaction prompt changed ("" = hide). Fires on: local peer only. Owner: S10 (HUD shows it).
signal interact_prompt_changed(text: String)

# ------------------------------------------------------------------ mage power (owner: S13)

## Mage power changed. `tier` = unlocked tier (0..3), `multiplier` = current fire effectiveness used by
## MageAbilities.power_multiplier (1.0 = base). Fires on: all peers.
signal power_changed(mage_id: int, power: float, tier: int, multiplier: float)

# ------------------------------------------------------------------ firestorm (owner: S14)

## A storm stage started. Zone shrinks from its current size toward (`center`, `radius`) over the stage.
## `required_power` = power the mage must hold. `time_to_next` = seconds until next stage (0 = final).
## Fires on: all peers.
signal firestorm_stage(stage: int, center: Vector3, radius: float, required_power: float, time_to_next: float)
## Warning before the next stage starts. Fires on: all peers.
signal firestorm_warning(next_stage: int, seconds_until: float)

# ------------------------------------------------------------------ scoring (owner: S16)

## A player's party total changed. Fires on: all peers.
signal score_changed(peer_id: int, total: int)
## Party finished. `standings` = Array of {id: int, name: String, total: int}, best first. Fires on: all peers.
signal party_ended(standings: Array)

# ------------------------------------------------------------------ registry

var _systems: Dictionary = {} # StringName -> Node


## Register a system root (call from its `_enter_tree`). Unregisters automatically when it leaves the tree.
func register_system(system_name: StringName, node: Node) -> void:
	_systems[system_name] = node
	if not node.tree_exiting.is_connected(_unregister.bind(system_name, node)):
		node.tree_exiting.connect(_unregister.bind(system_name, node))


## Returns the registered system node or null.
func system(system_name: StringName) -> Node:
	var n: Node = _systems.get(system_name)
	return n if is_instance_valid(n) else null


## Names of all registered systems (tests use this).
func system_names() -> Array:
	return _systems.keys()


func _unregister(system_name: StringName, node: Node) -> void:
	if _systems.get(system_name) == node:
		_systems.erase(system_name)
