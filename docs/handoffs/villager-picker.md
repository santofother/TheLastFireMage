# Simple villager picker
Agent: Claude Opus 5.5 · branch `villager-picker` · no session card (task given directly by the user)
Result: DONE

## What exists now
- Menu dropdown "Villager" (Red/Blue), saved in `user://settings.cfg`, locked while in a session like the name field.
- `game/player/villager/villager_skins.gd`: the skin list and this machine's choice. Add new bodies here.
- `Player.villager_skin`: synced by the player's MultiplayerSynchronizer.

## Public API
- `VillagerSkins.NAMES`, `.local`, `.scene(id)`, `.clamp_id(id)`, `.id_from_name(text)`
- `VillagerVisual.set_skin(id)`, `VillagerMeshSwap.apply(skeleton, scene)`
- CLI: `--villager=blue` (tests; never saved to settings)

## How to test
- Headless: `tools/tests/villager_picker_test.sh` → `VILLAGER PICKER TEST PASSED`
- Manual (needs the user): pick Blue, host, and check the body in third person and from a second machine.

## Touched outside my card
- `player.gd`, `player.tscn`, `villager_visual.gd`, `menu.gd`: small additions for the skin.
- `spectator_manager.gd`: the death ghost keeps the chosen body, tagged `FIX(villager picker, Claude)`.

## Contract change requested
- none. Skin ids are client-set, which is fine for a cosmetic; they are clamped on every peer.

## Known issues / next steps
- Bots alternate Red/Blue by id.
- Only villagers have a choice; the mage has one body.
