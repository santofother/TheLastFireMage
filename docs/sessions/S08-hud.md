# S08 — HUD shell
Agent: **Either** · Tier: **T3** · Codex: GPT-6.1 Sol, medium · Claude: Sonnet 5.5, medium · Wave 1 · Branch: `s08-hud`
Depends on: S02 · Parallel with: S03 S04 S05 S06 S07

Owns: `game/ui/hud/**`
Read: `docs/ARCHITECTURE.md` §UI §GameEvents, `docs/design/GDD.md` §Match flow §Power §Firestorm

## Goal
All in-round UI, driven only by `GameEvents` signals and synced values, so it works before the systems exist.

## Steps (all done in this one session)
- Role reveal banner, phase + timer, "you are blinded" overlay during head start for the mage.
- Mage: power meter with tier marks + firestorm threshold line. Villagers: carry indicator.
- Firestorm warning banner, kill feed, results screen (winner + per-player summary), scoreboard on Tab.
- Speaking indicators list (reuse VoiceManager speaking state). Interaction prompt from
  `interact_prompt_changed`; mage cooldowns from `MageAbilities.cooldown_left()` (0 until S09).
- Built in code or `.tscn`, simple readable style; scales at 1080p and 1440p.
- A debug scene/test hook that fires fake `GameEvents` so every widget can be checked.

## Tests
Headless: load HUD, fire the fake events, check no errors and the labels hold the expected text.
One small screenshot of the HUD test scene for the user at the end.
