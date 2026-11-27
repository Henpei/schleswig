# SCHLESWIG — AGENT CONVENTIONS (AGENTS.md)
Read this FIRST in every session, then follow it.

## Project
QB64-PE raycaster game (Wayland-native). Source:
schleswig/Schleswig.bas. Repo: Henpei/schleswig.
Working on: pre-release polish (6L-B cap visibility + starvation-zero
L3-L5 ammo balance + full selftest suite gate before public release).

## Language rules (STRICT)
- ALL commit messages: English.
- ALL new code comments: English.
- ALL in-game text: English.
- Variable/function names: English.
- ALL agent prompts/assignments: English. Swedish user context may be
  quoted verbatim, but instructions, requirements, and acceptance criteria
  MUST be unambiguous English.

## Input schema
- KeyUse = universal interaction key (E) — upcoming phases reuse this
  exact check (Const KeyUse + Function KeyUseHit% in Schleswig.bas).
  SPACE is NOT a menu selector; menus select with E, mouse click works
  in parallel where applicable.

## Build (CANONICAL workdir = /home/andre/Dokument/Projekt/schleswig — the repo root)
  cd /home/andre/Dokument/Projekt/schleswig
  /home/andre/QB64pe/qb64pe -c Schleswig.bas -o schleswig -x
- The compiler binary lives at /home/andre/QB64pe/qb64pe — that is the
  COMPILER's home, NOT the project. Any build area next to the compiler
  installation is André's manual playground: agents must never read or
  write there.
- MIGRATION LESSON (6G migration pass): NEVER assume a workdir — always read
  it from the task instructions or this AGENTS.md; the project can be moved
  by the user at any time.
- BEFORE THE REPOSITORY BECOMES PUBLIC: generalize all machine-specific
  paths (this section included) — absolute /home/ paths must not ship.
- Requirement: exit code 0. Shell is FISH: check
  $status, not $?.
