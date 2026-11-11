# Handoff: lower-settings (graphics quality options)
**Branch:** lower-settings (not merged to main; test build only)

## Built
- `core/graphics_settings.gd` autoload `GraphicsSettings`: presets Default / Medium / Low / Potato + Custom.
  Options: shadows (Off/Low/High), FXAA, 3D render scale 50-100% (FSR), torch/lantern lights, ember particles, FPS cap.
- Default preset = original look (unchanged). Saved to `user://graphics.cfg` (own file so menu's settings.cfg can't wipe it).
- Menu: Settings page gets a GRAPHICS section (scrollable).
- `--gfx=default|medium|low|potato` forces a preset for one run without saving.
- Test: `tools/tests/graphics_settings_test.sh`.

## Not verified
- Menu layout fit and actual FPS gains were not checked on screen (headless only).

## Touched outside my card
- `game/ui/menu/menu.gd` (Graphics section), `project.godot` (autoload).

## Playtest batch (same branch)
- START ROUND now runs party mode (everyone mage once; host's mage pick goes first) via `MatchManager._on_start_pressed`.
  `[Score]` now logs when a party round refuses to start. Root cause of the "stuck after round 1" report was NOT reproduced
  (scoring_test with 3 players passes); if it recurs, send the `[Score]`/`[Match]` log lines.
- Dead players: every 15s all living players are marked on screen for 4s (`SpectatorManager._update_ping`, tuning `ping_interval`/`ping_duration`).
- Ghost-thrown items now stun living villagers as well as mages (`CounterplayManager.stun_targets`).
- Storm: living player outside the next ring gets a text ping every 10s while the zone closes (`FirestormManager._out_of_ring_ping`).
- Not verified on screen: ping marker look/clamping, the storm text.
