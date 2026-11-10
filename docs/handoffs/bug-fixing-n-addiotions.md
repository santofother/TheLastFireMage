# bug-fixing-n-addiotions (user playtest batch) — Claude, 2026-11-10

## Done
- Spectator ghost speed 15 → 7 m/s (sprint still doubles): `spectator_tuning.gd`.
- Death rule: any hit from a player (the mage) on a downed villager kills them outright → spectator.
  Mage hits that empty hp already killed directly (no down). Downed now only comes from lethal falls;
  30 s bleed-out unchanged. `Health.apply_damage`, test added in `spectator_test.gd`.
- Stun: new `game/player/stun_stars.gd` (billboard outlined stars + swirl ring, pop-in, wobble), used by
  `Player._build_stun_fx/_update_stun_fx`.
- Bots: `bot_brain.gd` is now goal-driven: storm zone first; mage hunts nearest villager (knife, Ignite,
  Fire Wave, Locate) else chickens; villagers flee mage < 13 m, revive downed friends, roam inside zone;
  stuck → jump + sidestep. Non-Player callers keep the old wander (bot_test unit loop). `--bot-log` prints goals.
  Bots get alternating villager skins (`bot_manager.gd`).
- Lobby: player slot cards (portrait, name, skin, Host/You/Bot) for everyone, same on every peer; ‹ › on your
  own card change your villager. 6 cards, grows to MAX_PLAYERS (10) in 2 shrinking columns.
- Main menu + lobby restyled to concept-art/ui via new shared `game/ui/ui_style.gd` (SystemFont serif, no font file).

## Touched outside a card
health.gd, player.gd, match_manager.gd, menu.gd, bot_*.gd, spectator files (user-directed batch).

## Manual test
Host with 3–5 bots, start a round: mage bot should chase/kill chickens & villagers and not die in stage 1 storm.
Get stunned (bucket) → stars. Fall to downed, have the mage hit you → instant spectator. Join from a 2nd
machine and check both lobbies show the same cards/skins.

## Notes
- Button text "Host LAN" stays mixed-case: bot_menu_test finds it by text.
