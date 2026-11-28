# SCHLESWIG
### A retro raycaster set in an alternative reality of Skåne, 1676.
**v0.1.0-beta — Henpei Game Studios**

Skåne, autumn 1676 — in an alternative reality. The Danish army is at the
walls. You have a musket, an axe, and a fortress to hold.

This beta contains the five-level campaign from The Outskirts to The
Citadel: the core loop — explore, fight, find the bronze, silver and gold
keys, break the siege line.

## Build it yourself (no EXE in this release)
1. Download QB64 Phoenix Edition (free) — https://qb64phoenix.com
2. Either open `Schleswig.bas` in the QB64-PE editor and press F11 (Make EXE),
   or compile from a terminal:

       qb64pe -c Schleswig.bas -o schleswig -x

Done — no dependencies, no DRM, no launcher. The binary lands at the
repository root as `schleswig`; run it from there (`./schleswig`) so the
`maps/` folder and the font resolve.

## Run

    ./schleswig            # START MENU: [1] CAMPAIGN / [2] TEST ARENA
    ./schleswig campaign   # straight into the campaign (maps/levels.lst)
    ./schleswig selftest   # scripted self-test, log: /tmp/schleswig_selftest.log

## What's inside
- Software raycaster written in modern QB64 BASIC (`Schleswig.bas`, single source file)
- Five weapons: axe (melee), musket (magazine + reload cycle), blunderbuss,
  machine musket, mini cannon (lobbed splash) — per-type ammo pools and caps
- Enemy state machine: PATROL / HUNT / ATTACK, line-of-sight fire gate
  (undetected enemies never shoot), and aggro-on-hit — hit a patroller
  from behind and it will hunt you
- Enemies dodge incoming shots (a sidestep away from your ball)
- Unified depth-sorted renderer (walls, sprites, projectiles, pickups)
- Procedural enemy sprites and procedural sound (no binary assets, no audio files)
- 164-assertion self-test suite, all green at release (commit fade532)

### Pickup color legend

Every pickup type has a UNIQUE floor-box color plus a small shape mark, so you
can tell them apart at a distance:

- Ammo `A` (musket): **yellow** box, dot mark
- Ammo `B` (blunderbuss): **orange** box, horizontal bar mark
- Ammo `C` (machine musket): **light blue** box, vertical bar mark
- Ammo `D` (mini cannon): **magenta** box, cross mark
- Medkit `M`: red square box with a white cross
- Keys `b`/`s`/`g`: bronze / silver / gold
- Weapon pickups: their own weapon color with a glint

## Credits (fully transparent)
- Direction, design, quality control: André Motoda
- Engine code: developed with an AI coding agent under human direction
- Sound: procedurally synthesized in code by the same engine (no audio files)
- The complete development log is public. We hide nothing.

## License
- Code: GPL-3.0 (see LICENSE)
- Assets & art: CC BY 4.0 (see LICENSE-ASSETS)

## Known issues (beta)
- Difficulty is unbalanced (the Danes show no mercy) — balancing pass is next
- A few self-test fixtures are timing-sensitive under heavy CPU load
- This release is source-only; binaries may follow

---
*Henpei Game Studios. Yes, "Henpei" means "flat foot" in Japanese.
Ask the captain why.*
