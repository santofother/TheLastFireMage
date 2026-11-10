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
