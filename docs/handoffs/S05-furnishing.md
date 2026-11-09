# S05 follow-up · Furnishing, planting and breakable furniture

- Every storey of every house now has furniture chosen by room type from the four interior templates: kitchen, living, bedroom, storage, workshop, shop, chapel. Each room has a torch or lantern with a warm light.
- Courts, street edges, squares, the bluffs and the chapel ridge have trees, bushes, flowers, grass and potted plants. Buildings and court walls have climbing vines.
- Assets: Quaternius Fantasy Props and Stylized Nature, both CC0 (`ASSET_SOURCES.md`). Neither has vines or a medieval potted plant, so vines are generated meshes and pots are a vase plus a plant.
- Wooden chairs, stools, benches, tables, barrels, crates, cabinets and chests break into a plank pile. Sprinting into them or falling on them does it (`break_momentum` 5.0: villager walk 4, sprint 6.5). Fire Wave and ignited swings do too, charring the pile. Walls stop the flame. A new round restores everything.
- Regenerate with `tools/map/build_props.gd`, import, then `tools/map/generate.gd`. See `tools/map/README.md`.

## Touched outside the card
- Physics layer 9 `furniture` added (`project.godot`, `player.tscn` mask 275, `docs/ARCHITECTURE.md`). Flame and camera ignore it, so furniture never blocks Fire Wave or pulls the camera in.
- `player.gd` `_smash_furniture`, `player_tuning.gd` + `tuning_mage.tres` `body_mass`, `mage_abilities.gd` `burn_cone` call, `main.tscn` `Systems/Breakables`.
- `map_test.gd`: town lights are now allowed (only a sun is forbidden) and layer 9 bodies are allowed. New furnishing checks added.

## Manual test
- Host LAN, Explore town. Sprint at a chair in a ground-floor room: it should burst, and you keep running. Walk into one: it should stop you.
- As mage in a round, Fire Wave a table across a room, then check another client sees the same charred pile.
- Judge torch brightness in rooms, whether any room feels too cramped for a chase, and how chickens behave around furniture.

## Tests
`tools/tests/breakable_test.sh` covers host and client: sprint, walk, fire, wall protection, server refusal, late join, round reset. `map_test.sh` walks every door, stair and route with the furniture in place.
