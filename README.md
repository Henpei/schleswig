# SCHLESWIG

A Wolfenstein/Doom-like raycaster FPS written in BASIC for QB64-PE (Linux/Wayland).

## Build

From the QB64-PE root directory:

    ./qb64pe -c schleswig/Schleswig.bas -o schleswig/schleswig -x

The binary is always named `schleswig` (lowercase) inside `schleswig/`.
The repository directory and the binary intentionally share the name in
different "layers" (directory vs file), so no name collision can occur.

## Run

    ./schleswig/schleswig            # no-arg START MENU: [1] TEST ARENA / [2] CAMPAIGN
    ./schleswig/schleswig map.map    # single-map test mode (HUD: SINGLE)
    ./schleswig/schleswig campaign   # campaign from maps/levels.lst, level 1 (no menu)
    ./schleswig/schleswig --level N  # campaign starting at levels.lst position N (dev tool)
    ./schleswig/schleswig selftest   # scripted self-test, log: /tmp/schleswig_selftest.log

## Running from the QB64 IDE (ATT KÖRA VIA IDE)

F5 on Schleswig.bas (no command-line argument) opens the START MENU:
`[1] TEST ARENA` (maps/default.map, HUD: ARENA) or `[2] CAMPAIGN`
(maps/levels.lst from level 1, HUD: LVL 1/5 ...). Press 1 or 2, or move
the highlight with W/S / arrow keys and confirm with ENTER or E.
Mouse click also works before the pointer lock. ESC or Q quits.

A map file is the ONLY way to play — there is no embedded fallback map.
Paths resolve relative to the executable's own directory (schleswig/);
the loader also tries a "schleswig/" prefix.
Missing file -> fullscreen "MAP FILE NOT FOUND: <path>. Press Q to quit.";
invalid map -> "INVALID MAP: <path> line <r> col <c>: <why>. Press Q to quit."
(Broken maps/levels.lst in campaign mode: "LEVELS FILE NOT FOUND" /
"INVALID LEVELS LIST line <r>: <why>", same fatal screen.)

## Campaign (maps/levels.lst)

`schleswig campaign` plays the campaign list maps/levels.lst: one level per
line, `<file.map>|<display name>`; file order = play order and the LAST line
is the end of the campaign. Clearing a non-final level offers CONTINUE, which
loads the next level (score carries over, enemy/wave state is fully reset).
Clearing the last level shows the victory screen (score, total kills,
per-level times) with PLAY AGAIN / QUIT. Death offers RESTART LEVEL (same
level, per-segment score restored, restart counter in the HUD) / QUIT —
death never advances to the next level. `schleswig --level N` starts the
campaign at list position N (developer tool). A missing/broken levels.lst is
a loud fatal like map errors: "LEVELS FILE NOT FOUND" /
"INVALID LEVELS LIST line <r>: <why>". The shipped maps/level01..05.map are
temporary 16x16 placeholders (2..8 enemies, difficulty scale in the map
data) — see AGENTS.md.

## Controls

- SPACE or click START GAME: start the game
- W / S: forward / back, A / D: strafe (start ammo 15, max 20, ammo pickups +10)
- Mouse: look around. NOTE (Wayland): pointer lock engages on the first mouse
  click in game (the protocol requires a user gesture)
- Left mouse button: shoot
- R (on the death screen): restart (campaign: RESTART LEVEL = same level; arena/single: full restart to menu)
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
in the HUD, a win screen on kill-all (click to continue — Wayland locks the
mouse on that click)
(result screen with time/shots/damage/score/best), and a 12-phase scripted
self-test.

## License

GPLv3 (planned). The license text will be attached as a LICENSE file at the
1.0 public release; the choice is decided but the file is not added yet.

## Maps (.map files, Fas 5A)

    ./schleswig/schleswig maps/test64.map    # load a specific map (64x64 test map shipped)
    ./schleswig/schleswig                    # no arg = maps/default.map

`maps/default.map` is the shipped 64x64 TEST ARENA: sealed border, a 20x20
center room with a mid wall row, an L-shaped corridor block, an 8-cell
straight street, and at least one spawn of every enemy type (F/O/U/K/G).
It exists for combat-logic testing (mortar arcs, projectile flight, dodge,
sightlines), not for story. When a new enemy type is added to the register,
add a spawn of it to this map.

One char per cell, rows = map rows (CASE-SENSITIVE: 'S' start vs 's' silver key):
`#` wall, `.` floor, ` ` out-of-bounds, `S` player start,
`F`/`O`/`U`/`K`/`G` = foot/officer/musketeer/captain/general spawn,
`M` medkit, `A` ammo, `d` wood door (E opens), `1`/`2`/`3` = bronze/silver/gold
door (E needs the key), `b`/`s`/`g` = bronze/silver/gold key pickups.
See AGENTS.md for the full table.
