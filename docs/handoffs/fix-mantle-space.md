Merged: village map and manual Space mantle integrated with the latest S03 controller on main.
Behavior: S03 automatic mantle remains; a fresh airborne Space press also grabs a reachable ledge without movement held.
Safety: both paths share a one-pull-per-airtime guard; the manual path retains capsule and swept clearance checks.
Validation: run all headless tests on the combined result, including the original S03 and manual mantle regressions.
Manual: reopen this main project in Godot, press F5, Explore town, then jump and press Space again near a ledge.
