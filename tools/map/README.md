# Salmara: Party walls

Run the Godot project, host LAN, and choose **Explore town** in the lobby. Use WASD, Space to jump or mantle, Shift to sprint, and Esc for the menu. Start a LAN round with a second player to try the 1.4 m mage and Fire Wave (F).

- Start on the quay. Take the middle street through the attached houses; it climbs, dips and bends back toward the chapel. Try reversing direction around its tightest corners.
- Cross from the middle street to the lower lane via **Limekiln Stair**, or to the upper lane via **Potters Cut**. Their stairs run beside the stone cuts. All three streets meet again at the quay and the chapel court.
- Try **LimeHouse** or **Chapel** for a tall roof route. Take the interior stairs to the top room, step onto the teal sill, then use short, controlled jumps to the flower box, the timber plank, and the roof. From Chapel, you can jump down to the Bell Loft roof. **Dyeworks** and **WatchHouse** still have stairs all the way up. The Salt and Bell Loft windows remain two-way routes.
- On the arched pier, the small timber tide landing is the way onto Gull. Jump toward its broadside, then sprint and jump from Gull's stern to Otter. Sandpiper and Evening Star sit apart from that route. If you miss, the shallow shelf leads back to the east quay steps or up the sandy crescent.

## Authoring and verification

`layout.json` gives each lane independent (z, x, elevation, width) stations in metres. Four parcel bands occupy the ground between those lanes and the uneven cliff edges. A lot has z limits, storey count, street-facing side, room arrangement, facade colour, and roof style. Adjacent lots share a boundary; the generator samples the same bends for the street and the adjoining facade. Blank lots in that fabric are green courts. The two gaps in the middle bands are the rock cuts. The quay and chapel courts close the street loops.

Openings and terrain use world collision layer 1. Doors are 1.14 m wide and 1.76 m tall. Visible stone treads have smooth collision underneath. In `layout.json`, `tall_roof_stairs` lists the three-storey buildings that retain roof stairs. Other tall buildings get a solid roof deck and an exterior route from the top window. The hulls were built in Blender with `tools/map/build_fishing_boats.py`; Godot uses a separate collision shape for each working deck. The generator packs the collision and navigation into `town_geometry.scn` for faster loading; the game still loads `town.tscn`. The baked chicken routes are connected to the public streets.

From the village checkout:

```sh
GODOT="${GODOT:-/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --headless --path the-last-fire-mage --script ../tools/map/generate.gd -- --no-steam
bash tools/run_tests.sh
python3 tools/map/draw_plan.py ../village-brainstorm/layout-a-v7.svg
```

The map regression uses the real character controller for street, door, stair and jump traversal. Both roles test the roof jumps, and the mage checks the new window approaches and the waterfront paving seams. The test also covers spawn and navigation connectivity, camera retraction, water recovery and Fire Wave damage. A live chase is still the right test for corner visibility, pace and the feel of the two differently sized characters.

## After layout approval

- Furnish rooms at villager scale: chairs, tables, barrels and beds; add torches and lanterns. The imported [prop library](../../the-last-fire-mage/game/map/props/third_party/ASSET_SOURCES.md) already has several starting models.
- Dress the designated courts and street edges with pots, flowers, bushes and trees. Leave the authored door and stair clearances free.
