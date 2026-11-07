# S14 — Firestorm
Agent: **Lean Codex** · Tier: **T2** · Wave 3 · Branch: `s14-firestorm`
Depends on: S04 (S13 for the threshold; use a stub value until merged) · Parallel with: S13 S15 S16

Owns: `game/firestorm/**`
Read: `docs/ARCHITECTURE.md` §Firestorm §GameEvents §Health, `docs/design/GDD.md` §Firestorm, handoff S04

## Goal
A shrinking safe zone that makes choices, plus the mage's "control the storm" pressure.

## Steps (all done in this one session)
- Stages over the HUNT phase: zone shrinks toward a (randomly chosen, pre-announced) final area, warnings
  before each stage. Fire outside the zone damages villagers over time.
- Required mage power rises per stage. If the mage stays below it for N seconds, the storm overwhelms them:
  damage/death → `player_died` (cause "firestorm").
- Visuals: cheap: a cylinder wall with an emissive shader + ember particles; tinted sky/fog as stages pass.
- `GameEvents.firestorm_stage(stage, center, radius, required_power, time_to_next)` and
  `firestorm_warning(next_stage, seconds_until)` for the HUD. Tint the sky via group `world_environment`.

## Tests
Headless with short timings: stages advance, a bot outside the zone takes damage, a mage below threshold dies
with cause firestorm.
