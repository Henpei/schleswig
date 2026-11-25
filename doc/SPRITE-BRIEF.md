# SCHLESWIG — Fiende-sprite Design Brief (6E)

**Syfte:** Slipp ögon-kuberna. Fienderna ska kännas som uniformerade dansk-tida
soldater, läsbara på avstånd, med tydlig rang. Allt proced-tecknat (noll externa
assets, noll binär-tillväxt).

---

## 1. Designprinciper

1. **Ett ritningssystem, fem klasser** — baskroppen är samma för alla fiendetyper,
   skillnaden är färgschema + attribut. Mindre kod, enklare selftester.
2. **Läsbarhet först**: på 15+ celler avstånd ska spelaren direkt se (a) fiende,
   b) vilken RANG. Form = klassblock, färg = detalj.
3. **Historisk karikatyr**: symbolisk 1600-tals uniform, inte historiskt korrekt.
   1600-talet i skämttecknings-stil, inte no-time.
4. **Procedurramar, inte bitmaps**: spriten ritas med rekt-/linje-primitiv in i
   en off-screen buffer per figur-typ per frame (eller per tick), skickas genom
   den befintliga skala-eftar-avstånd-render-loopen och z-clippas per kolumn
   mot den existerande vägg-zbufferten (painter's algorithm för sprite-mot-sprite).

## 2. Zonlayout (baskropp)

Sprite-ytan delas i fyra horisontella zoner (procent av sprite-höjden):

```
   ZONE A  0–20%   Mössa/huvudtopp
   ZONE B  20–45%  Ansikte + hals
   ZONE C  45–85%  Torso/rock + vapen
   ZONE D  85–100% Ben/stövlar
```

```
     ▲        ← A: trekantmössa (2 rektanglar + spets)
    (o_o)     ← B: ansikte, ögon = 2 pixlar, mungIPA G: arg
   /#####|    ← C: rock med korsrem + vapen i händerna
   [#### ]|
    /   \     ← D: ben + stövlar (svart/vitt)
```

**Baskropp-regler (ALLA typer):**
- Kroppsbredd ≈ 70 % av sprite-höjd (G: se skala nedan)
- Ögon: 2 mörka pixlar i ZONE B — ARG-läge (röd ögon-pixel) när fienden är i ALERT
  (rep. den synbara ledtråden att man är upptäckt; ljud + syn = tydlig feedback)
- Vapen syns ALLTID i ZONE C (musket i ansats för U, yxa för F, kommandostav K)
- 2–3 rutors gång-animation: ben-skift vänster/höger + rock-svaj ±1 pixel i ZONE C.
  Frame-toggling vidpositionsflytt, eller timer-baserad 4 Hz.

## 3. Färglig design per fiendetyp

| Typ | Mössa/hatt | Rock | Rem/detalj | Vapen | Läs-cue på håll |
|-----|-----------|------|-----------|-------|-----------------|
| **F** Footsoldier | Mörkblå trekant | Uniform mörkblå | Vit diagonal korsrem | Musket lutad |
| **U** Musketeer | Mörkblå trekant m. gul emblem-pixel | Uniform mörkblå, TUNGNARE | Vit rem + svart bandolär | Musket I ANSATS (horisontell) |
| **K** Kapten | BRED hatt, svart + guldkant | Uniform mörkblå + guldknappar (2 gul pixlar) | Guld-epåletter på axlar | Kommandostav/sabel |
| **G** General | BRED hatt + FJÄDER (vit pixel-rad) | RÖD rock + guldknappar, epåletter | Guld-detaljer rikt | Mörser-handledning (pose) |
| **O** Officer | Mellan-hatt | Uniform mörkblå, ljusare än F | Vit rem + gul axel-pixel | Musket + svärd |

**Färguppsättning, _RGB32-värden (QB32-convention):**

```
 uniformBlue    = _RGB32( 22, 44,110)   ' mörk uniform-blå (rock F/U/O)
 uniformDeep    = _RGB32( 16, 32, 80)   ' mörkare (U:s ton)
 officerBlue    = _RGB32( 32, 56,120)   ' ljusare officer
 generalRed     = _RGB32(150, 28, 28)   ' generalfärg = röd rock
 hatBlack       = _RGB32( 24, 24, 24)
 hatBrim        = _RGB32( 40, 40, 40)
 crossWhite     = _RGB32(235,235,235)   ' korsrem/vit rem
 goldYellow     = _RGB32(255,205, 60)   ' knappar, epåletter, hatt-kant
 faceSkin       = _RGB32(205,170,130)
 bootBlack      = _RGB32( 15, 15, 15)
 musketBrown    = _RGB32(105, 68, 38)
 featherWhite   = _RGB32(240,240,240)   ' G:s fjäder
 eyeDark        = _RGB32( 20, 20, 30)
 eyeAlertRed    = _RGB32(255, 60, 60)   ' ALERT-ögon
```

**Regler:**
- Uniform-blå används INTE av spelarplockade ikoner (pickup-färgerna i 6D FIX C),
  så att fiender aldrig misstas för plockbara objekt — selftest på detta.
- G ska ha ensam-röd rock (INGEN lägre rang använder generalRed).
- Endast två typer (K, G) bär goldYellow — guldet signalerar "farlig leadership".

## 4. Skalor & boss-design — General G

- **G ritas i 1,4× skala** mot alla andra fiendetyper (motsvarar att han täcker
  mer av skärm-ytan på samma avstånd). De andra behåller EXAKT dagens skala.
- G:s sprite är också BREDARE (skala både X och Y, proportionen kropp:
  bredd = 0.8 × höjd för G, mot 0.7 för vanliga — breda generaler).
- G har därför EN egen uppsättning zoner (samma A–D-zoner, alla +streckade
  1,4×: mössa → fjäderhatt → röd rock + mörser-pose → kraftiga stövlar).
- Citat-mål från André: "man ska se vem som skickar mörsereld över citadellet".

## 5. Z-order & occlusion (kan redan sitta i 6D — check-a-ruta)

1. Per frame: sortera ALLA synbara fiende-sprites på avstånd (långt → nära).
2. Rita väggar/objekt som idag (DDA-zbuffer finns redan kvar som referens).
3. Rita fiende-sprites i sorteringsordning; varje kolumn av sprite-clippas
   mot vägg-zbufferten så att en fiende bakom en vägg skärs av korrekt.
4. Resultat: närmaste fiende occluderar fienden bakom ( painter's algorithm).

## 6. Selftester (föreslagna id: 6e-s*)

| ID | Krav |
|----|------|
| 6e-s1 | Färg-tabellen matchar Const-tabellen i kod (spegling inte dubblett). |
| 6e-s2 | Uniform-blå används ENDAST av fiende-caller (ingen pickup-kollision). |
| 6e-s3 | G skala = 1,4× (mätt sprite-renderad area mot F:s på samma avstånd). |
| 6e-s4 | Zoner A-D ritas för varje typ (pixel-scan i buffer per zon, typ unik). |
| 6e-s5 | Två fiender på linje: närmaste occluderar, bakre klippt (z-order). |
| 6e-s6 | Gång-animation togglar frames (frame-ID växlar vid position-flytt). |
| 6e-s7 | ALERT-ögon (röd pixel) endast i combat-läge, use not i patrol-läge. |

## 7. Acceptanskriterier (känntest)

1. **På 15 celler:** audda-blob → tydligt "fiende, typ = F/U/K/G (röd boss!) "
   KTH-bollen: André pekar på skärmen och gissar rätt typ 4/4 gånger.
2. G syns SOM boss från första ögonblicket han dyker upp i The Citadel.
3. Danskar occluderar varandra ordentligt — ingen genomskinlig dansk-sjö.
4. Sprite-färger krockar INTE med pickup-läsbarheten från 6D.
5. Full kampanj med nya sprites, RC=0, ALLA PASS behållna, binärtillväxt < +10 KB.

## 8. Utvecklingsråde (inget krav — diskutera)

- Rita fiende överhuvud inte som "kub": en sned axel-perspektiv-vinkel
  (kroppen plus ett sidoparti) ger direkt volym-känsla över 3D-roterade
  figurer utan full 8-vïcuts-sprites. Föreslå start med ett en-angle-vy.
- Fiendernas storlek-hälsa korrelerar med sprite-skala för K (lite större än F)
  och G (count redan řízen-Z by design), men OBS: balansändringar sker i
  attack-verifik-passet, INTE i sprite-passet.

## 9. Out of scope (håll 6E rent)

- Attack-logik/ai-beteende: EGET pass (fiende-attack-verifiering).
- Upptäckts-ljudets oktav: skilt pass.
- Sprint/stamina, ammo-caps, kanon-buff: skilda poster.

---

**Brief-version:** 1.0 (2026-11-25), av André & Vibe. Mål: 6E efter 6D-känntestet.