# S10 — Carry, hide, interact
Agent: **Either** · Tier: **T2** · Codex: GPT-6.1 Sol, high · Claude: Opus 5.5, medium · Wave 2 · Branch: `s10-interact`
Depends on: S03, S06 · Parallel with: S09 S11 S12

Owns: `game/interact/**`
Read: `docs/ARCHITECTURE.md` §Interact §Player §Chicken, `docs/design/GDD.md` §Chickens §Counterplay, handoffs S03 S06

## Goal
One interaction system villagers use for chickens now and items/doors later.

## Steps (all done in this one session)
- `Interactable` component + player-side interaction raycast/area, prompt text ("E: pick up chicken").
- Carry: chicken goes to `CarrySocket`, slows the carrier a bit (TUNE), drop and throw.
- Hide spots (`hide_spot` group: crates, barrels, sheds): put a carried chicken inside → it's hidden and
  quieter; the mage can search a hide spot (takes time) to find it.
- Server validates every interaction (distance, ownership, one carrier at a time).
- Generic enough that S15 items and future doors plug in without changes.

## Tests
Headless with bots: bot picks up a chicken, moves, hides it, chicken state is hidden on all peers; two bots
try to grab the same chicken → only one succeeds.
