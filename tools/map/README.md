# S05 town authoring

`layout.json` is the source of truth. It describes four districts, house dimensions, stairs and
roof height, reserved plaza cells, landmarks, mantle ledges, nooks, spawn markers and hide spots.
Units are metres. Cream, peach, ochre, terracotta, stone and wood are flat Salmara placeholder colours.

From the repository root:

```sh
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --headless --path the-last-fire-mage --script ../tools/map/generate.gd -- --no-steam
bash tools/tests/map_test.sh
bash tools/run_tests.sh
```

The generator writes `the-last-fire-mage/game/map/town.tscn`, including a baked NavigationMesh.
Commit both the input and generated scene. Runtime never invokes the generator or rebakes navigation.
Shared meshes/shapes keep the greybox scene small; smooth collision wedges under the visible stair
risers let CharacterBody3D walk to roofs. All solid geometry is on world layer 1. Lighting lives in main.
Navigation uses the default world's 0.25 m voxels, a 0.5 m radius and 1 m height for chickens.

The 104 x 104 m footprint includes the harbour mole (52% less area than the original 150 m map).
There are 32 one-room houses in four eight-house districts, with two 2.4 x 2.6 m open doorways each.
Roof terraces descend through 4.8, 4.2 and 3.6 m elevations; 2 m wide stairs reach every height.
Mixed plaster colours, low pitched roof sections, shutters and purple banners echo the village-purple
references at greybox detail. Narrow alleys, landmark plazas, a central cross street and quay remain.
North/south sloping planks connect roof levels; east/west routes bridge upper rows and keep 3 m running jumps on the lowest row.
Four 1.6 m ledges, four dead-end nooks and 20 S10 hide spots remain available for chase choices.

Roof slabs sit above wall tops, wall corners meet edge-to-edge, bridge tops stand clear of roofs,
and stair treads stop at landing edges. Do not restore coplanar overlaps: the headless map test checks
flat box tops for overlapping area, alongside navigation and capsule traversal at every roof height.

Placeholder landmarks are named Church, Windmill, MarketStall, HarbourStore and Mole for later art swaps.
No materials use textures. Keep `test_arena.tscn` unchanged: network/match tests depend on that small map.
Playtest running jumps, sightlines, search pressure and escape-route balance with the user; these are
layout affordances, not a claim that chase balance has been established.

One small overview (rendered by a separate tool, with its own temporary lighting):

```sh
"$GODOT" --path the-last-fire-mage --rendering-method gl_compatibility \
  --script ../tools/map/overview.gd -- --no-steam
```

The overview saves `/tmp/s05-town-overview.png` and exits. It does not change the map or main scene.

For solo playtesting, open the project, press F5 and host a LAN or Steam session. Click **Explore town**
in the lobby to capture the mouse. WASD moves, Space jumps and Shift sprints; Esc opens/closes the menu
and releases/recaptures the cursor. Starting a scored round still requires two players.

The mouse-capture regression needs a graphical DisplayServer (headless Godot ignores capture requests):

```sh
"$GODOT" --path the-last-fire-mage --rendering-method gl_compatibility \
  res://game/map/tests/lobby_explore_test.tscn -- --no-steam
```

It boots the real town, hosts alone on a random port, presses Explore and exercises device input plus Esc.
Expect `[TEST] LOBBY EXPLORE PASSED`; it exits automatically without a screenshot.
