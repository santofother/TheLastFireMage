# Hillside village greybox

Open `the-last-fire-mage/project.godot` and run the game. Host LAN and choose **Explore town** in the lobby to walk the map solo. Use WASD, Space to jump or mantle, Shift to sprint, and Esc for the menu. A LAN match with a second player lets you try the mage and Fire Wave (F).

## Routes to try

- From Fish Market on the quay, follow the pale street up to Market Terrace. It doubles back and drops into the Low Ward before the climb to Chapel Square. The Weavers and Potters arcades connect side lanes beneath occupied rooms. Courtyard gardens and walled dead ends break up the blocks.
- For Salt Loft, take the Fishers stairs up to the roof and jump east through the teal second-storey window. For Bell Loft, take the Roof Walk house stairs to the roof, head to the teal window across the balcony, and sprint-jump toward the sill to mantle. Reverse each entry with a jump through the same window. Both lofts have solid floors and roofs with a separate exterior route to the roof.
- From the T-dock, walk-jump east through Gull, Otter and Evening Star. The west route runs from the dock via Sandpiper to the crescent beach and up the broad steps to the quay. The four stationary boat decks are solid from gunwale to gunwale. Sprinting can carry you past a small deck.
- A missed jump drops onto a shelf about 0.5 m below the water surface. Walk up the sand or use the east recovery steps. The greybox uses normal movement and existing fall damage, with no swimming or drowning. Beyond the shelf, the existing out-of-bounds fallback returns players to the arcade near the origin. Boats and water are static.

## Authoring

`layout.json` defines metre-scale terrain cross-sections, street bends, lanes, house placements, templates, roof links, spawns, the crescent profile, arch-supported quay and pier, and boats. House rows specify name, template, x, z, storeys, yaw, colour and optional overrides. The four template footprints are **row** (front and rear rooms), **court** (open-air garden and roofed wing), **through** (lower and upper street doors connected by stairs), and **passage** (public arcade between two shop bays with rooms above). Use `window_floor` (zero-based), `window_z` and `sill` to author a loft; update its approach and its traversal record together. Doors are usually 1.48 m wide and 2.02 m tall. Solid shutters are brown; traversable window openings have teal jambs and sills.

`generate.gd` writes the production `game/map/town.tscn` and bakes chicken navigation from collision. Static bodies use world layer 1. Doors are clear thresholds. Visible steps have smooth collision wedges. The main scene supplies lighting. A separate [prop library](../../the-last-fire-mage/game/map/props/third_party/ASSET_SOURCES.md) contains imported village building references, furniture, torches and an optional warm torch fixture.

From the repository root:

```sh
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --headless --path the-last-fire-mage --script ../tools/map/generate.gd -- --no-steam
bash tools/run_tests.sh
```

The map test feeds the real Player controller. It covers the main street, doors, stairs, two-way loft and boat traversal, water recovery, and the centre of the camera's near plane along those routes. It exercises Fire Wave damage on the boats and in the lofts, and checks sampled walkable and crouchable collision at 0.55 m spacing with the real 6 m range, aim cone and blocker layers. Grid samples are a regression check. In a manual match, check live camera angles and fast reversals around jambs, readability of both window routes, chase balance, and how players discover the water exits.

For the graphical solo-input check or a small preview:

```sh
"$GODOT" --path the-last-fire-mage --rendering-method gl_compatibility \
  res://game/map/tests/lobby_explore_test.tscn -- --no-steam
"$GODOT" --path the-last-fire-mage --rendering-method gl_compatibility \
  --script ../tools/map/overview.gd -- --no-steam
```