- Compile errors land in internal/temp/compilelog.txt,
  but that file can be STALE (old attempts): trust the
  terminal "Output:"-line + exit code. Never name the
  binary the same as the source folder ("Är en
  katalog" / "is a directory" build failure).
- The binary lands at <repo>/schleswig (ELF, gitignored via /schleswig);
  run it as ./schleswig from the repo root (QB64-PE sets the process cwd
  to the executable's own directory, so maps/ and the font resolve there).

## Run & selftest (from the canonical workdir)
- Run: ./schleswig
- Selftest: ./schleswig selftest
  → ALL phases must PASS, log:
  /tmp/schleswig_selftest.log
- Report exactly: "SELFTEST OK, n PASS / 0 FAIL".
- KNOWN PRE-EXISTING FAILURE (not a timing flake; observed identical on
  4552e33 and e93da7b, so NOT introduced by 6L-B): fas14c-dodge fails with
  "seeded shot never landed: enHP=6 ammoN(1)=0" and the suite stops there.
  Known timing flakes: fas15a, 6e-c, 5e-d — document, do not "fix".

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
Load a map: `./schleswig path/to/map.map`. NO arg = `maps/default.map`
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
(the canonical repo root, where the binary lives), no matter where you start
it from — so map paths resolve relative to the repo root. The loader tries
the arg as-is, then "schleswig/" + arg (fallback for other exe locations).
Works from any shell cwd:
  ./schleswig maps/test64.map     (from the canonical repo root)
No arg -> maps/default.map. Build/run from the canonical workdir
(/home/andre/Dokument/Projekt/schleswig) — see the Build section above.
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

## Campaign maps (6C v1.0 / 6D v1.2 — REAL, Vibe-designed 64x64)
maps/level01..05.map are the REAL campaign maps (Vibe-designed, machine-
validated; design doc: maps/SCHLESWIG-CAMPAIGN-MAPS-README.md). All 64x64,
sealed border, exactly one S, ONLY existing chars (# . S F O U K G M A B C D
y m f k c b s g 1 2 3). levels.lst:
  level01.map|The Outskirts          v1.2 (6D): LOCKED HALVES — wall row y=33 with a
                                     2-wide bronze gate '1' at (31,33)+(32,33) (+ bonus
                                     shed door '1' at (40,44)); S=(32,59), bronze key
                                     'b'=(32,40) on the south street; musket 'm'=(31,30)
                                     and F x2 NORTH (18,17),(46,26), F x1 south (19,45);
                                     A x4, M x1, doors '1' x3. Clearing REQUIRES opening
                                     the gate (selftest 6d-e: BFS with doors closed
                                     reaches 0 cells north of y=33 and neither northern
                                     F; key b reachable south without doors; gate open
                                     -> >100 north cells reachable).
  level02.map|The Smugglers' Cellar  v1.2 (6D): LOCKED HALVES — wall row y=33, 2-wide
                                     silver gate '2' at (31,33)+(32,33) (+ '2' at
                                     (53,16) north); S=(32,59), silver key 's'=(17,45)
                                     south; blunderbuss 'f'=(31,30) + F(18,22) + O x2 +
                                     U x1 NORTH, F x2 south; B x4 A x3 M x2, doors '2' x3.
  level03.map|The Outer Rampart      F x4 O x2 U x2, 'k', A/B/C
  level04.map|The Moat Crossing      F x4 O x3 U x2 K x1, 'c', A/B/C/D
  level05.map|The Citadel            F x5 O x3 U x3 K x2 G x1, gold 'g' + doors '3' x2,
                                     G+Kx2 inuti guld-sanktuarium, D-ammo rik (x3)
Ammo principle: every level carries ammo for ALL weapons ownable at that point
(L1 A / L2 A+B / L3 A+B+C / L4 A+B+C+D / L5 D-rich). Keys are always reachable
BEFORE their door (flood-fill/BFS proven; selftest 6c-a re-proves per map with
doors closed). level05's general G is the campaign finale; his death registers
in killsTotal (selftest 6c-c1). Edge note: a locked door without its key stays
shut ("NEED ... KEY") — by design the key is always reachable first, so no
lockout is possible. default.map (64x64 TEST ARENA) is untouched: row 2 all
five weapon chars, row 3 B/C/D next to A — the test kitchen.

## Ammo balance (5E + 6A + 6H + 6L-B)
Const startAmmo = 15. 6A: ammo is PER TYPE — ammoN(1..4). 6H: per-type pickup
amounts amPickup(AMMO_N) = 10/4/12/2 (A=musköt, B=blunderbuss, C=maskingevär,
D=mini-kanon) and per-type caps capAmmo = 40/16/48/12 (B 12->16, D 8->12 in 6H).
Pickup chars: A=+10 typ1, B=+4 typ2, C=+12 typ3, D=+2 typ4 (capped).
6L: pickup message is per-type — hpMsg$ = "+"+amPickup(t)+" "+AmmoTypeName$(t)+" AMMO".
6L-B: cap visibility — pool already at cap -> "<NAME> AMMO FULL"; partial
truncation -> "+<actual gain> <NAME> AMMO (FULL: +<lost> lost)"; normal pickup
without truncation -> the unchanged 6L message (always the pickup's amount).
6C real maps (measured char counts, selftest 6b-f re-proves >= principle):
level01 A x3 M x1; level02 A x3 B x3 M x2; level03 A x5 B x2 C x2 M x2;
level04 A x6 B x1 C x2 D x1 M x2; level05 A x4 B x1 C x1 D x3 M x2 — every
level carries ammo for ALL weapons ownable at that point (L1 A / L2 A+B /
L3 A+B+C / L4 A+B+C+D / L5 D-rich + A+B+C+M). (The old 5E placeholder counts
1/2/2/3/4 A-cells are superseded by the real maps.) 6H STEG 5 audit added
A-pickups on L3/L4/L5 after the audit bot showed pool-A starvation; 6L-B
PART 2 (starvation-zero) added +1 A at (32,58) — the start corridor the bot
walks over from S=(32,59) — on L3/L4/L5 (L4: also removed A(57,30)/B(57,34),
which the spAmN<10 spawn cap silently dropped, and one redundant D(19,52),
so the new A stays within the 10-pickup cap). Audit x2 after the change:
L3/L4/L5 poolMin A = 8..28, starveEvents = 0 on all levels.
NOTE: the ammo spawn pool caps at 10 per map (spAmN < 10 in ParseMap) —
ammo chars beyond the first 10 in row-major order are normalized but never
spawn; keep per-map ammo char count <= 10.

## Weapon system (6A) — data-driven register
Same pattern as the enemy register (InitEnemyTypes -> InitWeapons fills
wpName$/wpDmg/wpCool!/wpRecoil!/wpShake!/wpSpread!/wpPellets/wpAmmoT/wpMag/
wpReload!/wpMelee/wpArc/wpBallSpd!/wpCol&/wpSplashR!/wpSplashDmg per weapon;
balance changes WITHOUT code-logic changes). WP_AXE=0, WP_MUSKET=1,
WP_BLUNDER=2, WP_MG=3, WP_CANNON=4 (WP_COUNT=5).
  AXE: melee, NO ammo, dmg 3, cooldown 1.2 s (6D FIX E: was 0.7 — at >=2 cells
    the musket (4 x 0.3 s + travel ~1.07 s) now beats the axe (2 hits = 1.2 s);
    6B-KOMPLETT: dmg was 8 / cd 0.8 — a foot soldier HP 4 now SURVIVES one hit
    with 1 HP margin, no one-shot),
    swing anim 3 frames, hit = cone in front (~1 cell, ~45°) aimed along the
    aim angle; enemy melee-dodge uses the LOWER etDodgeMelee! per type
    (FOOT 0.1 ... GENERAL 0). Start weapon.
  MUSKET: unchanged mechanics (dmg 1/ball, cooldown 0.3 s, ball speed 12
    (6D FIX D: was 6 — ~2x, still visible projectiles, NOT hitscan),
    ammo type 1). Reference viewmodel sprite (Fas 4C, unchanged).
  BLUNDERBUSS (6B-KOMPLETT, option iii = combination): 6 pellets x dmg 2 in a
    TIGHTER cone (spread 0.18 rad, was 4 x 1 @ 0.32), cooldown 0.9 s, ammo
    type 2, MAGAZINE 2 (dubbelpipa) + reload 1.2 s. Ball hit radius is 0.35
    cell, so at <2 cells >=2 pellets connect = >=4 dmg = kills a foot (HP 4)
    on a full hit; the spread IS the range falloff (fewer pellets connect far
    away). Brutal up close, weak per pellet at range.
  MACHINE MUSKET (maskingevär; 6B-KOMPLETT FIX G renamed from "MACHINE GUN"
    everywhere — HUD weapon list via wpName$, README, this file; sprite,
    mechanics and the 'k' pickup char are UNCHANGED): cooldown 0.08 s
    (3-4x musket), dmg 1, faster ball (16 — 6D FIX D, was 10; musket is 12),
    spread grows with distance (+0.015 rad/cell), ammo type 3.
  MINI CANNON: reuses the enemy MORTAR (arc + flight 1.2 s + splash), but
    prOwner=0 (player); target = the crosshair DDA hit cell; splash radius
    2.0 (6B-KOMPLETT FIX C: was 1.5 — covers a whole corridor crossing; the
    ENEMY general's mortar keeps etSplashR 1.5), dmg 40 with linear falloff (6E FIX F: var 25);
    cooldown 1.5 s, heavy recoil+shake; ammo type 4. Splash CAN hurt the
    player up close (radial risk documented) but not at safe distance.
    6B-KOMPLETT FIX C: ONE shared aim computation — CrosshairDDA (center-ray
    DDA -> chd!) + CannonAim (chd! -> clamped target cell mtx2/mty2) — used
    by BOTH firing (spTX/spTY) and the LIVE landing marker rendered every
    frame while the cannon is selected (steady cyan ring + crosshair dot at
    the floor-projected target cell, unlike the blinking in-flight mortar
    telegraph). No duplicate code. Selftest 6b-b proves a fired grenade
    lands within +/-0.5 cell of the computed target.

## Balance reference (6B-KOMPLETT + 6D FIX E) — time-to-kill FOOT SOLDIER (HP 4) at optimal range
  AXE            dmg 3 / 1.2 s   -> 2 hits, kill at ~1.2 s (6D: cd 0.7->1.2 so the
                                    axe is NOT strictly best at ALL ranges)
  MUSKET         dmg 1 / 0.3 s   -> 4 balls, kill at ~0.9 s + travel; at >=2 cells
                                    (~1.07 s total) the MUSKET beats the axe (1.2 s)
  BLUNDERBUSS    full hit <2 cells >= 4 dmg -> 1 shot (~0.9 s, +1.2 s reload / 2 shots)
  MACHINE MUSKET dmg 1 / 0.08 s  -> 4 shots, kill at ~0.24 s
  MINI CANNON    splash 40 (6E FIX F: var 25) -> foot dör av 1 granat i splash; K kräver 2 vid splash-kant (pd 1.7 ger 8/granat)
  (Enemy register 6B-KOMPLETT: etHP(ET_FOOT) 3 -> 4 — required so the axe
  dmg 3 does NOT one-shot a foot; fas14a asserts the new value.)

## Ammo isolation (6B-KOMPLETT FIX G — verified, line evidence)
  Fire decrements ONLY the current weapon's pool: `ammoN(wat) = ammoN(wat) - 1`
  with wat = wpAmmoT(wpn) (Schleswig.bas fire block; magazine weapons decrement
  wpMagNow instead). MUSKET = pool 1 (A), MACHINE MUSKET = pool 3 (C) —
  separate pools, no cross-drain. Pickup adds ONLY the pickup's own type:
  `ammoN(at2) = ammoN(at2) + ammoPickup` with at2 = amT(i) (A/B/C/D -> 1/2/3/4),
  capped at capAmmo(at2). Selftest 6b-e proves: musket fire A-1 & C unchanged;
  MG fire C-1 & A unchanged; A pickup loads only pool 1; C only pool 3; B/D
  parity incl. caps.
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

## SCHLESWIG 6D — aim, HUD panel, pickup colors, speeds, score model
FIX A (aim, ONE source): after `angle = angle + mmx * mouseSens * speed` the
  dirX/dirY pair is recomputed from the SAME angle in the same frame
  (`dirX = Cos(angle): dirY = Sin(angle)`), so render, crosshair DDA,
  player projectiles (ball dir = cos/sin aim, blunderbuss cone spreads around
  aim, axe cone aims along aim), mini-cannon target and melee all use ONE aim
  angle per frame. Selftest 6d-a: projectile per-frame delta == (cos,sin) of
  aim within 0.01 and hits an enemy placed 3 cells along the aim ray.
FIX B (HUD ammo panel): BuildAmmoHud builds `ammoHud$ = "AMMO  A:n  B:n  C:n
  D:n"` — ALWAYS all four pools, zeros visible; printed in the HUD and on the
  result/victory/death screens. The weapon list shows each owned weapon's OWN
  pool (`2:MUSKET*12`, axe `--`, magazine `n/m`). Selftest 6d-b asserts the
  panel text across fire/pickup.
FIX C (pickup readability): amCol&(1..4) — A yellow (255,220,0), B orange
  (255,120,0), C light blue (110,170,255) (6G eye-dom: was cyan 0,220,255),
  D magenta (255,0,200) — each ammo box is
  drawn in its type color plus a shape mark (A dot, B horizontal bar, C
  vertical bar, D cross); medkit stays red+cross, keys bronze/silver/gold,
  weapon pickups keep wpCol& + glint. README has the color legend table.
  Selftest 6d-c: pairwise-unique colors + distinct from medkit/key colors +
  README legend matches.
FIX D (projectile speed): plrBallSpd! 6 -> 12 (~2x, still visible
  projectiles, NOT hitscan); machine musket ball 10 -> 16 (> musket);
  ENEMY musketeer ball 5 -> 7 (proportionally up but still SLOWER than the
  player's 12 — fairness, dodgeable). Selftest 6d-d measures a real ball.
FIX E (axe balance): wpCool!(WP_AXE) 0.7 -> 1.2 s. TTK table updated above:
  at >=2 cells musket (~1.07 s incl. travel) beats axe (1.2 s); the axe stays
  best only in melee range. Selftest 6a-a register assertion updated to cd 1.2.
FIX F (v1.2 campaign maps): level01/02.map replaced — locked halves with
  gate + weapon + enemies behind the gate (see Campaign maps section above);
  clearing REQUIRES the gate. Selftest 6d-e: keyless BFS on L1 (doors
  closed) reaches 0 cells north of y=33 and neither northern F, while key b
  is reachable south; opening the gate makes >100 north cells reachable.
  6c hash/door-count expectations updated (L1/L2 doors = 3 each).
FIX G (score model): lvlScore&(lvlIdx) = CalcSegScore&(segShots, segDmg,
  segStartT - segT0) computed at the win trigger (SAME weights as CalcScore&:
  10000 - 5*s - 10*shots - 25*dmg, min 0, on the level SEGMENT delta);
  doneScore& += lvlScore&(lvlIdx) (running TOTAL of cleared levels);
  liveScore& = doneScore& + CalcSegScore&(current segment) while playing, so
  liveScore& IS the running total. Result screen shows the cleared level's
  score + TOTAL; victory shows L1..L5 lines + TOTAL (= sum); death screen
  shows the current segment + TOTAL. RESTART LEVEL zeroes ONLY the current
  level's segment (existing seg*-snapshot restore). StartRun / PLAY AGAIN
  reset doneScore& = 0 and lvlScore&(0..19) = 0. Selftest 6d-f: scripted
  3-level temp campaign asserts lvlScore&(n) == CalcSegScore& at each result,
  score == doneScore&, and victory TOTAL == L1+L2+L3.

## SCHLESWIG 6E — danska-makeover + balans (design-sanning: doc/SPRITE-BRIEF.md)
FIX A (nya fiende-sprites): "ögon-kuberna" borta. InitEnemySprites skapar
  enBuf&(typ, 2 gång-frames) ESW x ESH = 48x72, transparent bakgrund;
  DrawEnemySprite ritar zoner A(0-20% mössa/hatt) B(20-45% ansikte)
  C(45-85% rock+vapen) D(85-100% ben/stövlar) per typ: F musket lutad,
  U musket i ansats + bandolär + gul emblem-pixel, O mellan-hatt (INGEN guld —
  brief-regel: guld endast K+G), K bred hatt + guldkant + guldknappar +
  epåletter + kommandostav, G bred hatt + fjäder + RÖD rock + mörser-pose.
  Paletten är EN källa i kod (InitEnemyPalette, spUniformBlue& osv — kan ej
  vara Const då _RGB32() är funktionsanrop); värdena = briefens _RGB32-tabell,
  selftest 6e-s1 speglar alla 14. Ögon ritas vid render i ZONE B (~30% ner)
  via EN funktion EnemyEyeColor&(state): PATROLL mörka, JAKT/ANFALL röda
  (6e-s7). Gång-animation: enAnimF togglar vid positions-flytt (enLastAX/Y),
  max 4 Hz (6e-s6). Render: avståndsskuggning = alpha-överlägg per kolumn
  (min 20% ljushet som väggarna); snabbväg = EN skalad blit när hela spriten
  passerar wallDist, annars per-kolumn z-clip (prestanda: per-kolumn _PutImage
  gjorde 64x64-selftestet för långsamt).
FIX B (G boss-skala): etScale!(G) = 1.4 (höjd), etAspect!(G) = 0.8 mot 0.667
  för övriga (bredd/höjd) -> mätt: höjd x1.4, bredd x1.68 (6e-s3 via
  renEH!/renEW! render-prober).
FIX C (z-order): synbara fiender samlas i visI/visDist/..., sorteras på
  avstånd FJÄRRAN först (bubble sort), ritas närmast sist, per-kolumn z-clip
  mot wallDist — närmaste occluderar (6e-s5: ritordning + 5x5-pixel-probe
  läst inuti render efter buf->display, före _Display; zDrawOrder$/zProbe*).
  VIKTIGT: sprites blitas till världsbuffern buf& (samma _Dest som väggarna),
  INTE display& (annars skrivs de över av buf->display-blitten).
FIX D (attack-verifiering): U:s kulor färdas mot spelarens position VID
  AVFYRNING (redan korrekt — spDX/spDY = riktning mot (px,py) + liten seedad
  spridning; 6e-a: dir == atan2 inom 0.1 rad, vägg mellan -> ingen kula spawnas
  eftersom enSeen=0). Inga träffar genom väggar/stängda dörrar (LOS + projektil-
  Solid% per substeg; 6e-b på tempkarta med stängd dörr). Närstrid: edist<0.8,
  cd 0.7 s, alla typer. G: mörser mot förutsedd position, edist<12, LOS krävs.
  BUGGRÄTTNING: MortarLand sätter nu hitMelee=0 före fiende-loopen (splash är
  aldrig melee — annars kunde stale hitMelee=1 trigga melee-dodge på granat).
FIX E (ammo-caps): maxAmmo 20->40, capAmmo 40/12/48/8 (var 20/6/24/4).
  6d-b justerad (pickup A 11+10=21, ej cap). 5e-d/6c-d körda om: ammo når
  aldrig 0.
FIX F (mini-kanon): wpSplashDmg 25->40. TTK: foot dör av 1 granat i splash,
  K (HP 12) kräver 2 vid pd 1.7 (8/granat); spelaren oskadd på säkert avstånd
  (6e-c).
FIX G (sprint+stamina): Shift = sprint x1.25 (spdMul, appliceras på
  rörelseblocken; mouse-look påverkas ej). stamina 100: drän 20/s vid sprint,
  tom -> sprintLock tills stamina >= 30 (låset gäller direkt, även på framen
  då stamina når 0); återhämtning 10/s vid gång, 20/s stillastående.
  HUD: smal bar under HP-boxen (hudY+23..26), grön/gul/röd, grå vid lås.
  Reset i StartRun och LoadLevel. Selftest 6e-d (hermetisk via sprintInj).
FIX H (ljud oktav ner): SND_ALERT 620->310 / 930->465 Hz (sub-ton 110->55);
  NY SND_ALERT_G = 10: 155->232 Hz, 0.5 s — generalens egen upptäckt (ännu
  lägre general-bas), spelas vid PATROLL->JAKT för ET_GENERAL (6e-e: register
  + live-probe sndLastId/sndLastF0!).

## SCHLESWIG 6F-LITE — quick-fix evening before the public beta
FIX A (ghost box gone): the enemy distance-shade was drawn as an alpha overlay
  over the WHOLE sprite rect (`Line (ex0,ey0)-(ex1,ey1), _RGBA32(0,0,0,ealpha), BF`,
  fast path + per-column path), so the TRANSPARENT margins of enBuf were darkened
  too -> a semi-transparent box around every visible enemy. That overlay is
  debug/collision visualization only: it now sits behind `Const dbgEnemyBox = 0`
  (OFF by default; 1 = draw the full-rect debug box). With the flag OFF no extra
  translucent layer exists in the sprite rect beyond the billboard. Selftest
  6f-a: two-pass pixel-scan (background without the enemy vs with) — every
  transparent-buffer pixel in the sprite rect must be unchanged (0 darkened).
FIX B (eyes inside the face): eye offsets were computed in SCREEN coords from the
  unclamped height (`eoy = ey0 + eh*0.30`, `eox = ecx +- ew*0.18`) — at buffer
  level 0.18*ESW = 8.6 px from center lands OUTSIDE the face span (bx0+8..bx1-8 =
  15..31 of ESW 48), so the right eye rendered on transparent pixels, sometimes
  off the sprite entirely. Now the eyes are defined in SPRITE-BUFFER coords inside
  ZONE B (y 0.26..0.36 of ESH, x ESW\2 +- 4..6) and mapped through the SAME scale
  as the blit by ONE placement source, `Sub EnemyEyeRect` (buffer rect -> screen
  rect, CLIPPED against the sprite rect ex0..ex1/ey0..ey1). Patrol (dark) and
  ALERT (red) eyes share it — only the color (EnemyEyeColor&) differs. Selftest
  6f-b: pixel-scan in ZONE B per type for ALL 5 types incl G (scale 1.4) + one
  ALERT pass: both eyes found, every eye pixel maps back into ZONE B + face span.
FIX C (enemy balls readable): enemy ball (prOwner=1) was 2-3 px light gray. Now
  `Const enBallScale! = 0.6` with clamp `enBallPxMin = 5` / `enBallPxMax = 9`
  (>= 1.5x the old 2-3 px at ANY distance, still smaller than the player's
  7-12 px) with hot orange glow `enBallGlow& = _RGB32(255,110,0)` + white-hot
  core `enBallCore& = _RGB32(255,240,180)` inset 1 px + the shared dark 1 px rim.
  Player ball stays plain white — different COLOR. Selftest 6f-c: rendered glow
  width >= 1.5x the old formula at the same distance + core present + the color
  constants differ from the player ball white. (README has the projectile legend.)
NOT in 6F (6F-full later): ammo-pickup regression, mini-cannon tunneling
  (swept collision) — untouched on purpose.

## Menu render gating (6B FIX F — no menu blink between levels)
The title/pick menu is rendered ONLY when state$ is still "menu" at render
time (inside the menu/fadeout branch). pendingStart (VIDARE / paus-RESTART),
pendingNext (campaign CONTINUE) and PickAction are handled BEFORE the render
in the same frame and switch state to "fadeout" — so result->CONTINUE,
death->RESTART, victory->PLAY AGAIN and pick never render a single menu frame.
Instrumentation: menuRenderN counts real menu renders; selftest 6b-d asserts
menuRenderN is UNCHANGED across all those transitions (and that it DOES increase
at a real title screen — positive control).

## Selftest hermeticity (6B-KOMPLETT)
The selftest must be hermetic: real mouse buttons and real _KeyDown are IGNORED
while selftest=1 (KeyUseHit% checks k$ only; result/victory/menu branches skip
_MouseButton when selftest). A phantom click/key from the live Wayland session
otherwise fires CONTINUE mid-test (observed: fas12a flake). All selftest input
is injected via k$ (c22key$/c23key$/c24key$) or explicit mb=1 lines.
6c-d bot note: the campaign bot picks the best OWNED weapon per range (axe in
melee — free; cannon/blunderbuss/MG before the musket) and keeps a musket
reserve (fires musket only while ammoN(1) > 3), because FOOT HP 3->4 made a
musket-only bot run pool 1 dry. Also: case-25's state machine hunts only when
c25j=1 (otherwise the c25j=2 reset branch is dead code and the bot stalls on
the 2nd result screen), and fas12 zeroes shotsFired/dmgTaken at entry (the
score assertion measures the current round only).

## SCHLESWIG 6G — real-input regression (känntest) + test-library rule
Root cause of "WASD dead in real play" (6G FIX 1, commit 5fbd34d): QB64-PE's
_KeyDown reports letters as UPPERCASE (65..90) only while Shift/CapsLock is
held and lowercase (97..122) otherwise (libqb keyboard.cpp TranslateLetter /
keydown_unicode; key-up removes whichever code the release maps to). 6F FIX A
polled only Asc("W") -> unshifted WASD dead, Shift+W moved and could stick.
Shift itself is VK+QBVK_LSHIFT/RSHIFT = 100304/100303 — NOT 42/54 (those are
numpad codes), so the old sprint check never fired in real play. Fix:
KeyDown2% polls BOTH letter cases (plus the replay keySim% table).
LESSON (rule): keyboard tests must go through the real app path
(menu->start->playing), not direct state manipulation — 6g regression.
The sandbox cannot deliver real OS key events headless, so 6G added
`replay` mode (arg "replay [map]"): the NORMAL binary runs the NORMAL state
machine; a script /tmp/schleswig_replay.scr ("<frame> <token>", token "x" =
one-frame InKey$ tap, "X+"/"X-" = held keySim%, "SH+"/"SH-" = Shift) feeds the
SAME KeyDown2% polling predicate real _KeyDown feeds; telemetry ->
/tmp/schleswig_replay.log. External driver: tools/replay_test.py (asserts
W/A/S/D move, release stops within 1 frame, Shift+W sprints x1.5 + drains
stamina). Selftest phase 33 (6g-a) covers the same pipeline in-app.

## SCHLESWIG 6I — sticky-W under mouse-spam (real play)
Symptom: after releasing W mid click-spam, the player kept walking (W "stuck" in
the engine's eyes; W+S = net zero). Replay repro (tools/combat_replay_test.py)
proved the GAME logic clean (W- honored within 1 frame even mid-spam), so the
root cause is at the libqb/GLFW event level: a key RELEASE delivered while the
window is unfocused is dropped before keyheld_remove()
(GLUT_KEYBOARD_BUTTON_FUNC returns early when !WindowIsFocused), leaving
_KeyDown stuck; _KeyClear does NOT clear keyheld_buffer. Fix (6I): an
event-driven overlay keyEv%(0..255) drained from _KeyHit every frame at loop
top (_KeyHit = positive on down, NEGATIVE on release); KeyDown2% lets an
event-level "up" (keyEv%=-1) override a stuck _KeyDown (replayMode keeps keySim%
authoritative). Debug capture: run with SCHLESWIG_KEYLOG=1 -> /tmp/schleswig_keylog.txt.
6I-FU2 (André's log: kd87=-1 but ev87=1 for 40+ frames): the _KeyHit buffer is
a RingBuffer<8192, OverwriteOnFull=true> — under key-repeat spam it EVICTS the
oldest events, and _KeyClear clears it WITHOUT clearing keyheld, so the overlay
can go stale in BOTH directions. Final rule in KeyDown2% (6I-FU2): RELEASE
ALWAYS WINS — DOWN requires _KeyDown polling down AND keyEv%<>-1; polling up
wins over a stale keyEv%=1; keyEv%=-1 wins over a stuck keyheld. Keylog now
logs only events/anomalies (OVERLAY-STALE / STICKY-OVERRIDE)/state changes +
heartbeat, not per frame. Also fixed a replay-harness bug: token "SH+" fell
into a single-line If-Else and also set keySim%(Asc("S"))=1 (Shift pressed S);
use multi-line If/ElseIf for token parsing. NOTE: this QB64-PE build (V4.7.0-GLFW)
does NOT expose _HasFocus to BASIC ("Invalid variable name") — func__hasfocus
exists in window-gui.cpp but is not registered.
6I-FU3 (dead/stuttery keys under sprint): _KeyHit reports a letter as 65..90
(upper, Shift/CapsLock) OR 97..122 (lower) depending on modifiers at event
time, and press/release can be translated with DIFFERENT modifier states
(asymmetric: down=87, release=-119; Shift itself = VK+QBVK_LSHIFT=100304).
Fix: KeyNorm& folds 97..122 -> 65..90 so every code variant of one physical
key maps to ONE overlay slot (keyEv%); KeyDown2% = release-always-wins on
normalized ids (DOWN requires _KeyDown-polling down AND keyEv%<>-1). Trap
learned: QB64 % is 16-bit — passing 100304 through a % parameter overflows;
use & for key codes (kcn&). Replay test tokens "E<code>" inject raw overlay
events (combat_replay_test.py scenario "e"). Keylog uses monotonic lifeFr&
(frames resets each second for FPS).

## SCHLESWIG 6K — sprite z-order (pickups behind pickups fixed)
Root cause: pickups (amActive/wpActive/pkActive) were blitted in fixed index
order with a per-column check only against wallDist — two sprites on the same
sightline could paint over each other in the wrong order. Fix: ONE per-column
sprite zbuffer sprDist(RW) initialized from wallDist before sprites; EVERY
sprite type (pickups, weapon pickups, medkits, keys, enemies, projectiles,
markers) tests each column against sprDist(x) and marks it via SprMark (which
LOWERS sprDist(x) after the sprite) — back-to-front painter order across the
whole sprite layer, nearest occludes. The viewmodel (gunBuf&) and the HUD are
rendered LAST on top and are untouched by the zbuffer.

## Viewmodel design note (5A-hotfix2)
The viewmodel sits deliberately ~half a gun-width RIGHT of center
(Const vmOffsetX! = 0.06) — Wolfenstein/Quake design. DO NOT "fix" it to
center. Sway/bob/recoil apply to the WHOLE sprite via one gunX/gunY offset.
