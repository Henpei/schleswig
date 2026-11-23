# SCHLESWIG

A Wolfenstein/Doom-like raycaster FPS written in BASIC for QB64-PE (Linux/Wayland).

## Build

From the QB64-PE root directory:

    ./qb64pe -c schleswig/Schleswig.bas -o schleswig/schleswig -x

The binary is always named `schleswig` (lowercase) inside `schleswig/`.
The repository directory and the binary intentionally share the name in
different "layers" (directory vs file), so no name collision can occur.

## Run

    ./schleswig/schleswig            # play
    ./schleswig/schleswig selftest   # scripted self-test (9 phases), log: /tmp/schleswig_selftest.log

## Controls

- SPACE or click START GAME: start the game
- W / S: forward / back, A / D: strafe (start ammo 5, max 20, ammo pickups +5)
- Mouse: look around (pointer lock is active in game)
- Left mouse button: shoot
- R (on the death screen): full restart
- G: debug, -5 HP
- ESC: quit

## Status

Early development, tagged v0.1.0 ("first playable build"): title menu,
DDA raycast rendering, HP/ammo pickups, shooting with cooldown, enemy AI
(patrol / hunt / attack state machine with LOS detection and a BFS flow
field), procedural sound (shot/hit/enemy death/pickup/hurt/detect-alert/
footsteps via a data-driven registry), death screen with highscore
(score = 10000 - 10*s - 25*shots - 50*damage, best saved to
.schleswig_scores.txt; score = 10000 - 5*s - 10*shots - 25*damage), live score
in the HUD, a win screen on kill-all
(result screen with time/shots/damage/score/best), and a 12-phase scripted
self-test.

## License

GPLv3 (planned). The license text will be attached as a LICENSE file at the
1.0 public release; the choice is decided but the file is not added yet.
