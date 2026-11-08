Cause: roof/wall, stair/landing, plank/roof and quay surfaces overlapped coplanarly, causing motion-dependent z-fighting.
Fix: separated surface joins; regenerated a 104×104 m, 32-house town with three roof elevations, pitched sections, mixed plaster and purple accents.
Validation: overlap regression reproduces the old bug; map checks cover starts, hide spots, nav routes, jumps and capsule climbs at each height; full suite passes.
Manual: explore stairs/roofs while turning the camera; judge the smaller town, silhouette variety and chase pacing against village-purple references.
Delivery: fix-village targets main and includes the existing unpublished town/solo-explore commits; no contract changes or edits outside map ownership.
