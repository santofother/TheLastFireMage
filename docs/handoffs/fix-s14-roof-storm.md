# S14 — Hidden storm destination and roof falls

- Removed the beacon and destination ring from all stages. The server picks the final center when the last shrink begins.
- The player landing code, tuning, movement test, and test runner carry `FIX(S14, Codex)`. One-story drops deal half the previous damage based on ledge height.
- Headless coverage checks early storm snapshots and one- and two-story landings. In playtest, verify that only the moving storm boundary appears from hunt start through the final shrink.
