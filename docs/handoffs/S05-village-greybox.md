# S05 follow-up · Hillside village and waterfront

- Built on S16 scoring in the separate `s05-village-greybox` checkout.
- Production town now follows a 6.7 m climb with a downhill stretch, four wards and four reusable interiors.
- Salt Loft and Bell Loft have teal, two-way window-only entrances. Their roofs have separate access.
- The waterfront has stone arcades, a T-quay and dock, a partial crescent beach and four static boats.
- Misses land on a shallow recovery shelf connected to beach and quay stairs. The existing void fallback serves the outer edge.
- Edit `tools/map/layout.json` and regenerate with `tools/map/generate.gd`. The baked navigation, existing marker groups and normal town loading path remain compatible.
- KayKit building references, furniture and torches are available in `game/map/props/third_party`, with CC0 licenses and an optional warm light fixture.
- The map regression uses the real Player and Fire Wave for authored routes and special areas, plus a collision coverage grid.
- Manual playtest with two people for camera angle extremes, window and water exit readability, and chase pacing. See `tools/map/README.md` for a solo walkthrough.
