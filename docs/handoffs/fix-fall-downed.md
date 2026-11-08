# fix-fall-downed
- A lethal FALL now "downs" the player (alive, hp 1, cannot act, death pose) instead of killing, `Health.down()/recover()`, `is_downed` synced in `health.tscn`.
- A living villager presses E near them (Interactable "Revive <name>" on every Player) -> hp = 80% max, back up.
- Tuning (`player_tuning.gd`): `fall_downs_allowed` = 1 per round (0 = falls kill), `revive_hp_fraction` = 0.8, `downed_hp` = 1.
- Downed players are still "alive" for the match; any damage (mage fire, firestorm) kills them. No bleed-out timer yet.
- Test: spectator_test.gd (down, 80% revive, second fall kills, round reset). Manual: fall from a roof with a friend, revive with E.
