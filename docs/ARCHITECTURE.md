# Architecture & contracts
Owner: head engineer (Claude). This is the only place contracts live. Builders don't edit it: put proposals
under "Contract change requested" in your handoff. If a card disagrees with this file, this file wins.
Paths are relative to `the-last-fire-mage/`.

## Folders and owners
| Folder | Owner | Root scene in main.tscn | `GameEvents.system()` |
|---|---|---|---|
| `core/` | S12 (voice), head engineer (rest) | autoloads | — |
| `game/main.*`, `game/common/`, `project.godot`, `game/ui/menu/` | head engineer (S02) | `Main` | `&"main"` |
| `game/player/` | S03 | spawned into `Main/Players` | — |
| `game/match/` | S04 | `Systems/Match` | `&"match"` |
| `game/map/`, `tools/map/` | S05 | loaded into `Main/Map` | — |
| `game/chicken/` | S06 | `Systems/Chickens` | `&"chickens"` |
| `game/bots/`, `tools/tests/` (new files), `tools/run_tests.sh` | S07 | `Systems/Bots` | `&"bots"` |
| `game/ui/hud/` | S08 | `HUD` (CanvasLayer 10; menu is 20) | `&"hud"` |
| `game/mage/` | S09 | added under `Player/Abilities` | — |
| `game/interact/` | S10 | `Systems/Interact` + `Player/Abilities/Interactor` | `&"interact"` |
| `game/spectator/` | S11 | `Systems/Spectator` | `&"spectator"` |
| `game/power/` | S13 | `Systems/Power` | `&"power"` |
| `game/firestorm/` | S14 | `Systems/Firestorm` | `&"firestorm"` |
| `game/counterplay/` | S15 | `Systems/Counterplay` | `&"counterplay"` |
| `game/scoring/` | S16 | `Systems/Scoring` | `&"scoring"` |

Rules: **nobody but the head engineer edits `main.tscn`, `main.gd`, `project.godot` or `game/common/`.**
A system changes itself by editing its own root scene (add children, synchronizers, sub-scenes there).
Every system has a stub now with its public API; implement it, keep the signatures. Tests for a system
live in `game/<sys>/tests/` (scenes) + `tools/tests/<sys>_test.sh` (runner).

## Autoloads (in order)
`NetworkManager`, `SteamManager`, `VoiceManager`, `DebugOverlay` (all `core/`, game-agnostic), then
`GameEvents` (`game/common/game_events.gd`). `core/` never references `game/`.

## Authority
- The host is the server (peer 1) and runs every system. **Server decides all outcomes**: damage, deaths,
  stuns, power, timers, phases, scores, pickups. Clients send requests; the server validates.
- Movement is client-authoritative for now: each player node's authority = owning peer. The server changes
  a player's movement only through the player's server hooks (§Player), which RPC to the owner.
- Local bots (`--bots=N`, S07) are players with ids ≥ `Players.BOT_ID_BASE` (1 000 000) and authority 1.
- Offline (no session) counts as server (`Net.is_server()`), so single-process tests work.

## RPC and sync rules
- System roots sit at fixed paths in main.tscn on every peer, so their RPCs always resolve.
- "Server decided, tell everyone": `@rpc("authority", "call_local", "reliable")` on a server-owned node
  (or `@rpc("any_peer", "call_local", "reliable")` + `Net.from_server(self)` on a client-owned node like
  Player), sent with `Net.broadcast(self, &"_rpc_x", [args])`, which also works offline. The RPC body
  updates state and emits the GameEvents signal, so the server's own listeners fire too.
