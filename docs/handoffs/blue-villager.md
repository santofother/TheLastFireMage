# Blue villager — mesh on the red rig
Agent: Claude Opus 5.5 · branch `blue-villager` · no session card (task given directly by the user)
Result: DONE (not yet used by Player, see next steps)

## What exists now
- `game/player/villager/blue/blue-villager-mesh.glb`: mesh only, fresh export of Astra's `.blend`. 4 meshes, 35 joints, 0 clips, 1 m.
- `game/player/villager/blue_villager.tscn`: instances the red GLB, so skeleton, AnimationPlayer and clips are the red resources.
- `game/player/villager/villager_mesh_swap.gd`: at `_ready`, swaps the red meshes for `mesh_scene`'s. Reusable for other bodies.

## Public API
- `blue_villager.tscn`: same node layout as the red GLB. Replace `Model` under `VillagerVisual` in `player.tscn` to use it.

## How to test
- Headless: `tools/tests/blue_villager_test.sh` → `BLUE VILLAGER TEST PASSED`
- Manual (needs the user): look at the blue villager in game once it is wired into Player. Headless runs can't confirm how it renders.

## Touched outside my card
- none. Astra's files and the red clips/skeleton are unchanged.

## Contract change requested
- none

## Known issues / next steps
- Checked against red in Blender: bones, rest pose, body vertices, body weights and all 17 clips per frame are identical. No weight or mesh fixes were needed.
- Contact sheet (idle, walk, run, jump_air, carry_walk, climb, death): no stretching, clipping or floating pieces visible at 256 px per tile.
- `climb_mantle` dips 10 cm below the floor on both villagers. It comes from the clip, so it was left alone.
- Red's `.blend` has Preserve Volume on and blue's has it off. glTF and Godot skin linearly, so the game is unaffected, but Blender previews of the two differ slightly.
- `RV_Demo_Greeting` is in the shared library too; the test plays it but the game doesn't use it.
- No loop script on the blue GLB: it has no clips. Loop flags come from the red GLB's `rv_animation_import.gd`.
