# S06 — Chickens
Agent: **Either** · Tier: **T2** · Codex: GPT-6.1 Sol, high · Claude: Opus 5.5, medium · Wave 1 · Branch: `s06-chickens`
Depends on: S02 · Parallel with: S03 S04 S05 S07 S08

Owns: `game/chicken/**`
Read: `docs/ARCHITECTURE.md` §Chicken §GameEvents §Health, `docs/design/GDD.md` §Chickens

## Goal
Server-simulated chickens that wander, cluck, flee, and can be picked up and killed.

## Steps (all done in this one session)
- `chicken.tscn`: small body, `NavigationAgent3D` wander between random reachable points, flee from nearby
  players, idle pecking. Server simulates; clients receive position via sync (spawned by a `MultiplayerSpawner`
  in the chicken manager).
- Cluck sound: `AudioStreamPlayer3D` with random intervals (placeholder generated beep is fine), louder when
  scared. Carried/hidden chickens cluck less (TUNE).
- Health via the common health component; on death fire `GameEvents.chicken_killed(killer_id, pos)`.
- Pickup hooks for S10: `can_be_carried()`, `on_picked_up(carrier)`, `on_dropped(pos)`, `on_hidden(spot)`.
  Implement the chicken side; the carry system itself is S10.
- Manager spawns N chickens at `chicken_spawn` markers (test scene if map isn't merged), respawn rule (TUNE).

## Tests
Headless: spawn 10 chickens in a test scene with a flat navmesh, run 10 s, check all moved and none fell
through the floor; kill one via test hook → `chicken_killed` logged on server and the chicken is gone on clients.
