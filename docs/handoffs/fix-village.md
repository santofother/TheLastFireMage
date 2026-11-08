Cause: the first regression checked only top faces; bridge/roof and mole/rail side faces still overlapped, and the playtest checkout was still on the original map.
Fix: separate all coplanar box faces; author 24 asymmetrically placed, rotated buildings with usable 1–3 storeys and four upper entrances reached only by neighbour-roof jumps.
Validation: old revision fails the expanded six-direction overlap check; all four suites pass, including actual mage jumps, three-height stair climbs and street/upper-floor navigation.
Manual: restart the running game, orbit near roofs/bridges/quay, and climb each district's short approach building to jump into its tall neighbour; judge chase pacing.
Delivery: fix-village PR targets main with the existing town prerequisites; update the PersonalProjects/LastMage checkout to this branch while preserving local session notes and concept art.
