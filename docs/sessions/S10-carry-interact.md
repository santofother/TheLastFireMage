# S10 — Carry, hide, interact
Agent: **Lean Codex** · Tier: **T2** · Wave 2 · Branch: `s10-interact`
Depends on: S03, S06 · Parallel with: S09 S11 S12

Owns: `game/interact/**`
Read: `docs/ARCHITECTURE.md` §Interact §Player §Chicken, `docs/design/GDD.md` §Chickens §Counterplay, handoffs S03 S06

## Goal
One interaction system villagers use for chickens now and items/doors later.

## Steps (all done in this one session)
- Stubs exist: `Interactable` (Area3D, layer 4), `Interactor` (added to every role's `Abilities`),
  `HideSpot` (`hide_spot.tscn`, placed by the map), `InteractManager` (server carry table). Prompt text via
  `GameEvents.interact_prompt_changed`; fire `carry_changed`.
- Carry: chicken follows `carry_socket` (Carryable interface, no reparenting), slows the carrier with
  `set_speed_modifier(&"carry", obj.carry_speed_multiplier())`, drop (`drop`) and throw (villager `primary`).
- Hide spots (`hide_spot` group: crates, barrels, sheds): put a carried chicken inside → it's hidden and
  quieter; the mage can search a hide spot (takes time) to find it.
- Server validates every interaction (distance, ownership, one carrier at a time).
- Generic enough that S15 items and future doors plug in without changes.

## Tests
Headless with bots: bot picks up a chicken, moves, hides it, chicken state is hidden on all peers; two bots
try to grab the same chicken → only one succeeds.
