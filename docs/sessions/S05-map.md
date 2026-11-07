# S05 — Greybox town map v1
Agent: **Either** · Tier: **T2** · Codex: GPT-6.1 Sol, high · Claude: Opus 5.5, medium · Wave 1 · Branch: `s05-map`
Depends on: S02 · Parallel with: S03 S04 S06 S07 S08

Owns: `game/map/**`, `tools/map/**` (generator)
Read: `docs/ARCHITECTURE.md` §Map, `docs/design/GDD.md` §Map §Visual style

## Goal
A ~150×150 m dense seaside neighbourhood in grey boxes, good enough to playtest hide-and-seek.

## Steps (all done in this one session)
- Build it from data, not by hand: a layout file (JSON or `.tres`) of blocks/houses/roofs/stairs + a generator
  script that writes the `.tscn` (CSG or MeshInstance+StaticBody boxes). Then the layout is cheap to edit.
- 3–4 districts, narrow alleys, plazas, a harbour edge, rooftops connected by planks/low gaps, stairs and
  mantle-height ledges (≤2 m), roof gaps sized for running jumps (~3 m, see GDD §Movement; no climbable walls), dead ends, interiors-lite (open doorways into 1-room houses), hiding nooks.
- Map rules from the GDD: every district has multiple escape routes, roof and street routes connect, the mage
  (1.4 m) can reach most areas, no permanently safe spot.
- Marker nodes in groups: `villager_spawn` (≥8), `mage_spawn` (2), `chicken_spawn` (≥10), `item_spawn` (≥10),
  `hide_spot` (≥15). Navmesh for chickens (NavigationRegion3D baked by script).
- Simple flat colours from the Salmara palette (plaster cream/peach/ochre, terracotta roofs, stone). No textures.
- A few landmark boxes where Salmara pieces (church, windmill, mole) may go later.

## Tests
Headless: load the map, count markers per group, check the navmesh has polygons. One overview screenshot at
the end (small) is allowed for the user.
