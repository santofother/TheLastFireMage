# fix-fall-revive
- Fall damage: `fall_damage_scale` 2.7 -> 4.5 (3-storey sprint jump now ~108, was ~65-86). Damage is height-linear, so "inconsistent" = varying drop height; tests updated.
- Revive now needs 4 s of held E (`revive_hold_time`, `Interactable.hold_time`, server-counted in `Interactor._tick_hold`; releasing/moving away resets). Added `PlayerInput.interact_held`.
- MatchManager: mage wins when every living villager is dead OR downed (hooks `Health.downed`). Knife (20) already kills a downed player (hp 1); now covered by a test.
- Not reproduced: "walking at 0 hp" - most likely a downed player showing hp 1; needs a manual check. Round-end-on-all-downed has no automated test (match_test passes).
- Env note: map_test/match_test need `rg` installed (missing on this machine; I used a grep shim).
