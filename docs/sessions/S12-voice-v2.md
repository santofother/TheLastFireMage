# S12 — Voice v2: bandwidth, mage distortion, dead routing
Agent: **Either** · Tier: **T1** · Codex: GPT-6 Astra, medium · Claude: Opus 5.5, high · Wave 2 (can start in wave 1) · Branch: `s12-voice`
Depends on: S02 (S11 for dead routing; stub it if S11 isn't merged) · Parallel with: S09 S10 S11

Owns: `core/voice_manager.gd`, `core/voice/**`
Read: `docs/ARCHITECTURE.md` §Voice, `docs/design/GDD.md` §Voice, `core/voice_manager.gd`

## Goal
Voice that scales to 6 players over Steam relay and supports the game's voice effects, while `core/` stays
game-agnostic.

## Steps (all done in this one session)
- Bandwidth: raw PCM is ~256 kbit/s per speaker. Add compression (Opus via a maintained Godot 4.7 addon if one
  exists; otherwise a simple codec like 8-bit µ-law at 16 kHz + silence suppression). Keep RAW as fallback.
  Log kbit/s in the F3 overlay.
- Per-speaker effect hook: `set_speaker_effect(peer_id, preset, strength)` → distortion/pitch-down/reverb bus
  per speaker. The game (later S13) calls it with mage power. `core/` knows nothing about mages.
- Voice groups: `set_voice_group(peer_id, group)` + rules (e.g. dead hear everyone, living hear dead only
  nearby, or as the GDD says). Keep the rule table data-driven.
- Jitter buffer so packets arriving unevenly don't crackle.

## Tests
Headless synthetic-voice test still passes with the codec on; measured kbit/s drops ≥ 50%.
Manual for the user: Mac↔Windows talk test, mage distortion audible, dead/alive routing.
