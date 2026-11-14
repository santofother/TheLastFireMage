# The Last Fire Mage — Game Design (distilled)
Source: `docs/LastMageBrainstorming.md.txt`. Numbers marked `(guess)` are starting points for playtests, not decisions.
Read only the section your card names. Put tunables in tuning resources (`# TUNE:`).

Pillars: chaotic, social (proximity voice), risky parkour, escalating mage, compact (small map, short rounds), distinctive (rune-fire, coastal fantasy).

## Match flow
- Up to 10 players. 1 Mage by default; the host can choose up to 4, always leaving at least one Villager. Private friend lobbies, no matchmaking.
- Villagers get a head start; the Mage doesn't know where they spawned. Then firestorm advances while Mage hunts.
- Villagers win: timer expires, or every Mage dies to the firestorm. Mages win: all Villagers dead before the timer. Mages share one power pool and cannot hurt each other.
- Final stage is a chaotic last stand.

| Number | Value |
|---|---|
| Head start | 30 s |
| Round length | 8 min (brainstorm says 8; playtest may cut to 6) |
| Players | 6 (1 Mage + 5 Villagers) |

## Roles
- Mage: knife + fire abilities, grows via kills. Villager: cannot damage the Mage, survives.
- Long-term: every player takes a turn as Mage (see Scoring).

| Number | Value |
|---|---|
| Villager height | 1.0 m |
| Mage height | 1.4 m |
| Villager health | 100 (guess) |
| Mage health | 100 (guess) |

## Movement
- Jump simple and responsive. **No climbing.** Getting up = jumps + a simple ledge mantle; getting across =
  parkour jumps between roofs, balconies and crates. Being up high exposes you; rooftops rewarding but risky.
- Falling is funny and costly; collisions cause slapstick; momentum matters; physics creates accidents.
- Hard-to-reach hiding spots are not inherently safe. Mage is powerful but not automatically faster/better.

| Number | Value |
|---|---|
| Villager walk / sprint | 4 / 6.5 m/s (guess) |
| Mage walk / sprint | 4.5 / 6 m/s (guess) |
| Jump height | ~1.2 m (guess) |
| Mantle reach (edge above feet) | up to ~2 m (guess) |
| Running jump gap | ~3 m (guess) |
| Fall damage threshold | 4 m (guess) |

## Mage combat
- Small knife, low base damage. Short-cooldown ability ignites the knife (more damage). Longer-cooldown Fire Wave.

| Number | Value |
|---|---|
| Knife damage | 20 (guess) |
| Knife swing cooldown | 0.7 s (guess) |
| Ignite duration / cooldown | 5 s / 10 s (guess) |
| Ignited knife damage | 40 (guess) |
| Fire Wave cooldown | 25 s (guess) |
| Fire Wave base damage / range | 35 / 6 m (guess) |

## Power
- Power upgrades only fire magic: damage, range, spread. Not general stats.
- Gain power by killing chickens or villagers (the kill is the sacrifice, no ritual).
- Effectiveness decays over time; unlocked tiers are never lost. Mage must keep hunting.

| Number | Value |
|---|---|
| Power per chicken | 1 (guess) |
| Power per villager | 3 (guess) |
| Tiers | 4, at 0/3/6/10 power (guess) |
| Decay | 1% of effectiveness per 5 s, floor at tier base (guess) |

## Chickens
- Roam the map with basic pathfinding, make noise. Villagers can pick up and hide them (denies Mage power). Objective for both sides.

| Number | Value |
|---|---|
| Chicken count | 10 (guess) |
| Chicken health | 1 hit (guess) |
| Noise radius | 12 m (guess) |
| Carry speed penalty | -15% (guess) |

## Firestorm
- Safe zone shrinks continuously. Mage must keep power above a threshold that rises over time; below it the firestorm kills the Mage.
- Clear warnings. Progression should force decisions, not just delete map.

| Number | Value |
|---|---|
| Storm start | 2:00 into the round (guess) |
| Zones | 4 stages (guess) |
| Required power | rises one tier per stage (guess) |
| Warning lead time | 15 s (guess) |

## Counterplay
- Villagers can't hurt the Mage but can briefly stun/disrupt via environment, teamwork, movement.

| Number | Value |
|---|---|
| Stun duration | 1.5 s (guess) |
| Stun cooldown per source | 20 s (guess) |

## Death and spectator
- Dead players become chaos agents: top-down camera, limited vision radius (fog of war), cannot see highlighted players.
- Separate overhead layer; random items spawn; collect then throw. Hit = item breaks + brief stun; miss = item stays for living villagers.
- Multiple dead can coordinate; cooldowns cap their influence. Dead keep proximity voice. Future: megaphone.

| Number | Value |
|---|---|
| Vision radius | 15 m (guess) |
| Item spawn interval | 20 s (guess) |
| Throw cooldown | 10 s (guess) |
| Item stun | 1 s (guess) |

## Voice
- Proximity chat for living and dead. Mage voice is NOT distorted (user decision 2026-11-13: it sounded glitchy online).

| Number | Value |
|---|---|
| Hearing range | 25 m (guess) |
| Dead-player range | same as living (guess) |

## Scoring
- Mage: points per villager killed + bonus for a Mage win.
- Villagers lose: points by survival time. Villagers win: win bonus + survival-time points.
- Multi-round: everyone plays Mage once, highest total wins.

| Number | Value |
|---|---|
| Mage per kill | 100 (guess) |
| Mage win bonus | 200 (guess) |
| Villager per 10 s survived | 5 (guess) |
| Villager win bonus | 150 (guess) |

## Map
- Dense, colorful seaside town. Every district has multiple escape routes; rooftops and streets connect; no hiding spot stays safe forever.
- Mage can reach most areas; firestorm creates choices; layout encourages movement.

| Number | Value |
|---|---|
| Footprint | ~120 x 120 m (guess) |
| Spawn points | 5 villager, 1 mage (guess) |

## Visual style
- Charm plus danger: small goofy characters, colorful architecture, rune-emitting fire, ominous distorted Mage, escalating magical atmosphere.
- Mage should feel ominous without being huge.

## Open questions
- Final round length (8 vs 6 min)? Exact power thresholds and decay shape?
- How do villagers stun the Mage (which environmental interactions)?
- How is the dead-player overhead layer shown and what do items do besides stun?
- Do all-dead spectators keep the match running until the timer?
- Brainstorm mentions Unreal; the project is Godot — treat networking notes there as superseded.
