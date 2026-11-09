# S14 playtest fix
Shrinks start at 30 s, 90 s, and 60 s before the end. Only the active 80%/60%/25% target is revealed. The last ring closes with 30 s left.
Fire Wave deals 45 base HP to players and still hits chickens. Its cooldown starts at 15 s and drops by 20% per mage tier.
A mage-only pulse marks villagers within 20 m every 4 s. Playtest beacon timing and marker visibility in town.
**Touched outside my card** — `game/mage/` for combat, locator and tests. `tools/tests/firestorm_test.sh` for stage timings.
