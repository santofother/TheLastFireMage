# S11 — Death + basic spectator
Agent: **Either** · Tier: **T3** · Wave 2 · Branch: `s11-death`
Depends on: S04 · Parallel with: S09 S10 S12

Owns: `game/spectator/**`
Read: `docs/ARCHITECTURE.md` §Spectator §Player §Voice, `docs/design/GDD.md` §Death/Spectator, handoff S04

## Goal
Dying works cleanly and dead players watch from above. (Throwing items as a ghost is wave 4.)

## Steps (all done in this one session)
- On `player_died`: body becomes a ragdoll-lite/flattened corpse prop, input off, switch to the spectator camera.
- Top-down camera with limited vision radius (fog-of-war look: dark outside radius), no player highlighting.
  Free movement over the map on a separate height layer.
- Dead players stay in voice: set a `voice_group` flag the voice card (S12) uses. Until S12 is merged, dead
  players just keep normal proximity voice from their camera position.
- Return everyone to alive at round end/restart.

## Tests
Headless: kill a bot via test hook → spectator state on all peers, its player body no longer collides, round
restart revives it.