- Client requests: `@rpc("any_peer", "call_local", "reliable")` sent with `.rpc_id(1, ...)`; the server
  checks `Net.sender_id(self)` (works for the host's own calls) and validates everything.
- Continuous state (positions, timers, zone radius): `MultiplayerSynchronizer`, `spawn = true` so late
  joiners get it. Positions `replication_mode = ALWAYS` at 20 Hz; state flags `ON_CHANGE`.
- Late joiners: everything must be either in a synchronizer or re-sent on `NetworkManager.player_registered`
  (server, `rpc_id(new_peer, ...)`).
- Channels: 0 = gameplay reliable (default), 1 = gameplay unreliable (cosmetic: hit flashes, VFX),
  2 = voice (core only).
- Spawned things (players, chickens, items) go through a `MultiplayerSpawner` owned by their system;
  the server frees them and the spawner despawns them on clients.
- Log prefixes: `[Game]` main, `[Match]`, `[Player]`, `[Map]`, `[Chicken]`, `[Bot]`, `[HUD]`, `[Mage]`,
  `[Interact]`, `[Spectator]`, `[Power]`, `[Storm]`, `[Counter]`, `[Score]`, `[Tuning]`, `[TEST]`.

## Physics layers (named in project.godot)
1 world (static map) · 2 players · 3 chickens · 4 interact (Area3D query volumes, no collision) ·
5 props (thrown items, rigid props) · 6 hitboxes (server queries) · 7 triggers (zones) · 8 spectator.
Player: layer 2, mask 1+2+5. Chicken: layer 3, mask 1+5. Dead players: layer 0 (still stand on the floor).

## GameEvents
`game/common/game_events.gd`. A local signal bus plus a registry (`register_system`, `system(name)`).
Emitting is local; the owning system makes it fire on the right peers (see RPC rules). Signatures are
fixed. Each signal's doc comment says the owner and the peers it fires on:

| Signal | Owner | Fires on |
|---|---|---|
| `phase_changed(phase, duration)`, `role_assigned(peer_id, role)`, `round_ended(winner, reason)` | S04 | all |
| `player_damaged(peer_id, amount, source_id, cause)`, `player_died(peer_id, killer_id, cause)`, `player_revived(peer_id)`, `player_stunned(peer_id, seconds)` | Player (from Health) | all |
| `local_player_ready(player)` | Player | local only |
| `chicken_killed(killer_id, pos)` | S06 | all |
| `carry_changed(peer_id, kind)` | S10 | all |
| `interact_prompt_changed(text)` | S10 | local only |
| `power_changed(mage_id, power, tier, multiplier)` | S13 | all |
| `firestorm_stage(stage, center, radius, required_power, time_to_next)`, `firestorm_warning(next_stage, seconds_until)` | S14 | all |
| `score_changed(peer_id, total)`, `party_ended(standings)` | S16 | all |

`source_id`/`killer_id` 0 = environment. Causes: `&"knife"`, `&"ignite"`, `&"fire_wave"`, `&"firestorm"`,
`&"fall"`, `&"item"`, `&"test"`. Enums (`game/common/enums.gd`): `Enums.Role {NONE, VILLAGER, MAGE,
SPECTATOR}`, `Enums.Phase {LOBBY, ROLE_REVEAL, HEAD_START, HUNT, RESULTS}`, `Enums.Winner {NONE, VILLAGERS,
MAGE}`. Sent as ints; only append.

## Common helpers (`game/common/`)
- `Health` (`health.tscn`, child named "Health"): `max_hp`, `hp`, `is_alive` (synced), `invulnerable`
  (server flag); server-only `apply_damage(amount, source_id, cause)`, `kill(source_id, cause)`,
  `heal(amount)`, `revive()`; signals `damaged`, `died`, `revived`, `hp_changed` fire on all peers.
  `Health.find_on(collider)` finds it from any child (hit detection). Always authority 1.
- `Tuning` base: each system has `<sys>_tuning.gd` + `tuning_<sys>.tres` with GDD defaults. Load with
  `Tuning.load_tuning(path, section)` (private copy). Tests override: `--tune=match.hunt_time=10,power.per_chicken=5`.
- `PlayerInput`: one tick of intent (§Player). `Players`: `all()`, `get_player(id)`, `local_player()`,
  `alive_with_role(role)`, `BOT_ID_BASE`. `Net`: `is_server`, `is_online`, `sender_id`, `from_server`,
  `broadcast`. `RoleScenes`: role → ability scenes.

## Main
`game/main.tscn`: WorldEnvironment (group `world_environment`) + Sun (group `sun`), `Map` (map scene
instanced from `MAP_SCENE_PATH = res://game/map/town.tscn`, override `--map=`), `Players` + `PlayerSpawner`,
`Systems/*`, `HUD`, `MenuCamera`, `Menu`. Server spawns a player per registered peer at `villager_spawn`
markers. `main.spawn_player(id, name, is_bot)` (server) is how S07 adds local bots. Lighting stays in
main.tscn; S14 tints it at runtime through the groups.

## Player
`game/player/player.tscn` (`class_name Player`, CharacterBody3D, group `players`, node name = peer id).
S02 wrote the contract; S03 owns the file and must keep all of this working:
- Vars: `peer_id`, `display_name`, `is_bot`, `role`, `is_alive`, `velocity`, `tuning` (PlayerTuning:
  villager/mage .tres, swapped by role), `input`, `input_driver`.
- Nodes: `health` ($Health), `carry_socket` ($CarrySocket Marker3D), `abilities` ($Abilities Node3D),
  `camera_rig` ($CameraRig = pitch; body = yaw), `camera`, `voice` (AudioStreamPlayer3D for VoiceManager).
- `set_role(role)`: called on **every** peer by S04 inside its RPC. Swaps tuning and rebuilds `Abilities`
  from `RoleScenes` (mage: `MageAbilities` + `Interactor`; villager: `Interactor`); abilities get the
  player's authority. Then S04 emits `role_assigned`.
- `is_local()` = this peer's human controls it. `can_control()` = alive, not stunned, no input lock.
- Server hooks (server calls, all peers get it, owner applies): `stun(seconds)`, `set_input_lock(reason,
  on)` (head start freeze, reveal), `teleport(pos)`, `apply_knockback(impulse)`, `set_speed_modifier(source,
  mult)` (carry, nets; 1.0 removes).
- Input: the player fills `input` (PlayerInput) at the start of `_physics_process` from the InputMap, or
  from `input_driver.fill_input(player, input, delta)` (bots). **Movement and abilities read only
  `player.input`**, never `Input`, so bots drive the human code path. Abilities are children, so they run
  after the player in the same tick. Input is cleared while `!can_control()`.
- Death look is the player's job: on `Health.died` it drops to layer 0, lies flat, re-emits
  `GameEvents.player_died`; on revive it restores. Camera: any card takes the view with its own
  `camera.make_current()` and gives it back with `player.camera.make_current()`.
- Sync: `Sync` (position/rotation, 20 Hz, owner authority). S03 may add synced anim/state flags there.

## InputMap (all defined; don't add actions without the head engineer)
move_forward/back/left/right (WASD + arrows), jump (Space), sprint (Shift), crouch (Ctrl, C), interact (E),
drop (G), primary (LMB: mage knife, villager throw), ability_1 (RMB, Q: ignite), ability_2 (F: fire wave),
push_to_talk (V), scoreboard (Tab), debug (F3), menu (Esc). `core/` still reads raw keys (V, F3, F4) to stay
game-agnostic; S12 may switch voice to the `push_to_talk` action with a key fallback.

## Match
`MatchManager` (`game/match/`): `phase`, `time_left` (synced), `mage_id`, `roles`, `tuning`;
server `start_round(mage_id = 0)`, `end_round(winner, reason)`; `get_role(id)`, `is_round_active()`.
Uses Player hooks for spawning (`teleport` to `villager_spawn`/`mage_spawn`), freezing (`set_input_lock`),
and `Health.revive()` / `invulnerable` for resets. Ends the round on `player_died` (any cause, including
firestorm) and on mage disconnect. The host lobby UI lives inside the match scene.

## Map
Map scene root: Node3D with static geometry on layer 1, a baked `NavigationRegion3D` (chickens), no
lighting. Marker nodes (Marker3D or any Node3D) in groups: `villager_spawn`, `mage_spawn`, `chicken_spawn`,
`item_spawn`; hiding places are instances of `res://game/interact/hide_spot.tscn` (group `hide_spot`).
`game/map/test_arena.tscn` is the small test map (stable, for tests); `town.tscn` is the real map (S05
regenerates it; today it just wraps the test arena).

## Chicken
`ChickenManager` spawns `chicken.tscn` (`class_name Chicken`, layer 3, group `chickens`) via its own
spawner, server-simulated. Chickens have a `Health`; on death they emit `chicken_killed` and the server
frees them. Synced `carrier_id` and `is_hidden`. They implement **Carryable** (below).

## Interact
`Interactable` (Area3D on layer 4, child of any usable object): `prompt`, `kind`, `max_distance`,
`can_interact(player)`, server `interact(player)` → `interacted`. The player-side `Interactor` ability does
detection, prompt (`interact_prompt_changed`) and requests; `InteractManager` keeps the server's carry
table (one carrier per object) and fires `carry_changed`.
**Carryable** interface (methods on the carried object's root, called by S10 on the server):
`can_be_carried() -> bool`, `carry_speed_multiplier() -> float`, `on_picked_up(carrier)`,
`on_dropped(pos, impulse)`, `on_hidden(spot)`, `on_unhidden()`. The object syncs its own state and every
peer places it at the carrier's `carry_socket` while carried (no reparenting of networked nodes).
S10 applies the carry slow with `player.set_speed_modifier(&"carry", obj.carry_speed_multiplier())`.

## Mage
`MageAbilities` (Node3D, under `Player/Abilities`). Owner peer reads `player.input` and RPCs requests;
server validates range/angle/cooldown/line of sight and calls `Health.apply_damage`. Chickens are valid
targets (find with `Health.find_on`). `power_multiplier` (default 1.0) is updated on all peers from
`power_changed`. HUD reads `cooldown_left(&"knife"|&"ignite"|&"fire_wave")`, `is_ignited()`.

## Power
`PowerManager`: server counts kills from `chicken_killed` / `player_died` (killer = mage), applies
tier/decay from `tuning_power.tres`, fires `power_changed`. `current_power()`, `current_tier()`,
`multiplier()`; `add_power()` for tests. Calls `VoiceManager.set_speaker_effect(mage_id, "mage", strength)`
once S12 provides it.

## Firestorm
`FirestormManager`: server runs stages during HUNT, fires `firestorm_warning` / `firestorm_stage`, damages
players outside the zone (`apply_damage(..., 0, &"firestorm")`), kills the mage below
`required_power()` for too long (`kill(0, &"firestorm")`). `is_inside(pos)`, `zone_center`, `zone_radius`.

## Counterplay
`CounterplayManager`: items at `item_spawn` (using Interactable/Carryable), environment pieces as reusable
scenes. Server applies effects only through `request_stun(target, seconds, source_id)` (diminishing
returns) and `Player.set_speed_modifier`.

## Spectator
`SpectatorManager` (local per peer): on the local player's death (or role SPECTATOR) switch to its own
top-down camera with a vision radius; `exit_spectator()` gives the view back. Doesn't touch the body
(Player does). Voice routing via S12's `set_voice_group` when available.

## Scoring
`ScoringManager`: server tallies from `player_died`, `round_ended`, `phase_changed`; fires `score_changed`;
party mode calls `MatchManager.start_round(next_mage)` after RESULTS and fires `party_ended`.

## UI
`Hud` (`game/ui/hud/`): reads only GameEvents + public vars through `GameEvents.system(...)`; never
changes game state. Menu (`game/ui/menu/`, head engineer) owns Esc and the mouse capture.

## Voice
`core/voice_manager.gd` + `core/voice/` (S12) stay game-agnostic. Capture is 16 kHz mono, sent as IMA ADPCM
(~65 kbit/s; raw PCM fallback via `--voice-raw`), RPC `_voice_packet(data, codec, group)`, unreliable_ordered, channel 2.
Receivers have a jitter buffer. Loudness tuning (MIC_GAIN 12, 8 m / 45 m falloff, `max_distance = 0`) is a contract.
Game hooks: `register_speaker(peer_id, player, node)`, `listener` (set by Player),
`set_speaker_effect(peer_id, preset, strength)` (presets `mage deep distort cave none`; S13 PowerManager drives `mage`),
`set_voice_group(peer_id, group)` for the LOCAL peer (`alive`/`dead`; S11 SpectatorManager calls it) with the
data-driven `voice_rules` table (`set_voice_rule`). The game calls them; `core/` knows nothing about mages or death.

## Bots
`--bot` (client) or `--bots=N` (host) handled by `BotManager`. A `BotBrain` implements
`fill_input(player, input, delta)` and is set as `player.input_driver`.

## Tests
`tools/run_tests.sh` runs every `tools/tests/*.sh`. Existing: `net_test.sh` (3 peers, positions + voice),
`contract_test.sh` (boots main.tscn, checks every contract above: systems, InputMap, markers, Player API,
tuning overrides, Health events). Keep both green; extend the contract test only via the head engineer.
