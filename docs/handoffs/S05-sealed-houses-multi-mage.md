# S05 follow-up · Parkour-only roofs, sealed houses, 10 players, multiple mages

- No stairs reach a roof any more. Four one-storey houses climb from a street block and overhead plank, Fishers and Porters are jumped to from the next roof (`roof_from_neighbour`), and Dyeworks and WatchHouse use the normal window route.
- WoolHouse, FishHall and Coopers have boarded street doors. A block and ledge in the rear lane reach a top-floor window, and interior stairs lead down. `layout.json` `sealed_doors` lists them; layout is now `salmara-party-walls-v5`.
- Street-level climbs put only one 0.44 m block in a lane. Deeper or repeated low ledges cut lanes off for the mage and chicken navigation at 1.65 m widths.
- `NetworkManager.MAX_PLAYERS` is 10 and the bot limits follow it.
- The host's lobby has a "Number of mages" spinner (1 to 4, default 1). Extra mages are drawn at random and at least one villager always remains.
- `MatchManager.mage_ids()` lists every mage. `mage_id` stays as the lobby pick / first mage. Villagers win only when all mages are dead or gone.
- Mages cannot damage each other. They share one power pool and tier in `PowerManager`, every kill feeds it, and the mage win bonus goes to each mage.

## Touched outside my card
S04 match manager and scene, S09 mage abilities, S13 power manager, S16 scoring, S07 bots and menu, `core/network_manager.gd`.

## Tests
`match_test.sh` gained `two_mages`; `mage_test.sh` checks fellow mages are immune; `map_test.sh` checks every roof and sealed house.

## Manual test
- Host with 2+ mages and 8+ players: check voice load, spawn spacing and whether shared power makes the mage side too strong (`tuning_power.tres`).
- Try each sealed house and a one-storey roof without sprint to judge how hard the climb feels.
