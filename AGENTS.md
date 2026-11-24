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
- MOVEMENT COORDINATE TRAP (5E — THE "invisible walls" bug): the
  vertical movement check must be
  `OpenCell%(Int(px), Int(ny + Sgn(ny-py)*0.2))` — it was
  `OpenCell%(Int(ny + Sgn(ny-py)*0.2), Int(px))` (x/y SWAPPED), so
  vertical moves were blocked by whatever wall happened to sit at
  (y-candidate, x-current) — phantom invisible walls at static
  spots. Fixed in all 4 movement blocks (mvF/mvB/mvL/mvR); guarded
  permanently by selftest 5e-c (BFS==OpenCell + real walk-bot).

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
  'M' medkit   'A' ammo pickup TYPE 1 (musköt)
  'd' wood door (E always opens)   '1' bronze  '2' silver  '3' gold door (E + key)
  'b' bronze key   's' silver key   'g' gold key
6A WEAPON/AMMO CHARS (6A — same normalize-to-'.' rule, no collisions with the
chars above; lowercase = weapon pickups, uppercase = ammo pickups):
  'y' YXA (axe, melee)   'm' MUSKÖT   'f' BLUNDERBUSS   'k' MASKINGEVÄR   'c' MINI-KANON
  'B' ammo type 2 (blunderbuss)   'C' ammo type 3 (maskingevär)   'D' ammo type 4 (mini-kanon)
  ('A' stays ammo type 1 = musköt.)
6B CASE-SENSITIVITY (empirically verified — do NOT "fix"): QB64-PE string
comparisons (=) and Select Case are CASE-SENSITIVE (test program: 'k' matches
Case "k", not Case "K"; "d" = "D" is FALSE). So the pairs 'k' (weapon) vs 'K'
(captain) and 'd' (door) vs 'D' (ammo type 4) are distinct by construction;
selftest 6b-c1/c2 prove both pairs on a temp map AND on level03/default.map.
Weapon pickups render on the floor as small squares in the weapon's register
color (wpCol&) — 6A originally had no floor sprite for them (invisible pickup).
Row length = width, row count = height. Historical maps: at least 64x64
(shipped test map: schleswig/maps/test64.map; MAP_MAX=128 is only the input
read cap — the committed arrays are REDIM'd to the real map size in ParseMap).
5E CHAR SEMANTICS (single source): ParseMap NORMALIZES every spawn/item char
(S/F/O/U/K/G/M/A/b/s/g) to '.' at commit, so a parsed grid only ever contains
'#', '.', ' ' (OOB=wall) and door chars. WallChar%/DoorChar% own the meaning of
a char; Solid% (built on them) is the ONLY collision/render query — render
DDA, LOS, projectiles, BFS and movement all go through it, so render and
collision can never disagree (no invisible walls). ParseMap also counts
leftover non-normalized cells into mapBadN (must be 0); Const dbgCellScan=1
shows a HUD debug line "BADCELLS n".
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
  schleswig                  -> NO-ARG START MENU (5D/6B): title screen with
                                [1] CAMPAIGN (maps/levels.lst, level 1 — DEFAULT
                                highlight, selIdx starts at 1) / [2] TEST ARENA
                                (maps/default.map). Select with 1/2, or
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

## Placeholder campaign maps (5C/6A, TEMPORARY)
The .map format has NO comment-line support ('#' is a wall char), so the five
shipped placeholder maps are documented here instead of in-file:
maps/level01.map..level05.map are TEMPORARY PLACEHOLDER campaign maps
("# PLACEHOLDER — REPLACE WITH CAMPAIGN MAP"): valid 16x16, exactly one S,
only valid chars, small enemy mix with a difficulty scale in the map data —
level01: 2 enemies (F F, easiest) ... level05: 8 enemies (F O U K / G F F U,
densest). 6A weapon/ammo placement: level01 'm' (MUSKÖT) next to S + A;
level02 'f' (BLUNDERBUSS) next to S + B; level03 'k' (MASKINGEVÄR) next to S
+ C; level04 'c' (MINI-KANON) next to S + D; level05 two 'D' cells near S
(densest enemies). The 64x64 TEST ARENA (maps/default.map) is the test kitchen:
row 2 holds all five weapon chars y/m/f/k/c, row 3 holds B/C/D next to A.
Display names in maps/levels.lst:
The Outskirts / Village Streets / The Old Mill / Barracks Yard / The Citadel.
Vibe writes the real campaign maps later.

## Ammo balance (5E + 6A)
Const startAmmo = 15 (was 5 — ~3x, André ran dry before level 3),
Const ammoPickup = 10 per ammo pickup (was +5). 6A: ammo is PER TYPE —
ammoN(1..4) with per-type caps capAmmo: typ1 (musköt) = maxAmmo = 20,
typ2 (blunderbuss) = 6, typ3 (maskingevär) = 24, typ4 (mini-kanon) = 4.
Pickup chars: A=+10 typ1, B=+10 typ2, C=+10 typ3, D=+10 typ4 (capped).
Placeholder A-cell counts follow "~1 A per 2 enemies" with the enemy curve
2/3/4/6/8 untouched: level01..05 have 1/2/2/3/4 type-1 A cells (1 M each),
plus one typed-ammo cell of the level's weapon (level02 B, level03 C,
level04 D, level05 D x2 near S).

