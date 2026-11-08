Cause: S02's shipped controller only handled Space on the floor; no airborne mantle existed.
Fix: a fresh airborne Space press pulls onto a reachable ledge once per jump, using PlayerInput and role tuning.
Safety: landing capsule and upward/forward sweeps reject blocked paths; locks and crouch prevent the pull.
Tests: mantle fixtures cover villager/mage success, held Space, ceilings, tall walls and input locks; full suite passed.
Manual: jump against the playtest block, release Space, then press Space near the top; confirm the snap-up feels right.
