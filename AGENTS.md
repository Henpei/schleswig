# SCHLESWIG — AGENT CONVENTIONS (AGENTS.md)
Read this FIRST in every session, then follow it.

## Project
QB64-PE raycaster game (Wayland-native). Source:
schleswig/Schleswig.bas. Repo: Henpei/schleswig.
Working on: phases 4+ (enemy AI, projectiles,
weapons rendering).

## Language rules (STRICT)
- ALL commit messages: English.
- ALL new code comments: English.
- ALL in-game text: English.
- Variable/function names: English.

## Input schema
- KeyUse = universal interaction key (E) — upcoming phases reuse this
  exact check (Const KeyUse + Function KeyUseHit% in Schleswig.bas).
  SPACE is NOT a menu selector; menus select with E, mouse click works
  in parallel where applicable.

## Build (from /home/andre/QB64pe, NOT repo root)
  ./qb64pe -c schleswig/Schleswig.bas -o schleswig/schleswig -x
- Requirement: exit code 0. Shell is FISH: check
  $status, not $?.
- Compile errors land in internal/temp/compilelog.txt,
  but that file can be STALE (old attempts): trust the
  terminal "Output:"-line + exit code. Never name the
  binary the same as the source folder ("Är en
  katalog" / "is a directory" build failure).

## Run & selftest
- Run: ./schleswig/schleswig
- Selftest: ./schleswig/schleswig selftest
  → ALL phases must PASS, log:
  /tmp/schleswig_selftest.log
- Report exactly: "SELFTEST OK, n PASS / 0 FAIL".

## Every pass (workflow)
1. Read this file + the prompt.
2. Implement + bump strBuild$ (use latest commit
   hash shortform).
3. One commit, push origin/main, English message.
4. Report: changed lines (grep-proof where
   relevant), selftest status, commit hash, and a
   "SEN KLAR — André feel-test" checklist for
   hands-on verification.

## QB64-PE traps (learned the hard way)
- Variables read inside SUB/FUNCTION need DIM
  SHARED or they silently become local (=0).
- Image handles can be negative: check <> 0, not > 0.
- Wayland pointer lock: _MOUSEHIDE _DISABLE = lock
  (needs user click on Wayland); plain _MOUSEHIDE =
  hide only. NEVER use _MOUSESHOW: it was the cursor
  bug culprit. Session design: default Wayland
  cursor in main menu (before first lock), ONE
  _MOUSEHIDE _DISABLE at first fade end, no destroys
  except QuitGame.
- Procedural sound (GenSample# noise) consumes the
  global Rnd stream sample-by-sample, so Rnd is NOT
  predictable around PlaySound. For seeded/deterministic
  selftest checks use a dedicated LCG stream instead
  (see Function DodgeRnd# / dodgeSeed& in Schleswig.bas).
- _RGB32(r,g,b) sets alpha=255, so its return value is a
  NEGATIVE LONG (>= 2^31). Extract channels ALWAYS via
  _Red32/_Green32/_Blue32 — NEVER `\ 65536 Mod 256` on the
  raw value (negative long -> negative channels -> _RGB32
  clamps to 0 -> black, the 4B "black enemies" bug).
- GOSUB/labels share scope: a loop variable inside a shared
  label can clobber the caller's loop variable (the 4B
  last-kill crash, i/j case) -> use dedicated loop names per
  block (e.g. spi/aej) in any shared label.
- SINGLE-LINE IF TRAP (5D crash "subscript out of range"):
  `If a Then b: c` — c is part of the THEN clause and runs ONLY
  if a is true. NEVER put two independent clamps on one line
  (`If x0 < 0 Then x0 = 0: If x1 > RW-1 Then x1 = RW-1`) — when
  x0 >= 0 the x1-clamp is SKIPPED and wallDist(x1) goes out of
  range (that was the 5D crash: ball sprite near the RIGHT screen
  edge on the 64x64 arena). Always split clamps onto separate
  lines. Fixed at the ball-sprite clamps (bx/by, obx/oby) and the
  map-coordinate clamps (zigzag zx/zy, mortar mtx/mty).
- Map arrays (mapRow$/doorOpen%/bfsD/qx/qy) are REDIM'd to the
  ACTUAL map size in ParseMap at commit — no static map-dimension
  constant drives any loop (MAP_MAX=128 remains only as the input
  read cap for mapSrc$/mapTmp$ and the parse guard).

## PARKED (do not reactivate without André's OK)
- Virtual cursor + arrow sprite (commit aa26eee):
  vCurX/vCurY, MoveVirtualCursor, ButtonHit%,
  DrawCursor, cursorBuf&.

## Map format (.map) — Fas 5A / 5A-hotfix2
Load a map: `./schleswig/schleswig path/to/map.map`. NO arg = `maps/default.map`
— the shipped 64x64 TEST ARENA (sealed border, 20x20 center room with a mid
wall row, an L-corridor block, an 8-cell straight street; S=(32,37); every
register enemy type F/O/U/K/G placed at least once; no keys/doors). Purpose:
combat-logic testing (mortar/grenade arcs, projectile flight, dodge in tight
corridors, musket sightlines) — NOT story. WHEN A NEW ENEMY TYPE IS ADDED TO
THE REGISTER: UPDATE maps/default.map with at least one spawn of it.
The selftest does NOT run on default.map: phases 1-16 use the classic 16x16
layout written to /tmp/schleswig_selftest16.map (Const selftestMap$) —
fas18c verifies the arena instead.
`selftest` = selftest. A MAP FILE IS THE ONLY WAY — there is NO embedded
fallback map anymore (removed in 5A-hotfix2). Rows = map rows, one char per cell.
CASE-SENSITIVE parse — TRAP: 'S' = player start, 's' = silver KEY; uppercase =
enemies, lowercase = keys:
  '#' wall    '.' floor    ' ' out-of-bounds (wall in BFS/render)
  'S' player start
  'F' FOOT  'O' OFFICER  'U' MUSKETEER  'K' CAPTAIN  'G' GENERAL (enemy spawns)
  'M' medkit   'A' ammo pickup
  'd' wood door (E always opens)   '1' bronze  '2' silver  '3' gold door (E + key)
  'b' bronze key   's' silver key   'g' gold key
Row length = width, row count = height. Historical maps: at least 64x64
(shipped test map: schleswig/maps/test64.map; MAP_MAX=128 in code).
Malformed map (ragged rows / invalid char / not exactly one 'S') -> LOUD FATAL:
fullscreen "INVALID MAP: <path> line <r> col <c>: <why>. Press Q to quit."
(state$ = "fatal", Q/ESC quits) + log line. Missing file -> "MAP FILE NOT
FOUND: <path>. Press Q to quit." Same fatal path. NO silent/phantom map ever
reaches render. ParseMap stages into mapTmp$ and only COMMITS to mapRow$ on
full success (mapValid = 1) — a half-parsed grid can never reach render.
Map-declared enemies spawn as typed every wave; remaining slots are filled by
the register mix (etMinWave gating). Opened doors stay open for the round;
closed doors are walls for BFS/movement/render-hit.

## Map loading paths (5A-hotfix2)
QB64-PE sets the game process cwd to the EXECUTABLE's own directory
(schleswig/), no matter where you start it from — so map paths resolve
relative to schleswig/. The loader tries the arg as-is, then "schleswig/" +
arg (fallback for other exe locations). Works from any shell cwd:
  ./schleswig/schleswig maps/test64.map     (from QB64pe root)
  schleswig/schleswig maps/test64.map       (from repo root)
No arg -> maps/default.map (same two path forms). Build/run from the QB64pe
root (/home/andre/QB64pe).
mapRow$ is THE single map grid — every read goes via CellAt$/Solid%/OpenCell%.
LoadMapAuto always runs before the first render frame.

## Command-line arguments (5C/5D)
  schleswig                  -> NO-ARG START MENU (5D): title screen with
                                [1] TEST ARENA (maps/default.map) / [2] CAMPAIGN
                                (maps/levels.lst, level 1). Select with 1/2, or
                                W/S + arrows to highlight + ENTER/E; mouse click
                                works before the pointer lock; ESC/Q quits.
                                Same menu when run from the QB64 IDE: F5 -> pick 1 or 2.
  schleswig selftest         -> scripted selftest (mode "selftest", HUD "SINGLE")
  schleswig <file.map>       -> mode "single": that one map via the classic
                                START GAME menu, HUD "SINGLE"
  schleswig campaign         -> mode "campaign": maps/levels.lst from level 1,
                                SKIPS the menu (auto-start, AutoStartFromCmd%)
  schleswig --level N        -> mode "campaign" starting at lst position N (1-based,
                                clamped to the list; dev tool, also "--level=N"),
                                also skips the menu
"campaign"/"--level" parse via GameModeFromCmd$/LevelFromCmd%; a missing or
broken levels.lst is the SAME loud fatal as maps: "LEVELS FILE NOT FOUND: ..."
/ "INVALID LEVELS LIST line <r>: <why>" + state$ = "fatal" (Q/ESC quits).

## Campaign / levels.lst (Fas 5C)
File: maps/levels.lst — ONE level per line, format `<file.map>|<display name
(English)>`, blank lines skipped, file order = play order. DECISION: the
LAST line of the list = the end of the campaign — clearing it shows the
victory screen (never a CONTINUE). Map paths resolve like map args (as-is,
then "schleswig/" prefix). Max 20 levels.
Flow: MAP CLEARED on a non-final level -> result screen shows
"NEXT: LVL <n+1>/<total> <name>" + CONTINUE (click/E) -> pendingNext ->
LoadLevel: new ParseMap via LoadMapAuto + enemy/wave register reset via the
EXISTING SpawnEnemies with waveNo forced to 0 first (SpawnEnemies also clears
the projectile pool + BFS target) — level N's enemies/waves can never leak
into N+1. Score (shotsFired/dmgTaken/runT0 -> liveScore&) is KEPT across
levels; each level start snapshots segShots/segDmg/segT0/segStartT.
Death on level N -> RESTART LEVEL (same level reloaded, segment score
restored from the snapshot, restarts++ HUD counter) or QUIT — death NEVER
advances to the next level. Last level cleared -> state "victory": stats
table (score, killsTotal, per-level times lvlTime(), best) + PLAY AGAIN
(restart campaign at level 1, score/kills/restarts zeroed) / QUIT.
HUD mode line (HudLevelTag$): campaign "LVL <n>/<total> <name>  MAP <file>
#<gridhash>  RESTARTS <r>", single "SINGLE <file> #<hash>", arena
"ARENA <file> #<hash>".

## Placeholder campaign maps (5C, TEMPORARY)
The .map format has NO comment-line support ('#' is a wall char), so the five
shipped placeholder maps are documented here instead of in-file:
maps/level01.map..level05.map are TEMPORARY PLACEHOLDER campaign maps
("# PLACEHOLDER — REPLACE WITH CAMPAIGN MAP"): valid 16x16, exactly one S,
only valid chars, no keys/doors/weapons, small enemy mix with a difficulty
scale in the map data — level01: 2 enemies (F F, easiest) ... level05: 8
enemies (F O U K / G F F U, densest). Display names in maps/levels.lst:
The Outskirts / Village Streets / The Old Mill / Barracks Yard / The Citadel.
Vibe writes the real campaign maps later (6a+).

## Viewmodel design note (5A-hotfix2)
The viewmodel sits deliberately ~half a gun-width RIGHT of center
(Const vmOffsetX! = 0.06) — Wolfenstein/Quake design. DO NOT "fix" it to
center. Sway/bob/recoil apply to the WHOLE sprite via one gunX/gunY offset.
