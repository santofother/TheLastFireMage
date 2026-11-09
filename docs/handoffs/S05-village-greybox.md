# S05 follow-up · Salmara: Party walls

- Local review build on `s05-village-greybox`; uses the existing production town path.
- Three narrow winding lanes define attached parcels with mixed room plans, storeys and roof shapes. The broad foot of the hill and the chapel court connect the lanes at either end.
- Two staggered rock cuts give direct, steep ways between streets; the middle lane climbs more gently and dips locally.
- Multi-room floors, open stairwells, and two-way Salt Loft/Bell Loft window entrances. The loft roofs are connected separately to neighbouring roofs.
- The arched quay and pier stay. A larger crescent grades down through wet sand and into shallows, and original Blender fishing boats replace the blocks.
- Regenerate from `tools/map/layout.json` using `tools/map/generate.gd`. See `tools/map/README.md` for routes, the generated review plan, and verification commands.
- Playtest the tight bends and the cuts with both roles before dressing interiors or planting the courts. Furniture, torches, lanterns, pots, flowers, shrubs and trees are the next pass.
- Outside S05 ownership: the ENet sync test uses the stable test arena for its fixed coordinates. The separate lobby check still loads the real village.
- Map and graphical lobby checks pass. The mage walks all lanes, stairs and room doors; the Fire Wave audit covered all 41,504 sampled positions.
