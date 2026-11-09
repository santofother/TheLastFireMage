# Third-party map props

This library supplies reference buildings and optional props for the art pass. The packs use stylized medieval forms and a warm palette. The greybox collision and routes are authored separately.

- Six yellow village buildings from Kay Lousberg’s **KayKit Medieval Hexagon Pack 1.0**, CC0 1.0. [Official source](https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0)
- Chair, stool, table, barrel, crates and two torch meshes from Kay Lousberg’s **KayKit Dungeon Remastered 1.0**, CC0 1.0. [Official source](https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0)

The original license texts are included beside each pack. `kaykit_dungeon_remastered/torch_fixture.tscn` adds a warm Godot OmniLight3D to the lit torch for optional placement.
- Furniture, torches and lanterns from Quaternius **Fantasy Props MegaKit** (Standard), CC0 1.0. [Official source](https://quaternius.com/packs/fantasypropsmegakit.html)
- Trees, bushes, flowers, grass and ferns from Quaternius **Stylized Nature MegaKit** (Standard), CC0 1.0. [Official source](https://quaternius.com/packs/stylizednaturemegakit.html)

The Quaternius copies are trimmed: base-colour textures only, downscaled, with normal and ORM maps removed so they sit with the flat greybox. The twisted-tree leaf texture was recoloured from crimson to olive. `tools/map/build_props.gd` turns these models into the scenes in `game/props/`.

## Current furnishing art (replaces the Quaternius props in `game/props/`)
- Furniture, candlesticks, bowls and bottles from zappypixel's **Interior (free)**, [itch.io](https://zappypixel.itch.io/). Not CC0: free for commercial and non-commercial use and may be modified, but may not be redistributed or resold, even if modified (`zappypixel_interior/license.txt`).
- Normal and palm trees, bushes, flowers and grass from the **Ultimate Stylized Nature Pack**. The download has no licence file, so its terms are unconfirmed. Birch, pine, maple and dead trees are deliberately excluded.
