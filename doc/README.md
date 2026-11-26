# SCHLESWIG

A Wolfenstein/Doom-like raycaster FPS written in BASIC for QB64-PE (Linux/Wayland).

## Build

From the repository root, using your local QB64-PE installation (`qb64pe`):

    qb64pe -c Schleswig.bas -o schleswig -x

The binary is always named `schleswig` (lowercase) at the repository root
(gitignored). Never assume a workdir — always read it from the task
instructions or doc/AGENTS.md; the project can be moved by the user, so no
absolute machine paths are hardcoded here.

## Run

    ./schleswig            # no-arg START MENU: [1] CAMPAIGN / [2] TEST ARENA
    ./schleswig map.map    # single-map test mode (HUD: SINGLE)
    ./schleswig campaign   # campaign from maps/levels.lst, level 1 (no menu)
    ./schleswig --level N  # campaign starting at levels.lst position N (dev tool)
    ./schleswig selftest   # scripted self-test, log: /tmp/schleswig_selftest.log
    ./schleswig replay [map.map]
                                     # replay mode: NORMAL binary + real app flow (menu ->
                                     # StartRun -> fade -> playing), OS key events simulated
                                     # from /tmp/schleswig_replay.scr, telemetry ->
                                     # /tmp/schleswig_replay.log (6G; see tools/replay_test.py)

## Real-input integration test (6G)

    python3 tools/replay_test.py path/to/schleswig

runs the normal binary headless (`replay` arg, SDL dummy drivers) through the
real menu->playing path and asserts movement/sticky/sprint from the telemetry
log. Keyboard tests must go through this real app path — the selftest's
injected variables do NOT cover the real `_KeyDown` pipeline (6G regression).

## Running from the QB64 IDE

F5 on Schleswig.bas (no command-line argument) opens the START MENU:
`[1] CAMPAIGN` (maps/levels.lst from level 1, HUD: LVL 1/5 ... — this is the
DEFAULT highlighted row) or `[2] TEST ARENA` (maps/default.map, HUD: ARENA).
Press 1 or 2, or move the highlight with W/S / arrow keys (W/up = row 1,
S/down = row 2) and confirm with ENTER or E.
Mouse click also works before the pointer lock. ESC or Q quits.

A map file is the ONLY way to play — there is no embedded fallback map.
Paths resolve relative to the executable's own directory (the canonical
repo root, where the `schleswig` binary lives); the loader also tries a
"schleswig/" prefix.
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
- SHIFT: sprint (x1.5 speed, 6F-FULL fix E; base walk speed also +30%) —
  drains the stamina bar under the HP box (max 100, 20/s); when empty,
  sprint locks immediately and regen pauses for 1 s (anti-puls), then
  stamina regens at 12/s and the lock releases as soon as stamina > 0
- Mouse: look around. NOTE (Wayland): pointer lock engages on the first mouse
  click in game (the protocol requires a user gesture)
- Left mouse button: attack / shoot (per weapon)
- Digit keys 1-5: select owned weapon (unowned = nothing happens); [ and ]: previous/next owned weapon
- Weapons: start with the AXE (melee, no ammo). Pickups in the maps:
  `y` axe, `m` musket, `f` blunderbuss (double barrel, 2-shot magazine),
  `k` machine musket, `c` mini cannon (arcing grenade, splash damage).
  Ammo pickups per type: `A` musket, `B` blunderbuss, `C` machine musket, `D` mini cannon
  (HUD ammo panel shows the WEAPON NAMES, not the letters:
  `AMMO  MUSKET:n  BLUNDERBUSS:n  MACHINE MUSKET:n  MINI CANNON:n`).
  Weapons and ammo carry over between campaign levels (only a fresh round resets them;
  RESTART LEVEL keeps weapons and restores ammo to the level-segment start).
- E: open door (keys needed for 1/2/3 doors)
- R (on the death screen): restart (campaign: RESTART LEVEL = same level; arena/single: full restart to menu)
- G: debug, -5 HP
- ESC: pause/quit
- Easter egg: type `qtd` while playing for 60 s of QUANTUM MODE (the Danes'
  uncertainty principle is YOURS) — see AGENTS.md

### Enemy types — who shoots (6F-FULL FIX D)

All types EXCEPT the weakest (FOOT) shoot when the player is in line of sight
within range (same LOS check as detection). FOOT is a pure melee charge.

| Type | HP | Shoots | Projectile | Cadence | Range | Behavior at distance |
|---|---|---|---|---|---|---|
| FOOT SOLDIER (`F`) | 4 | no — melee only | melee hit 10 | — | < 0.8 | charges |
| OFFICER (`O`) | 6 | yes | ball spd 8, dmg 8 | 1.0 s | 2–8 cells | run-and-shoot |
| MUSKETEER (`U`) | 5 | yes | ball spd 7, dmg 10 | 1.2 s | 3–5.5 cells | stops and shoots (holds ~4 cells) |
| CAPTAIN (`K`) | 12 | yes | ball spd 9, dmg 12 | 0.8 s | 2.5–7 cells | run-and-shoot |
| GENERAL (`G`) | 25 | yes | mortar, splash 1.5, dmg 25 | 2.0 s | ≤ 12 cells | stops, lobs over obstacles at predicted position |

The GENERAL (boss) shoots most aggressively. Enemy balls are slower than the
player's (dodgeable) and orange-hot with a white core; see the projectile
legend below.

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

    ./schleswig maps/test64.map    # load a specific map (64x64 test map shipped)
    ./schleswig                    # no arg = maps/default.map

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
- Ammo `C` (machine musket): **light blue** (RGB 110,170,255) box, vertical bar mark
- Ammo `D` (mini cannon): **magenta** box, cross mark
- Medkit `M`: red **square** box with a centered white cross (square = distinct
  from the rectangular ammo boxes)
- Keys `b`/`s`/`g`: bronze / silver / gold colored keys
- Weapon pickups `y`/`m`/`f`/`k`/`c`: keep their own weapon color with a glint

The HUD ammo panel always shows all four pools (`AMMO  A:n  B:n  C:n  D:n`,
zeros visible), and each owned weapon in the weapon list shows its own pool
(e.g. `2:MUSKET*12`). The same panel is printed on the result, victory and
death screens.

### Projectile colors (6F)

- Player balls: plain **white** (7-12 px, distance-scaled) with a dark 1 px rim
- Enemy balls (musketeer): **hot orange glow** (5-9 px, >= 1.5x the old 2-3 px)
  with a **white-hot core** and the same dark rim — clearly a different color
  from the player's white balls, visible at range
- Mortar grenades: dark red in flight; blinking amber ring (enemy) / cyan ring
  (player mini cannon) at the landing cell
