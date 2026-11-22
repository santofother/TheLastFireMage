# S19 — Old man villager (third selectable skin)
Agent: Claude Opus 5.5 · effort low · branch `s19-old-man`
Result: DONE for the old man. Chicken carrier and auntie are not done yet.

## What exists now
- `game/player/villager/elderly/elderly-villager.glb` (+ extracted `elderly-villager_cloth.png`): Astra's mesh-only body. It has 3 meshes (`Elder_Body`, `Elder_Clothing`, `Elder_Headwear_and_Face`), 35 bones and 0 clips.
- `game/player/villager/old_man_villager.tscn`: red rig + AnimationPlayer + `VillagerMeshSwap` with this mesh. Clips aren't copied, and the loop flags come from `rv_animation_import.gd` on the red GLB.
- `VillagerSkins.NAMES` now holds `["Red", "Blue", "Old Man"]`, so skin id 2 is the old man. You can pick him with the lobby ‹ › arrows or `--villager=old_man`. Bots now rotate through 3 skins.
- `game/ui/art/portrait_old_man.png`: the lobby portrait, cropped from `concept-art/villagers-low-poly/elderly-cane-villager-a-pose.png` onto the same maroon backdrop.
- `docs/handoffs/S19-elderly-contact-sheet.png`: Astra's Blender contact sheet (idle, walk, run, jump_air, climb_mantle).

## How to test
- Headless: `tools/tests/old_man_villager_test.sh` → `OLD MAN VILLAGER TEST PASSED`. It checks binds vs the red rest, the 1 m height, that the clips are the red resources, the loop modes, and that all 16 clips play with finite poses.
- Manual: host, then press › on your lobby card twice → "Old Man Villager". Play a round and look at walk/run/carry/death.

## Touched outside my card
- `game/player/tests/blue_villager_test.gd`: the paths and mesh list are now vars (FIX tag) so the old man test can extend it. Blue behaviour is unchanged.
- `game/match/match_manager.gd`: the lobby loads extra per-skin portrait files after the Red/Blue sheet (FIX tag).

## Contract change requested
- none

## Known issues / next steps
- I didn't redo any Blender work. Astra's handoff confirms the joint names, parents, rests and inverse binds match red exactly, and the Godot test re-verifies this.
- Astra's contact sheet doesn't cover carry_walk or death, so check those in game.
- From Astra's handoff: the deep mantle tuck folds the baggy trousers sharply, and the armholes look angular when the arms lift (most visible from the side). The clips were left unedited.
- The old man is a 1 m body like the others, so his hitbox and speed are unchanged. He has no cane.
