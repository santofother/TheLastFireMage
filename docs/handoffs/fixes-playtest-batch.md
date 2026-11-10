# fixes-playtest-batch: movement feel, net stun, downed rules, revive bar
Agent: Claude Opus 5.5 · effort low · branch `fixes-playtest-batch`
Result: DONE (feel needs a playtest)

## What exists now
- Movement (`player.gd`): grounded players keep no upward speed (ramp crests and stairs no longer launch
  you or add speed), `floor_constant_speed`, `wall_min_slide_angle = 0` (a near head-on wall contact slides
  instead of sticking), and step-up ignores walkable contacts (ramps, rounded edges).
  Old code ran up 8 cm stairs ~60% faster than on flat ground; now it's ≤ flat speed with no air time.
- Net (`counter_item.gd`, `counterplay_manager.net_burst`): a thrown net opens where it hits or lands.
  Every mage within `net_radius` 2.5 m gets stunned (`net_stun` 2.5 s, longer than the bucket) and slowed.
  It's used up if it catches someone, otherwise it stays on the ground. A plain drop (G) doesn't open it.
- Stun feedback: yellow stars circle a stunned player's head (all peers). HUD shows "STUNNED".
- Downed: only villagers go down. A lethal fall kills the mage outright. Downed villagers bleed out after
  `bleed_out_time` 30 s (`player_tuning.gd`, cause `&"bled_out"`). The clock pauses while someone is
  holding revive.
- HUD centre status: reviver sees "REVIVING…" with a filling bar. A downed player sees a bleed-out countdown bar.

## Public API
- `Player.bleed_out_left`, `Player.being_revived` (all peers), `Player.stun_time_left()`,
  `Player.note_revive_hold()` (server; Interactor calls it), `Interactor.hold_progress() -> float` (owner)
- `CounterplayManager.net_burst(item, center) -> int` (server)

## How to test
- `tools/run_tests.sh` → ALL TESTS PASSED (new: ramps and stairs in movement_test, net near/far miss in
  counterplay_test, bleed-out / revive pause / mage no-down in spectator_test)
- Manual: run up town stairs and ramps (no hop or speed burst), play the mage along walls and furniture,
  throw a net at the mage's feet, go down and wait 30 s, revive someone and watch the bar.

## Known issues / next steps
- Walking (not sprinting) up box stairs with treads under ~0.3 m is slow. Town stairs are ramps, so this
  doesn't occur in the map today. Three fixes were tried; each broke another case.
- "Mage gets caught on objects" was fixed in general terms (wall slide angle, ramps). If a specific prop still
  snags, note where it is.