## Weapon system (6A) — data-driven register
Same pattern as the enemy register (InitEnemyTypes -> InitWeapons fills
wpName$/wpDmg/wpCool!/wpRecoil!/wpShake!/wpSpread!/wpPellets/wpAmmoT/wpMag/
wpReload!/wpMelee/wpArc/wpBallSpd!/wpCol&/wpSplashR!/wpSplashDmg per weapon;
balance changes WITHOUT code-logic changes). WP_AXE=0, WP_MUSKET=1,
WP_BLUNDER=2, WP_MG=3, WP_CANNON=4 (WP_COUNT=5).
  AXE: melee, NO ammo, dmg 8, cooldown 0.8 s, swing anim 3 frames, hit =
    cone in front (~1 cell, ~45°); enemy melee-dodge uses the LOWER
    etDodgeMelee! per type (FOOT 0.1 ... GENERAL 0). Start weapon.
  MUSKET: unchanged mechanics (dmg 1/ball, cooldown 0.3 s, ball speed 6,
    ammo type 1). Reference viewmodel sprite (Fas 4C, unchanged).
  BLUNDERBUSS: 4 pellets in a cone (spread 0.32 rad), dmg 1/pellet, cooldown
    0.9 s, ammo type 2, MAGAZINE 2 (dubbelpipa) + reload 1.2 s from the pool.
    NOTE: integer damage makes "40-50% of musket per pellet" impossible
    (musket=1 -> 0.5); we use 1 dmg/pellet and realize the intent via pellet
    count + spread (brutal up close, weaker per pellet at range).
  MACHINE GUN (maskingevär): cooldown 0.08 s (3-4x musket), dmg 1, faster
    ball (10), spread grows with distance (+0.015 rad/cell), ammo type 3.
  MINI CANNON: reuses the enemy MORTAR (arc + flight 1.2 s + splash), but
    prOwner=0 (player); target = the crosshair DDA hit cell (telegraphed);
    splash radius 1.5, dmg 25 with linear falloff; cooldown 1.5 s, heavy
    recoil+shake; ammo type 4. Splash CAN hurt the player up close (radial
    risk documented) but not at safe distance.
Ammo model: ammoN(AMMO_N) per type (ammoN(1) = the old 'ammo' musket pool).
HUD: ammo box shows the CURRENT weapon's ammo (magazine "n/m" for the
blunderbuss, pool count otherwise, "--" for the axe); weapon list row above
the HP box shows only OWNED weapons "1:AXE*" (selected marked *), QTD badge.
Controls: digit 1-5 = select owned weapon (unowned = NOP), [ ] = prev/next
owned. Weapon switch plays a ~0.15 s lowering animation (wpSwitchT!).
PERSISTENCE DECISION: LoadLevel (CONTINUE / RESTART LEVEL) does NOT touch
wpOwned/wpCur/ammoN — weapons AND ammo carry over between campaign levels.
Only StartRun (a fresh round from the menu / PLAY AGAIN) resets the register
to AXE + startAmmo. On RESTART LEVEL (death) the ammo pools are restored
from the per-level-segment snapshot segAmmoN (same principle as the score
snapshot segShots/segDmg); owned weapons are kept.
Viewmodels: gunBuf&(WP_COUNT) — ONE procedural sprite buffer per weapon
(DrawWeaponSprite), same vmCX/vmOffsetX/sway/bob/one-blit-offset pattern
(18b) for all; musket = the unchanged reference sprite. Per-weapon recoil
(wpRecoil!) and shake (wpShake!): axe swing, blunderbuss wide kick, MG small
quick kicks, cannon heavy screen shake.

## QTD easter egg (6A — PERMANENT official joke feature)
Type "qtd" on the keyboard while playing (last-3-keys buffer qtdBuf$) ->
quantum mode for qtdDur! = 60 s: HUD message "QUANTUM MODE ENGAGED —
danskarnas osäkerhetsprincip är DIN", enemy dodge rolls get x3 threshold and
the dodge becomes an instant sideways TELEPORT (the normal dodge is a glide —
see below). Auto-off after 60 s. Documented here as a permanent feature.

## Dodge = glide, not teleport (6A)
EnemyDodge now sets a glide target (enDodgeSX!/SY! -> TX!/TY!, 0.2 s) instead
of teleporting; pass 2 interpolates in <=0.3-cell sub-steps with OpenCell%
checks (monotonic, never inside a wall, never a >0.5-cell frame hop).
Exception: QTD quantum mode teleports (the joke).

## Menu render gating (6B FIX F — no menu blink between levels)
The title/pick menu is rendered ONLY when state$ is still "menu" at render
time (inside the menu/fadeout branch). pendingStart (VIDARE / paus-RESTART),
pendingNext (campaign CONTINUE) and PickAction are handled BEFORE the render
in the same frame and switch state to "fadeout" — so result->CONTINUE,
death->RESTART, victory->PLAY AGAIN and pick never render a single menu frame.
Instrumentation: menuRenderN counts real menu renders; selftest 6b-d asserts
menuRenderN is UNCHANGED across all those transitions (and that it DOES increase
at a real title screen — positive control).

## Viewmodel design note (5A-hotfix2)
The viewmodel sits deliberately ~half a gun-width RIGHT of center
(Const vmOffsetX! = 0.06) — Wolfenstein/Quake design. DO NOT "fix" it to
center. Sway/bob/recoil apply to the WHOLE sprite via one gunX/gunY offset.
