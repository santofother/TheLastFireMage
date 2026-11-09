# Mage model as the default mage body
Agent: Claude Opus 5.5 (landed work found uncommitted in the main checkout) · branch `mage-skin`
Result: DONE

## What exists now
- `game/player/mage/`: animated mage GLB, `MageVisual`, loop import script, CC0 licenses.
- `player.tscn` has a `MageVisual` node; the mage shows it instead of the capsule and nose.
- `mage_abilities.gd`: confirmed casts play on the model and the flame follows the held blade.

## How to test
- Headless: `tools/tests/villager_visual_test.sh` covers the role swap.
- Manual (needs the user): play as the mage and check casts, flame position and facing.

## Touched outside my card
- `mage_abilities.gd`, `player.gd`, `player.tscn`, `villager_visual_test.gd`, tagged `FIX(mage model)`.

## Contract change requested
- none
