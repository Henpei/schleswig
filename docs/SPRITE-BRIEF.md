# SCHLESWIG — Enemy Sprite Design Brief (6E)

**Purpose:** Get rid of the eye-cubes. Enemies should feel like uniformed
Danish-era soldiers, readable at a distance, with clear rank. Everything
procedurally drawn (zero external assets, zero binary growth).

---

## 1. Design principles

1. **One drawing system, five classes** — the base body is the same for all
   enemy types; the difference is color scheme + attributes. Less code,
   simpler selftests.
2. **Readability first**: at 15+ cells distance the player should directly see
   (a) enemy, (b) which RANK. Shape = class block, color = detail.
3. **Historical caricature**: symbolic 17th-century uniform, not historically
   accurate. 17th century in cartoon style, not no-time.
4. **Procedural frames, not bitmaps**: the sprite is drawn with rect/line
   primitives into an off-screen buffer per figure type per frame (or per
   tick), sent through the existing scale-by-distance render loop and
   z-clipped per column against the existing wall z-buffer (painter's
   algorithm for sprite-vs-sprite).

## 2. Zone layout (base body)

The sprite area is divided into four horizontal zones (percent of sprite
height):

```
   ZONE A  0–20%   Hat/head top
   ZONE B  20–45%  Face + neck
   ZONE C  45–85%  Torso/coat + weapon
   ZONE D  85–100% Legs/boots
```

```
     ▲        ← A: tricorne hat (2 rects + tip)
    (o_o)     ← B: face, eyes = 2 pixels, mouth. G: angry
   /#####|    ← C: coat with cross strap + weapon in hands
   [#### ]|
    /   \     ← D: legs + boots (black/white)
```

**Base body rules (ALL types):**
- Body width ≈ 70 % of sprite height (G: see scale below)
- Eyes: 2 dark pixels in ZONE B — ANGRY mode (red eye pixel) when the enemy
  is ALERT (the visible cue that you've been spotted; sound + sight = clear
  feedback)
- Weapon ALWAYS visible in ZONE C (musket shouldered for U, axe for F,
  command staff for K)
- 2–3 frame walk animation: leg swap left/right + coat sway ±1 pixel in
  ZONE C. Frame toggling on position change, or timer-based 4 Hz.

## 3. Color design per enemy type

| Type | Hat | Coat | Strap/detail | Weapon | Read-cue at range |
|------|-----|------|--------------|--------|-------------------|
| **F** Foot soldier | Dark blue tricorne | Uniform dark blue | White diagonal cross strap | Musket shouldered |
| **U** Musketeer | Dark blue tricorne with yellow emblem pixel | Uniform dark blue, HEAVIER | White strap + black bandolier | Musket AIMED (horizontal) |
| **K** Captain | WIDE hat, black + gold brim | Uniform dark blue + gold buttons (2 yellow pixels) | Gold epaulettes on shoulders | Command staff/sabre |
| **G** General | WIDE hat + FEATHER (white pixel row) | RED coat + gold buttons, epaulettes | Rich gold details | Mortar handling (pose) |
| **O** Officer | Medium hat | Uniform dark blue, lighter than F | White strap + yellow shoulder pixel | Musket + sword |

**Color set, _RGB32 values (QB32 convention):**

```
 uniformBlue    = _RGB32( 22, 44,110)   ' dark uniform blue (coat F/U/O)
 uniformDeep    = _RGB32( 16, 32, 80)   ' darker (U's tone)
 officerBlue    = _RGB32( 32, 56,120)   ' lighter officer
 generalRed     = _RGB32(150, 28, 28)   ' general color = red coat
 hatBlack       = _RGB32( 24, 24, 24)
 hatBrim        = _RGB32( 40, 40, 40)
 crossWhite     = _RGB32(235,235,235)   ' cross strap / white strap
 goldYellow     = _RGB32(255,205, 60)   ' buttons, epaulettes, hat brim
 faceSkin       = _RGB32(205,170,130)
 bootBlack      = _RGB32( 15, 15, 15)
 musketBrown    = _RGB32(105, 68, 38)
 featherWhite   = _RGB32(240,240,240)   ' G's feather
 eyeDark        = _RGB32( 20, 20, 30)
 eyeAlertRed    = _RGB32(255, 60, 60)   ' ALERT eyes
```

**Rules:**
- Uniform blue is NOT used by player-facing pickup icons (the pickup colors in
  6D FIX C), so enemies are never mistaken for pickups — selftest on this.
- G has the ONLY red coat (NO lower rank uses generalRed).
- Only two types (K, G) wear goldYellow — gold signals "dangerous leadership".

## 4. Scales & boss design — General G

- **G is drawn at 1.4× scale** versus all other enemy types (equivalent to
  covering more of the screen area at the same distance). The others keep
  EXACTLY today's scale.
- G's sprite is also WIDER (scale on both X and Y; body proportion:
  width = 0.8 × height for G, versus 0.7 for normal — wide generals).
- G therefore has his OWN set of zones (same A–D zones, all stretched 1.4×:
  hat → feathered hat → red coat + mortar pose → heavy boots).
- Quote goal from André: "you should see who is lobbing mortar fire over the
  citadel".

## 5. Z-order & occlusion (may already be in 6D — check-box)

1. Per frame: sort ALL visible enemy sprites by distance (far → near).
2. Draw walls/objects as today (the DDA z-buffer stays as reference).
3. Draw enemy sprites in sorted order; each sprite column is clipped against
   the wall z-buffer so an enemy behind a wall is cut correctly.
4. Result: the nearest enemy occludes the one behind (painter's algorithm).

## 6. Selftests (proposed ids: 6e-s*)

| ID | Requirement |
|----|-------------|
| 6e-s1 | Color table matches the Const table in code (mirror, not duplicate). |
| 6e-s2 | Uniform blue used ONLY by enemy calls (no pickup collision). |
| 6e-s3 | G scale = 1.4× (measured rendered sprite area vs F's at the same distance). |
| 6e-s4 | Zones A–D drawn for every type (pixel scan in buffer per zone, unique per type). |
| 6e-s5 | Two enemies in line: nearest occludes, the one behind is clipped (z-order). |
| 6e-s6 | Walk animation toggles frames (frame id changes on position change). |
| 6e-s7 | ALERT eyes (red pixel) only in combat state, not in patrol state. |

## 7. Acceptance criteria (feel-test)

1. **At 15 cells:** blob → clearly "enemy, type = F/U/K/G (red boss!)".
   The KTH ball: André points at the screen and guesses the right type 4/4 times.
2. G is visible AS the boss from the first moment he appears in The Citadel.
3. Danes occlude each other properly — no transparent Danish sea.
4. Sprite colors do NOT collide with the 6D pickup readability.
5. Full campaign with the new sprites, RC=0, ALL PASS retained, binary growth < +10 KB.

## 8. Development advice (not a requirement — discuss)

- Don't draw the enemy not as a "cube": a slanted shoulder perspective angle
  (body plus a side part) directly gives a volume feel over 3D-rotated figures
  without full 8-views sprites. Suggest starting with a single-angle view.
- Enemy size-health correlates with sprite scale for K (slightly larger than
  F) and G (already big by design), but NOTE: balance changes happen in the
  attack-verification pass, NOT in the sprite pass.

## 9. Out of scope (keep 6E clean)

- Attack logic / AI behavior: OWN pass (enemy attack verification).
- The detection sound's octave: separate pass.
- Sprint/stamina, ammo caps, cannon buff: separate items.

---

**Brief version:** 1.0 (2026-11-25), by André & Vibe. Goal: 6E after the 6D feel-test.
