# fix-fall-damage
- Cause: `player.gd` `_report_fall` only ran for jumps and used a 3.0 m threshold; walking off tall drops did nothing.
- Fix: no damage below 3.1 m (`fall_story_height`); above it, walk/sprint-off (no jump) takes reduced damage (`fall_damage_walk_off` = 3); jumps unchanged (5 / sprint 8).
- All fall damage multiplied by new `fall_damage_scale` = 2.7 (tuning in `player_tuning.gd`).
- Test: `spectator_test.gd` fall section rewritten (thresholds, walk-off, jump, sprint jump, scaling).
- `_rpc_fall` gained a `jumped` arg; client and server must run the same build.
