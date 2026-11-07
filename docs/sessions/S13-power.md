# S13 — Mage power + decay
Agent: **Either** · Tier: **T2** · Wave 3 · Branch: `s13-power`
Depends on: S06, S09 · Parallel with: S14 S15 S16

Owns: `game/power/**`
Read: `docs/ARCHITECTURE.md` §Power §GameEvents, `docs/design/GDD.md` §Power, handoffs S06 S09

## Goal
Kills feed the mage's fire; effectiveness decays so the mage must keep hunting.

## Steps (all done in this one session)
- Server-side power model: chicken kill +X, villager kill +Y, tiers unlocked permanently, effectiveness decays
  over time toward the tier floor (all TUNE in `tuning_power.tres`).
- Fires `GameEvents.power_changed(mage_id, power, tier, multiplier)` on all peers; MageAbilities picks up
  `multiplier` itself.
- Calls `VoiceManager.set_speaker_effect(mage_id, "mage", strength)` if S12 is merged (otherwise TODO).
- Exposes `current_power()` for the firestorm threshold (S14).

## Tests
Headless: scripted kills and time skips → power values match the tuning table within tolerance.
