# SCHLESWIG

A Wolfenstein/Doom-like raycaster FPS written in BASIC for QB64-PE (Linux/Wayland).

## Build

From the QB64-PE root directory:

    ./qb64pe -c schleswig/Schleswig.bas -o schleswig/schleswig -x

The binary is always named `schleswig` (lowercase) inside `schleswig/`.
The repository directory and the binary intentionally share the name in
different "layers" (directory vs file), so no name collision can occur.

## Run

    ./schleswig/schleswig            # no-arg START MENU: [1] CAMPAIGN / [2] TEST ARENA
    ./schleswig/schleswig map.map    # single-map test mode (HUD: SINGLE)
    ./schleswig/schleswig campaign   # campaign from maps/levels.lst, level 1 (no menu)
    ./schleswig/schleswig --level N  # campaign starting at levels.lst position N (dev tool)
    ./schleswig/schleswig selftest   # scripted self-test, log: /tmp/schleswig_selftest.log

## Running from the QB64 IDE

F5 on Schleswig.bas (no command-line argument) opens the START MENU:
`[1] CAMPAIGN` (maps/levels.lst from level 1, HUD: LVL 1/5 ... — this is the
DEFAULT highlighted row) or `[2] TEST ARENA` (maps/default.map, HUD: ARENA).
Press 1 or 2, or move the highlight with W/S / arrow keys (W/up = row 1,
S/down = row 2) and confirm with ENTER or E.
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
- W / S: forward / back, A / D: strafe
- SHIFT: sprint (x1.25 speed) — drains the stamina bar under the HP box
  (20/s); when empty, sprint locks until stamina recovers to 30 (regen 10/s
  walking, 20/s standing still)
- Mouse: look around. NOTE (Wayland): pointer lock engages on the first mouse
  click in game (the protocol requires a user gesture)
- Left mouse button: attack / shoot (per weapon)
- Digit keys 1-5: select owned weapon (unowned = nothing happens); [ and ]: previous/next owned weapon
- Weapons: start with the AXE (melee, no ammo). Pickups in the maps:
  `y` axe, `m` musket, `f` blunderbuss (double barrel, 2-shot magazine),
  `k` machine musket, `c` mini cannon (arcing grenade, splash damage).
  Ammo pickups per type: `A` musket, `B` blunderbuss, `C` machine musket, `D` mini cannon.
  Weapons and ammo carry over between campaign levels (only a fresh round resets them;
  RESTART LEVEL keeps weapons and restores ammo to the level-segment start).
- E: open door (keys needed for 1/2/3 doors)
- R (on the death screen): restart (campaign: RESTART LEVEL = same level; arena/single: full restart to menu)
- G: debug, -5 HP
- ESC: pause/quit
- Easter egg: type `qtd` while playing for 60 s of QUANTUM MODE (the Danes'
  uncertainty principle is YOURS) — see AGENTS.md

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
`M` medkit, `A` ammo (type 1), `d` wood door (E opens), `1`/`2`/`3` = bronze/silver/gold
door (E needs the key), `b`/`s`/`g` = bronze/silver/gold key pickups,
`y`/`m`/`f`/`k`/`c` = weapon pickups (axe/musket/blunderbuss/machine musket/mini cannon),
`B`/`C`/`D` = ammo pickups types 2/3/4.
See AGENTS.md for the full table.

### Pickup color legend (6D)

Every pickup type has a UNIQUE floor-box color plus a small shape mark, so you
can tell them apart at a distance:

- Ammo `A` (musket): **yellow** box, dot mark
- Ammo `B` (blunderbuss): **orange** box, horizontal bar mark
- Ammo `C` (machine musket): **cyan** box, vertical bar mark
- Ammo `D` (mini cannon): **magenta** box, cross mark
- Medkit `M`: red box with a white cross
- Keys `b`/`s`/`g`: bronze / silver / gold colored keys
- Weapon pickups `y`/`m`/`f`/`k`/`c`: keep their own weapon color with a glint

The HUD ammo panel always shows all four pools (`AMMO  A:n  B:n  C:n  D:n`,
zeros visible), and each owned weapon in the weapon list shows its own pool
(e.g. `2:MUSKET*12`). The same panel is printed on the result, victory and
death screens.
