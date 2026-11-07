# S02 — Architecture, contracts and stubs
Agent: **Claude only** (head engineer) · Tier: **T1** (Opus 5.5, high) · Wave 0 · Branch: `s02-architecture`
Depends on: S01 · Parallel with: nothing (every later card builds on this)

Owns: `docs/ARCHITECTURE.md`, `the-last-fire-mage/project.godot` (autoloads + InputMap), `game/main.tscn`,
`game/main.gd`, `game/common/**`, stub files in every system folder listed below, `docs/sessions/*` (to correct cards)
Read: `AGENTS.md`, `docs/design/GDD.md`, `game/*.gd`, `core/network_manager.gd` (header + signals only)

## Goal
After this card, wave-1 cards can run in parallel **without editing the same files**. That means every shared
thing is decided and stubbed now.

## Steps (all done in this one session)
1. `docs/ARCHITECTURE.md` (max ~3 pages): folder per system with owner card, autoload list, the authority model
   (server decides all outcomes; client-authoritative movement for now), the RPC/sync rules, and the contracts
   below. Keep it the single place contracts live.
2. Folders + stub scenes/scripts (header comment, public API with `pass`/TODO bodies) for: `game/player/` (S03),
   `game/match/` (S04), `game/map/` (S05), `game/chicken/` (S06), `game/bots/` (S07), `game/ui/hud/` (S08),
   `game/mage/` (S09), `game/interact/` (S10), `game/spectator/` (S11), `game/power/` (S13),
   `game/firestorm/` (S14), `game/counterplay/` (S15), `game/scoring/` (S16).
3. `game/main.tscn` instances every system stub, so **later cards never edit main.tscn**. The map is loaded by
   path from one constant.
4. `game/common/`: `GameEvents` autoload (game-level signal bus, all signals declared now with doc comments:
   e.g. `role_assigned`, `phase_changed`, `player_damaged`, `player_died`, `chicken_killed`, `power_changed`,
   `firestorm_stage`, `round_ended`, `score_changed`); `health.gd` component (server-side damage/death,
   synced `hp`, `is_alive`); `Role` / `Phase` enums; a `tuning` pattern (one `.tres` per system, script class
   in common).
5. Player contract: what `player.tscn` exposes for other cards (`role`, `is_alive`, `velocity`, a `CarrySocket`
   node, an `Abilities` node that role scenes are added to at runtime, `stun(seconds)` hook, a camera rig
   other cards can switch from).
6. All InputMap actions now (move, jump, sprint, crouch, interact, drop, primary, ability_1, ability_2,
   push_to_talk, scoreboard, debug) so nobody edits `project.godot` later.
7. Update session cards S03–S16 if folders/contracts differ from what they say. Keep `tools/run_tests.sh` green.

## Done when
Stubs compile, `tools/run_tests.sh` passes, ARCHITECTURE.md written, the user has read it (ask them to).
