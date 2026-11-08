# fix-hud-voice — S08 playtest HUD and voice fix
Cause/fix: removed overlapping legacy keybind text, kept the mic bottom left, and raised cooldowns.
Voice: raw mic PCM had no gain; added 4× (+12 dB) capture gain with clipping bounds, shared by loopback and remote playback.
Validation: tools/run_tests.sh; regression checks cover 720p/1080p/1440p clearance, quiet PCM, clipping, silence and proximity falloff.
Touched outside S08: core/debug_overlay.gd, core/voice_manager.gd and core/tests (FIX tags); contract changes: none; manual: speak normally via F4 and two nearby peers, then walk apart.
