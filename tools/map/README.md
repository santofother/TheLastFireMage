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
Each district now lists individually placed buildings rather than generating a mirrored row/column grid.
There are 24 buildings with varied widths, depths, setbacks, quarter-turn orientations and one to three
usable storeys. Each 3.6 m storey has a room and two doorways; alternating stair sides connect floors
without placing the next flight over the previous stairwell. Roofs reach 3.6, 7.2 and 10.8 m.

Four buildings deliberately have no ground-to-first-floor stairs. Enter their upper rooms by climbing
the neighbouring one-storey building and jumping a 2 m break in a catwalk to the upper doorway.
Inside, stairs connect the remaining floors and roof. These routes work for the mage as well as villagers;
chickens do not need to navigate across jumps. The headless test actually jumps each gap with mage tuning,
checks no continuous ground nav route bypasses it, and checks navigation from the landing to each roof.

Mixed plaster, small pitched roof sections, shutters and purple banners echo village-purple at greybox
detail. Four plazas, dead-end nooks, mantle ledges and 20 S10 hide spots remain. Markers have been relocated
to the authored rooms and streets. Every ground entrance, spawn and hide spot is checked for access.

Roof slabs sit above wall tops; wall corners and stair/landing edges meet without overlaps. The quay
uses the foundation surface, and mole rails start above the deck rather than sharing its side faces.
The regression checks all six coplanar box-face directions, including quarter-turn building rotations,
not just roof tops. Player capsule climbs are checked at all three storey elevations.

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
