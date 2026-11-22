# S19 — Yellow chicken carrier villager (fifth selectable skin)
Agent: Claude Opus 5.5 · effort low · branch `s19-chicken-carrier`
Result: DONE. All three S19 villagers (old man, auntie, chicken carrier) are now in.

## What exists now
- `game/player/villager/chicken_carrier/yellow-chicken-carrier.glb`: Astra's mesh-only body, used as delivered. It has 4 meshes (`Carrier_Accessories`, `Carrier_Body`, `Carrier_Face_Hair`, `Carrier_Outfit`), 35 joints, 0 clips and 1 embedded image. Import params are the same as the auntie's.
- `game/player/villager/chicken_carrier_villager.tscn`: the red rig + AnimationPlayer + `VillagerMeshSwap` with this mesh. Clips aren't copied, and the loop flags come from `rv_animation_import.gd`.
- `VillagerSkins.NAMES` gets "Chicken Carrier" appended, so it's skin id 4. Pick it with the lobby arrows or `--villager=chicken_carrier`.
- `game/ui/art/portrait_chicken_carrier.png`: an 887² portrait rendered in Blender from the .blend (85 mm, upper body) on the maroon #350610 background.
- `docs/handoffs/S19-chicken-carrier-contact-sheet.png`: my render, 2 frames each of idle, walk, run, jump_air, carry_walk, climb_mantle and death.

## How to test
- Headless: `tools/tests/chicken_carrier_villager_test.sh` → `CHICKEN CARRIER VILLAGER TEST PASSED`. It runs the same checks as the old man and auntie tests.
- Manual: host, then press › on your lobby card four times → chicken carrier.

## Touched outside my card
- `game/match/match_manager.gd`: added the portrait path to the S19 per-skin portrait list (one line).

## Contract change requested
- none

## Known issues / next steps
- No Blender rework was needed. In the .blend, `RV_Rig` has the same 35 bone names as red, and its rest heads and tails differ from red's by 0.0. The meshes are 0–1.0 m tall with only an Armature modifier on RV_Rig.
- climb_mantle: the end of the red sash pokes through the raised shin for a few frames. It's minor and the clip was left unedited.
- The death frame in the contact sheet is cut off by the camera framing. The mesh itself is fine.
