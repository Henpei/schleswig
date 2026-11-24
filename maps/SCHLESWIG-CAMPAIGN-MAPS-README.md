# SCHLESWIG — Vibe's Five Campaign Maps (64x64)

Design: Vibe | Validated: 64x64, closed border, exactly 1 S per map,
keys always reachable BEFORE their door, no isolated pockets (flood-fill proven).

## levels.lst (replace placeholders, names in English)
    level01.map|The Outskirts
    level02.map|The Smugglers' Cellar
    level03.map|The Outer Rampart
    level04.map|The Moat Crossing
    level05.map|The Citadel

## Flow & progression
| Level | Theme | New weapon | Keys/doors | Enemies |
|---|---|---|---|---|
| 01 | Village outskirts, houses, bronze-locked musket shed | musket (m) | b + door 1 | F x3 |
| 02 | Pillar cellar, key vault + locked smuggler store | blunderbuss (f) | s + door 2 | F x3, O x2, U x1 |
| 03 | Rampart rows with staggered firing gaps, MG redoubt | machine gun (k) | - | F x4, O x2, U x2 |
| 04 | Double moat with narrow bridges, cannon yard NE | mini-cannon (c) | - | F x4, O x3, U x2, K x1 |
| 05 | Concentric citadel: bailey -> middle wall -> gold-doored sanctum, GENERAL + twin captains | (2x D ammo) | g + doors 3 | F x5, O x3, U x3, K x2, G x1 |

## Ammo principle (Andre's rule from 6B)
Every level carries ammo for ALL weapons the player can own at that point:
L1: A. L2: A+B. L3: A+B+C. L4: A+B+C+D. L5: D richest + others + medkits.

## Integration notes for the CLI agent
- The maps use ONLY existing, documented chars: # . S F O U K G M A B C D
  y m f k c b s g 1 2 3. No new semantics needed.
- Keep SKIP-logic: spawning normalizes to floor (5E pattern).
- level05 ends with general G: the campaign finale. KILLS on G should be
  satisfying (verify wave/score registers him).
- Suggested new selftests (6c): per-map validation (64x64, 1 S, door/key
  pairing, weapon placement per table, enemies per table), flood-fill
  reachability like generator, HUD-hash equality with these files.

## v1.1 (2026-11-25, André playtest feedback: " Cleared game with the axe alone, never found musket/blunderbuss, weapons behind keys = wrong")
- LEVEL 01: musket (m) + A now ON THE START STREET (visible at spawn); bronze key b moved onto the main N-S street. Bronze shed = bonus cache (A x2 + M) — no longer blocks progression.
- LEVEL 02: blunderbuss (f) + B now ON THE START STREET. Silver vault/store = bonus caches (B x2 + M + s).
- DESIGN RULE going forward: weapons are NEVER locked behind keys; keys only guard optional bonus caches / finale doors.
- Levels 03-05 unchanged (k/c redoubts + citadel gold door as before).
- All five re-validated: 64x64, closed border, 1 S, keys reachable before door, 0 isolated pockets.

## v1.2 (2026-11-25, Andre refined the design: locking is FINE — the problem was that the level auto-clears before you get there)
- NEW RULE: lock ~half the level behind the key wall, and put BOTH the new weapon AND most of the enemies there. Level clear then REQUIRES opening the gate, so the weapon is guaranteed its moment.
- LEVEL 01: full wall across y=33 with a 2-wide bronze gate (1) at x=31-32. NORTH half: musket + A + 2 of 3 footsoldiers. SOUTH: bronze key b on the street + 1 footsoldier + shed cache.
- LEVEL 02: full wall across y=33 with silver gate (2). NORTH: blunderbuss + B + 4 of 6 enemies (incl. the musketeer U). SOUTH: silver key vault + 2 enemies.
- LEVEL 03-05 unchanged.
- Re-validated: keys always reachable BEFORE gates (south side), 0 isolated pockets, 1 S, 64x64, closed border.
