# S19 — Auntie villager (fourth selectable skin)
Agent: Claude Opus 5.5 · effort low · branch `s19-auntie`
Result: DONE for the auntie. The chicken carrier is still not done.

## What exists now
- `game/player/villager/auntie/auntie-purple.glb`: Astra's mesh-only body. It has 4 meshes (`Auntie_Accessories`, `Auntie_Body`, `Auntie_Face_Hair_Headband`, `Auntie_Outfit`), 35 bones and 0 clips. Textures stay embedded (default import).
- `game/player/villager/auntie_villager.tscn`: the red rig + AnimationPlayer + `VillagerMeshSwap` with this mesh, the same setup as the old man. Clips aren't copied, and the loop flags come from `rv_animation_import.gd`.
- `VillagerSkins.NAMES` is now `["Red", "Blue", "Old Man", "Auntie"]`, so skin id 3 is the auntie. Pick her with the lobby ‹ › arrows or `--villager=auntie`.
- `game/ui/art/portrait_auntie.png`: the 887² lobby portrait. It's cropped from `concept-art/auntie-purple/low-poly-front-a-pose.png`, with the beige background flood-filled to the old man's maroon (#350610).
- `docs/handoffs/S19-auntie-contact-sheet.jpg`: Astra's contact sheet (idle, walk, run, jump_air, climb_mantle).

## How to test
- Headless: `tools/tests/auntie_villager_test.sh` → `AUNTIE VILLAGER TEST PASSED`. It runs the same checks as the old man test: binds vs the red rest, 1 m height, shared clip resources, loop modes, and all clips playing with finite poses.
- Manual: host, then press › on your lobby card three times → "Auntie Villager". Watch carry_walk and death, which no contact sheet covers.

## Touched outside my card
- `game/match/match_manager.gd`: added the auntie portrait path to the S19 per-skin portrait list (one line).

## Contract change requested
- none

## Known issues / next steps
- No Blender rework was needed. Astra confirms the joint names, hierarchy and inverse binds match red, the GLB has zero animation tracks, and the Godot test re-verifies this.
- From Astra: the shoulder and trouser joints stretch locally on deep bends. The belt fold of the hip cloth clips the raised right trouser leg on climb_mantle frames 23–24. The hip cloth hangs wider than in the concept. The clips were left unedited.
