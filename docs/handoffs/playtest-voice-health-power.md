# Playtest fixes — voice, health and power
Agent: Codex · branch `codex/fix-voice-health-power` · 2026-11-08

- Voice capture gain: 4× → 12× (+9.5 dB relative); PCM remains bounded to avoid integer wrap.
- Voice full-volume distance: 3 → 8 m; silence: 25 → 45 m; gentler quadratic fade.
- Disabled AudioStreamPlayer3D.max_distance's additional attenuation; custom fade is the only distance gain.
- Both roles have a local Health bar and numeric HP; polling follows damage, healing, death, revive and sync.
- Implemented S13 power rather than leaving the visible meter connected to a zero-returning stub.
- Health HUD verified visually at 1280×720; automated bounds also cover 1080p/1440p.
- Manual voice test: two machines, normal speech at 1/8/25/45 m. Nearby speech should be clear, fade gradual,
  and speech inaudible at 45 m. Also check loud speech for clipping with the actual microphones.
- HUD safely handles power resets after multiplayer disconnect.
- Validation: all 15 suites passed via `bash tools/run_tests.sh`, including multiplayer and the 60-second soak.
- Contract changes: none. Existing API and server gameplay authority preserved.
