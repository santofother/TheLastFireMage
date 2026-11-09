# S05 follow-up · Roof routes and stamina

- Local review build on `s05-village-greybox`. The market apron and quay now meet at a shared edge, and the sea draws as one surface.
- Twelve three-storey buildings replace the final stair flight with a window, flower box and eaves plank route. Dyeworks and WatchHouse keep their roof stairs; the two-storey roof stair from RopeHouse to SaltLoft is unchanged.
- Both roles use the same stamina defaults: about 5½ seconds of uninterrupted sprinting, seven points per jump, and recovery after 0.65 seconds on the ground. The owner's HUD displays the pool in rounds and solo exploration.
- Touched S03's player controller and tuning and S08's HUD. The stamina value stays on the movement authority; the HUD reads only the local player.
- All 22 suite checks passed, including the map and movement reruns. Both roles completed the new jumps, the Fire Wave audit covered all 41,830 samples, and the graphical lobby test confirmed that sprint drains the displayed bar.
- Try walking across the market-to-quay seam, then climbing LimeHouse without holding Shift. Compare the roof route with Dyeworks' stairs and try sprinting out the full bar along the pier.
