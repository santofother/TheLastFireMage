# S15 — Villager stuns / counterplay
Agent: **Either** · Tier: **T3** · Codex: GPT-6.1 Sol, medium · Claude: Sonnet 5.5, medium · Wave 3 · Branch: `s15-counterplay`
Depends on: S03 (S10 for item pickup; stub if not merged) · Parallel with: S13 S14 S16

Owns: `game/counterplay/**`
Read: `docs/ARCHITECTURE.md` §Counterplay §Interact §Player, `docs/design/GDD.md` §Counterplay

## Goal
Villagers can't hurt the mage but can briefly stop them.

## Steps (all done in this one session)
- 2–3 throwable/usable items spawned at `item_spawn` (e.g. bucket of water = stun + extinguish ignite,
  clay pot = short stagger, fishing net = slow). Items use the interact system from S10.
- Server validates hits; calls `stun(seconds)` / slow on the mage. Diminishing returns so the mage can't be
  stun-locked (TUNE).
- Environment: 1–2 map interactions as reusable scenes (e.g. a tippable cart, a laundry line that blocks
  sight) that the map card can place later.

## Tests
Headless: bot throws item at mage → mage stunned N s; second hit within the window gives a shorter stun.
