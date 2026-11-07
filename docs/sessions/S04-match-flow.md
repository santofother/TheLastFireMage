# S04 — Match flow, roles, timer, win conditions
Agent: **Lean Codex** (well-specified state machine) · Tier: **T2** · Wave 1 · Branch: `s04-match`
Depends on: S02 · Parallel with: S03 S05 S06 S07 S08

Owns: `game/match/**`
Read: `docs/ARCHITECTURE.md` §Match §GameEvents §Authority, `docs/design/GDD.md` §Match flow §Roles

## Goal
Server-run round from lobby to results.

## Steps (all done in this one session)
- Phases: LOBBY → ROLE_REVEAL (3 s) → HEAD_START (30 s, mage blinded/frozen, villagers spawn at random spawn
  points the mage can't see) → HUNT (timer, default 6 min TUNE) → RESULTS (10 s) → back to LOBBY.
- Host picks who is mage (or random) from the lobby; synced to all clients.
- Win rules: villagers win when time runs out or mage dies; mage wins when all villagers are dead.
  Listen to `GameEvents.player_died`; firestorm death arrives the same way.
- Late join = spectator; disconnecting mage ends the round (villagers win, flag "mage left").
- Fire every phase change on `GameEvents`. Synced `time_left` for the HUD.
- Spawn points: nodes in group `villager_spawn` / `mage_spawn`. `game/map/test_arena.tscn` already has them
  (run tests with `--map=res://game/map/test_arena.tscn`).
- Use the Player server hooks (`teleport`, `set_input_lock`), `Health.revive()` / `invulnerable`, and call
  `Player.set_role()` on every peer inside your RPC before emitting `role_assigned`.
- Host lobby UI (start button, mage pick) lives inside `match_manager.tscn`. Add your own CLI flags there
  (e.g. `--autostart`).

## Tests
Headless: host + 2 clients with `--autostart` (or a test hook), short timers (`--tune=match.hunt_time=10,match.head_start_time=2`), check the log
goes through all phases and the right winner is printed for: timeout, all villagers killed (test hook kill).
