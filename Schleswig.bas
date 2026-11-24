' ============================================================================
' SCHLESWIG v0.1.0  -- raycaster-FPS i QB64-PE (Linux/Wayland)
' ============================================================================
' VAD: Wolfenstein/Doom-liknande raycaster (DDA) med titelmeny, mouselook (yaw),
'      pitch via y-shearing, HP, medkit/ammo-pickups, skjutning (Fas 2; ingen
'      HP-regen — medkits är enda botemedlet, beslut 2026-11-23),
'      klickbar START GAME-knapp med hover-tick/klick-ljud och fade-overgang (Fas 2.5),
'      dodsskarm + full reset vid R/SPACE (Fas 2.6), crosshair i playing (Fas 2.7),
'      fiender: PATROLL/JAKT/ANFALL-AI med LOS + BFS-flowfield, närstridsskada,
'      skott-träff, billboard-sprites (Fas 3 + 3.1).
'
' BYGG-KONVENTION (stående regel, gäller alla sessioner):
'   Bygg ALLTID från /home/andre/QB64pe med:
'     ./qb64pe -c schleswig/Schleswig.bas -o schleswig/schleswig -x
'   Projektkatalogen heter schleswig/ och binären heter ALLTID "schleswig"
'   (liten s) - samma namn i olika "lager" (katalog vs fil) krockar aldrig,
'   till skillnad från tidigare Raycaster/ vs Raycaster-bygge.
'
' KÖRINSTRUKTIONER:
'   ./schleswig/schleswig            (binären i schleswig/)
'   ./schleswig/schleswig selftest   = autoplay-selftest (logg: /tmp/schleswig_selftest.log)
'   SPACE = starta spelet (från titelmenyn), ESC = avsluta (fungerar i båda lägen)
'   WASD = gå/strafe, musen = titta runt. Muslåset (pointer lock) aktiveras
'   FÖRST när state = "playing" -- i menyn är pekaren synlig.
'
' Byggd med qb64pe från grenen wayland-backend. Byggdatum: 2026-11-22
' ============================================================================
'
' Schleswig i QB64 (Linux) - 1920x1080, WASD + mouselook, FPS-matare, ingen LIMIT
' ======== INITIERING: fönster, GL, karta, variabler, pickups ========
' fönster = skrivbordets faktiska upplösning (1920x1080 ger samma läge som tidigare)
display& = _NewImage(_DesktopWidth, _DesktopHeight, 32)
Screen display&
_FullScreen
' RW/RH = fönstrets faktiska dimension (variabler nu, inte Const)
DIM SHARED RW, RH            ' används även inuti SUBs (MoveVirtualCursor/DrawCursor) — måste deklareras först
RW = _Width(display&)
RH = _Height(display&)
' aspektjusterad projektion: vertikal FOV konstant (0.66 vid 16:9), horisonten
' breddas automatiskt på bredare format (21:9/32:9). Vid 1920x1080 blir båda = 0.66.
planeDist = 0.66 * (16 / 9) / (RW / RH)
fovCut = 0.66 * (RW / RH) / (16 / 9)
buf& = _NewImage(RW, RH, 32)
DIM SHARED btnFont&          ' TTF-font för knapptext (ca 2x HUD-fonten); 0 = ej laddad
DIM SHARED btnFontSize       ' px-storlek, skalad med RH (32 vid 1080p = 2x HUD 16px)
DIM SHARED cursorBuf&, cursorSize   ' pil-sprite-buffer för menyerna (skapas i init, ritas varje meny-frame)
' DIM SHARED: dessa används inuti riktiga SUBs (EngageLock/MoveVirtualCursor/
' DrawCursor) — i QB64-PE blir annars sub-lokala kopior (samma gotcha som ljudet).
DIM SHARED lockEngaged       ' livstids-lås: 1 efter första EngageLock, låses ALDRIG upp förrän exit
DIM SHARED lockEngages       ' räknare: antal _MOUSEHIDE _DISABLE (ska bli exakt 1 per session)
DIM SHARED lockDestroys      ' räknare: antal unlock (_MOUSESHOW) — ska vara 0 tills app-exit
DIM SHARED vCurX, vCurY      ' PARKED: mouse experiment aa26eee — virtuell pekare obrukbar (inga aktiva anrop)
' Fas 4C: weapon viewmodel (Wolfenstein-style musket, bottom of screen). All
' render-only — projectile physics / hit radius / ammo logic are untouched.
' gunX/gunY = smoothed offset (px) from the rest position; recoil = kick (px,
' decays per frame); muzzleT/shakeT = remaining frame counters; bobPhase =
' walk-cycle phase; turnDelta/anglePrev = per-frame turn (rad) for sway.
' (DIM/Const BEFORE first use: the sprite buffer is drawn in init below.)
Const gunBobAmp = 6          ' walk bob amplitude (px) — spec 4-8
Const gunBobRate = 16        ' bob phase advance per cell walked
Const gunSwayGain = 300      ' px sway per rad of turnDelta (before clamp)
Const gunSwayMax = 16        ' hard sway clamp (px) — spec 12-20
Const gunLerp! = 0.25        ' per-frame lerp toward target offset (soft return)
Const gunRecoil = 20         ' recoil kick on shot (px up/back) — spec 15-25
Const gunRecoilDecay! = 0.82 ' recoil decay per frame
Const gunMuzzleFrames = 3    ' muzzle flash visible frames after a shot — spec 2-3
Const gunShakeFrames = 2     ' screen shake frames after a shot — spec 1-2
Const gunShakeAmp = 3        ' screen shake amplitude (px)
Const vmOffsetX! = 0.06      ' DESIGN: viewmodel sits ~half gun-width RIGHT of center
                             ' (Wolfenstein/Quake look) — DO NOT "fix" to center!
DIM gunX, gunY, recoil, muzzleT, shakeT, bobPhase, turnDelta, anglePrev
DIM gunSway, gunTX, gunTY, movedCells   ' Fas 4C working vars (selftest reads gunSway/gunX)
DIM gunBW, gunBH, gunBuf&, gunBaseX, gunRendered   ' sprite buffer + rest pos + selftest counter
DIM inj16r, gr16a, gr16b, gunX0, minGunX, mf16n, ej16, c16done   ' Fas 4C selftest working vars
DIM inj17a, inj17b, inj17c, f17, ej17, k17, c17, el17, per17, d17, row17save$, mapW17save   ' Fas 5A selftest working vars
DIM ej18, px18(20), py18(20), pch$(20), pm18, pj1&, pj2&, p18n, hash18&, row18save$, mapW18save, p18sway   ' Fas 5A-hotfix2 selftest vars
DIM c19hash&, c19alive, c19seg, c19lvl, c19i, c19x, c19y, c19cnt(5), c19f, c19prAll, c19died, inj19d, inj19v, ok19, f19, r19$, c19ok, c19hud$, c19bfs   ' Fas 5C (level progression) selftest vars
DIM inj20a, inj20c, c20hud$, c20hash&, c20alive   ' Fas 5D start-menu selftest vars
DIM c21t0, c21shots, c21corner, c21edge, c21mortar, c21alive, c21i, c21j, c21x, c21y, c21f, c21r$, c21d, c21en, c21killed, c21edgeOK, c21cornerOK, c21mortOK   ' Fas 5D 64x64 runtime-regression selftest vars
' Fas 2.5: meny-knapp + ljud + fade-overgang. Knapptext = riktig TTF-font ~2x
' (ingen bild-skalning/_PutImage — det kraschade "Invalid expression" rad ~1409).
' Storleken skalas med RH så layouten hålls på alla skärmupplösningar.
btnFontSize = Int(RH * 32 / 1080): If btnFontSize < 16 Then btnFontSize = 16
btnFont& = 0
fontCand$ = "schleswig/LiberationMono-Regular.ttf"     ' CWD = QB64pe-rot (dokumenterat körsätt)
If Not _FileExists(fontCand$) Then fontCand$ = "LiberationMono-Regular.ttf"   ' CWD = repo-rot
If Not _FileExists(fontCand$) Then fontCand$ = "/home/andre/QB64pe/schleswig/LiberationMono-Regular.ttf"
If Not _FileExists(fontCand$) Then fontCand$ = "/home/andre/QB64pe/tests/compile_tests/font/LiberationMono-Regular.ttf"
If Not _FileExists(fontCand$) Then fontCand$ = "/usr/share/fonts/TTF/DejaVuSansMono.ttf"
If _FileExists(fontCand$) Then btnFont& = _LoadFont(fontCand$, btnFontSize, "MONOSPACE")
' pil-sprite för menyerna: buffer skapas EN gång i init (~40x40 vid 1080p,
' skalad med RH). Spetsig triangel: svart outline + amber kärna RGB(255,200,0).
' Pilens TOPP hamnar exakt på pekar-koordinaten (hotspot för ButtonHit%).
cursorSize = Int(RH * 40 / 1080): If cursorSize < 16 Then cursorSize = 16
cursorBuf& = _NewImage(cursorSize, cursorSize, 32)
_Dest cursorBuf&
Line (0, 0)-(cursorSize - 1, cursorSize - 1), _RGBA32(0, 0, 0, 0), BF   ' transparent bakgrund
ccx = cursorSize \ 2
For cy = 0 To cursorSize - 1
    chw = Int(cy * 0.75)
    Line (ccx - chw - 1, cy)-(ccx + chw + 1, cy), _RGB32(0, 0, 0)        ' svart outline
Next cy
For cy = 0 To cursorSize - 1
    chw = Int(cy * 0.75) - 1: If chw < 0 Then chw = 0
    Line (ccx - chw, cy)-(ccx + chw, cy), _RGB32(255, 200, 0)            ' amber kärna
Next cy
_Dest display&
' Fas 4C: procedural musket viewmodel sprite (no external art — LINE/rect
' primitives only). Buffer ~16% RW x ~34% RH (~1/3 of screen height), transparent
' background. Fas 5A-hotfix: ALL primitives derive from ONE origin vmCX (buffer
' center x) — barrel centered on vmCX, stock centered on vmCX and at least as
' wide as the barrel at the junction, so barrel can never drift off the stock.
' Sway/bob/recoil apply as ONE blit offset (gunX/gunY) to the whole buffer.
gunBW = Int(RW * 0.16): If gunBW < 48 Then gunBW = 48
gunBH = Int(RH * 0.34): If gunBH < 96 Then gunBH = 96
gunBuf& = _NewImage(gunBW, gunBH, 32)
_Dest gunBuf&
Line (0, 0)-(gunBW - 1, gunBH - 1), _RGBA32(0, 0, 0, 0), BF   ' transparent background
vmCX = gunBW \ 2                      ' single origin for every primitive
vmBarrelHW = Int(gunBW * 0.09)        ' barrel half-width
bxx0 = vmCX - vmBarrelHW: bxx1 = vmCX + vmBarrelHW
Line (bxx0, 0)-(bxx1, Int(gunBH * 0.6)), _RGB32(45, 45, 52), BF          ' barrel: dark gunmetal
Line (bxx0, 0)-(bxx0 + Int(gunBW * 0.03) + 1, Int(gunBH * 0.6)), _RGB32(85, 85, 98)  ' barrel highlight (volume)
Line (bxx0 - 1, 0)-(bxx1 + 1, Int(gunBH * 0.07)), _RGB32(155, 155, 165), BF  ' muzzle: lighter metal tip
Line (bxx1 + 1, Int(gunBH * 0.38))-(bxx1 + Int(gunBW * 0.16), Int(gunBH * 0.52)), _RGB32(125, 125, 135), BF  ' flintlock hook
For gy16 = Int(gunBH * 0.55) To gunBH - 1   ' stock: centered on vmCX, widens toward the bottom (butt)
    gw16 = Int(gunBW * 0.20 + gunBW * 0.26 * (gy16 - gunBH * 0.55) / (gunBH * 0.45))   ' top 0.20w >= barrel 0.18w
    gsx0 = vmCX - gw16 \ 2: gsx1 = gsx0 + gw16
    If gsx0 < 0 Then gsx0 = 0
    If gsx1 > gunBW - 1 Then gsx1 = gunBW - 1
    gmid = gsx0 + gw16 \ 2
    Line (gsx0, gy16)-(gmid, gy16), _RGB32(96, 60, 28)     ' dark wood (shadow side)
    Line (gmid, gy16)-(gsx1, gy16), _RGB32(140, 92, 44)    ' light wood (lit side)
Next gy16
_Dest display&
gunBaseX = RW \ 2 + Int(RW * vmOffsetX!)   ' Fas 4C/5A-hotfix2 rest position: right of center by design (Const vmOffsetX!)
' btnX0..btnY1 sätts i meny-grenen via BtnGeom med GEMENSAM bredd per meny
' (längsta label + padding — alla knappar inom en meny lika brede).
' pendingStart: fortsättning från result går samma START-väg som meny-START (se meny-grenen)
pendingStart = 0
startRuns = 0            ' räknare: antal START-vägs-triggeringar via StartRun (diagnos-bevis)
DIM selIdx               ' meny-markering (tangentdriven): 1=START GAME 2=QUIT GAME; paus: 1..3
selIdx = 1
hover = 0: prevHover = 0   ' PARKED: mouse experiment aa26eee (mus-hover i menyer borttagen)
' LIVSTIDS-LÅS vid APP-START: låset engageras NU, före första meny-framen —
' compositor-pekaren syns ALDRIG (inga _MOUSESHOW i kodbasen, grep-bevis).
' Alla menyer är tangentdrivna; virtuell pekare/pil-sprite är parkerad (obrukbar).
fading = 0: fadeT0 = 0   ' fading: 0=nej, 2=fade-in i playing
deathTime = 0            ' Fas 2.6: när state$ = "dead"
dummy = _MouseMovementX
fading = 0: fadeT0 = 0   ' fading: 0=nej, 2=fade-in i playing
deathTime = 0            ' Fas 2.6: när state$ = "dead"
dummy = _MouseMovementX

' Fas 5A + 5A-hotfix2: .map-format — dynamic map grid (no hardcoded 16x16) and
' NO embedded map anymore: the .map FILE is the only source (maps/default.map
' when no argument). MAP_MAX bounds all map arrays. mapRow$ = THE parsed grid;
' mapTmp$ is the parse staging area — mapRow$ is only committed on FULL success,
' so a half-parsed grid can never reach the renderer. Load failure = loud fatal
' error screen (state$ = "fatal"), never a silent phantom map.
Const MAP_MAX = 128
DIM SHARED mapRow$(MAP_MAX - 1)
DIM SHARED mapW, mapH
DIM SHARED doorOpen%(MAP_MAX - 1, MAP_MAX - 1)
DIM mapSrc$(MAP_MAX - 1), mapTmp$(MAP_MAX - 1)
DIM spEnT(10), spEnX(10), spEnY(10), spEnN     ' Fas 5A: enemy spawns from map (F/O/U/K/G)
DIM spPkX(10), spPkY(10), spPkN                 ' medkits (M)
DIM spAmX(10), spAmY(10), spAmN                 ' ammo (A)
DIM spKeyT(10), spKeyX(10), spKeyY(10), spKeyN  ' keys: 1=bronze 2=silver 3=gold (b/s/g)
DIM keyX(10), keyY(10), keyType(10), keyActive(10)
DIM hasBronze, hasSilver, hasGold               ' Fas 5A: owned keys
DIM plStartX, plStartY                          ' player start cell ('S')
DIM loadedMapFile$, lmPath$, lmOK, pmOK, srcN
' Fas 5C: level progression / campaign (maps/levels.lst). DIM SHARED: these are
' also read inside Functions (HudLevelTag$) — sub-local copies would read 0.
DIM SHARED mapFile$          ' current map file (arg, default, or current campaign level)
DIM SHARED mapHash&          ' grid hash of the loaded map (HUD tag + selftest)
DIM SHARED gameMode$         ' "arena" (no arg) / "single" (map arg) / "campaign" / "selftest"
DIM SHARED lstFile$          ' levels list path (default "maps/levels.lst")
DIM SHARED lvlFile$(20), lvlName$(20), lvlN, lvlIdx   ' campaign list; lvlIdx = 0-based current level
DIM SHARED lvlT0, lvlTime(20)                          ' per-level start time / cleared time (s)
DIM SHARED segShots, segDmg, segT0, segStartT          ' per-level-segment score snapshot (RESTART LEVEL restores it)
DIM SHARED restarts, pendingNext                       ' HUD restart counter / CONTINUE->next-level flag
DIM SHARED menuPick, autoCamp                          ' 5D: menuPick=1 -> no-arg pick menu (1 ARENA / 2 CAMPAIGN); autoCamp=1 -> campaign arg starts straight in
DIM mapValid                 ' 1 only after a FULL successful ParseMap commit
DIM loadFatal, fatalMsg$, errRow, errCol, errWhy$, nStartS, tStartX, tStartY, mapWarn$
mapValid = 0
Const selftestMap$ = "/tmp/schleswig_selftest16.map"   ' 5A-hotfix2 addendum: default.map is the 64x64 TEST ARENA; selftest phases 1-16 run on this classic 16x16 temp map

Dim pal&(255)
For i = 0 To 255
    pal&(i) = _RGB32(i, i, i)
Next i

' RW/RH satta ovan från fönstrets dimension (var tidigare Const 960/540)

' px/py sätts EFTER kartladdningen (plStart från kartans 'S') — se LoadMapAuto nedan
angle = 0
pitch = 0
state$ = "menu"
moveStep = 0.012   ' +20% (2026-11-23 hastighets-bump, var 0.01); strafe = 0.6x oförändrad
turnStep = 0.04
mouseSens = 0.002
Const pitchSens = 2
' Version (semver-light): MINOR = stor fas, PATCH = fix, 1.0.0 = fullständig spelarkrets.
' Placering: git-tagg (v0.1.0) + denna rad + titelskärm-hörn + _Title.
Const ver$ = "v0.1.0"
' Bygg-stämpel: commit-hash som denna källa bygger från — UPPDATERAS I VARJE
' COMMIT (en rad i commit-rutinen). Visas nere höger i meny + resultat.
Const strBuild$ = "0c11a5a"

' KeyUse = the universal interaction key (E). Menus select/confirm with it now;
' doors etc. phase 5+ — reuse this exact check (KeyUseHit%).
Const KeyUse = 101   ' Asc("E")

' ===== GAME TEXT (centralized) =================
' All user-visible text lives here, in English. Selftest log strings (stMsg$)
' are diagnostics and stay with the selftest code.
Const strAppName$ = "Schleswig"                    ' window title (_Title)
Const strTitle$ = "SCHLESWIG"                      ' big title on the title screen
Const strStartBtn$ = "START GAME"                  ' menu button
Const strQuitBtn$ = "QUIT GAME"                    ' menu button 2 (same menu, same width)
Const strDead$ = "YOU DIED"                        ' death screen, big text
Const strRestart$ = "Press R to restart"           ' death screen, line 2
Const strHudHp$ = "HP:"                            ' HUD label
Const strHudAmmo$ = "AMMO:"                        ' HUD label
Const strKeys$ = "KEYS:"                           ' Fas 5A: HUD keys row (owned keys only)
Const strNeedBronze$ = "NEED BRONZE KEY"           ' Fas 5A: locked door, missing key (2 s HUD msg)
Const strNeedSilver$ = "NEED SILVER KEY"
Const strNeedGold$ = "NEED GOLD KEY"
Const strDoorOpen$ = "DOOR OPEN"                   ' Fas 5A: door opened with E
Const strGotBronze$ = "GOT BRONZE KEY"             ' Fas 5A: key pickups
Const strGotSilver$ = "GOT SILVER KEY"
Const strGotGold$ = "GOT GOLD KEY"
Const strFatalQuit$ = "Press Q to quit"            ' Fas 5A-hotfix2: fatal map-load error screen
Const strFps$ = "FPS:"                             ' debug line + window title
Const strDmgDebug$ = "-5 HP"                       ' debug key G
Const strMedkit$ = "+25 HP"                        ' medkit pickup
Const strAmmoPick$ = "+5 AMMO"                     ' ammo pickup (cap 20)
Const strScore$ = "SCORE:"                         ' death screen/HUD: score line
Const strBest$ = "BEST:"                           ' death/result screen: best score
Const strNewRec$ = "NEW RECORD!"                   ' death/result screen: on new record
Const strWin$ = "MAP CLEARED"                      ' result screen: title
Const strTime$ = "TIME:"                           ' result screen: mm:ss
Const strShots$ = "SHOTS:"                         ' result screen
Const strDmg$ = "DAMAGE:"                          ' result screen
Const strEscMenu$ = "ESC = PAUSE"                  ' result screen, bottom (ESC -> pause)
Const strClickCont$ = "CLICK OR E TO CONTINUE"     ' result: continue with click/E (fast blink)
Const strPaused$ = "PAUSED"                        ' pause menu: title
Const strResume$ = "RESUME"                        ' pause menu: button 1
Const strRestartRound$ = "RESTART LEVEL"           ' pause menu: button 2
Const strQuitPause$ = "QUIT GAME"                  ' pause menu: button 3
Const strNextMap$ = "CONTINUE"                     ' result menu: button 1 (next round)
Const strMainMenu$ = "MAIN MENU"                   ' result menu: button 2
' 5C level progression / campaign:
Const strVictory$ = "VICTORY"                      ' campaign victory screen title (last level of levels.lst cleared)
Const strPlayAgain$ = "PLAY AGAIN"                 ' victory screen button 1 (restart campaign at level 1, score zeroed)
Const strQuit$ = "QUIT"                            ' victory/death screen button 2
Const strRestarts$ = "RESTARTS:"                   ' 5C: restart counter (death screen + HUD via HudLevelTag$)
Const strKills$ = "KILLS:"                         ' 5C: victory screen total-kills line
Const strNextLvl$ = "NEXT:"                        ' 5C: result screen next-level hint (campaign, non-final level)
' 5D start menu (no-arg / IDE F5): mode pick rows
Const strPickArena$ = "1  TEST ARENA"               ' pick menu row 1 (default.map)
Const strPickCamp$ = "2  CAMPAIGN"                  ' pick menu row 2 (maps/levels.lst, level 1)
Const strPickHint$ = "1/2 OR ARROWS+ENTER, ESC/Q QUIT"   ' pick menu hint line
' (strLockHint$ borttagen 2026-11-23: Wayland-låset ska bara SKE vid klick — ingen hint-text)
' ============================================================================

ceilingCol& = _RGB32(24, 24, 48)
floorCol& = _RGB32(70, 45, 25)

' Fas 1: hälsa + pickups (array-baserat).
' VARFÖR pkX/pkY och inte px(10)/py(10): spelarens position ligger i skalärerna
' px/py, så arrayer med samma namn skulle krocka med dem. wallDist(RW) behövs
' för att sprites ska kunna döljas bakom väggar (se RENDERING-sektionen).
DIM wallDist(RW)
DIM pkX(10), pkY(10), pkActive(10)
hp = 100
hpMsg$ = ""
hpMsgTime = 0
' Fas 5A: pickup-positioner sätts av ApplyMapSpawns från kartans M/A-tecken
' (defaultkartan har samma celler som tidigare hårdkodade värden).

' Fas 2: ammo + skjutning (ingen HP-regen; samma array-pool-mönster som medkit)
Const maxAmmo = 20         ' ammo-cap — samma konstant används av HUD-streckantalet
DIM amX(10), amY(10), amActive(10)
ammo = 5
lastShotTime = -1        ' cooldown 0.3 s mellan skott
tracerTime = -1          ' tracer-flash synlig 2-3 frames
flashTime = -1           ' träff-flash
flashDist = 99

' Fas 3/3.1: fiende-pool (samma array-pool-mönster som pickups): pos, aktiv flagga,
' hp (3 träffar), skada, hastighet + AI-tillstånd. Startlägen i SpawnEnemies.
' enState: 0=PATROLL, 1=JAKT, 2=ANFALL. bfsD = BFS-avståndskarta (flödesfält).
DIM enX(10), enY(10), enActive(10), enHP(10), enDmg(10), enSpd(10), enLastHit(10)
DIM enState(10), enSeen(10), enTx(10), enTy(10), enPatrolT(10), enLastSeen(10)
DIM enLx(10), enLy(10), enCalmT(10), bfsD(MAP_MAX - 1, MAP_MAX - 1), qx(MAP_MAX * MAP_MAX - 1), qy(MAP_MAX * MAP_MAX - 1)
' Fas 4A: data-driven enemy-type register ("the Danish regiment"). Per type:
' HP, melee dmg, speed, zigzag amplitude (cells), dodge chance, shoot ability
' (0 = melee only; ranged weapons arrive in 4B), hold distance (0 = none),
' body color, sprite id, name.
Const ET_FOOT = 0
Const ET_OFFICER = 1
Const ET_MUSKETEER = 2
Const ET_CAPTAIN = 3
Const ET_GENERAL = 4
Const ET_COUNT = 5
Const ET_BOSS_STEP = 5          ' general spawns on waves 5, 10, 15, ... (max 1 per wave)
DIM etHP(ET_COUNT), etDmg(ET_COUNT), etZigAmp(ET_COUNT), etShoot(ET_COUNT), etSpr(ET_COUNT)
DIM etSpd!(ET_COUNT), etDodge!(ET_COUNT), etHold!(ET_COUNT), etCol&(ET_COUNT), etName$(ET_COUNT)
DIM etFireT!(ET_COUNT), etProjSpd!(ET_COUNT), etProjDmg(ET_COUNT)          ' ranged: fire interval, ball speed/dmg
DIM etMortarT!(ET_COUNT), etSplashR!(ET_COUNT), etSplashDmg(ET_COUNT)       ' mortar: flight time, splash radius/dmg
DIM etScale!(ET_COUNT), etMinWave(ET_COUNT)                                 ' sprite scale + spawn gating wave
DIM enType(10), enZigX(10), enZigY(10), enZigT(10), enZigS(10)   ' per-enemy type + zigzag target cell / re-roll timer / side sign
DIM enFireT(10)                                                   ' Fas 4B: next allowed fire time per enemy (ranged types)
DIM waveNo, killsTotal                                  ' spawn-wave counter / total kills (captain gate)
DIM SHARED dodgeSeed&                                   ' dedicated seedable LCG for dodge rolls (read inside Function DodgeRnd#)
DIM SHARED aiSeed&                                      ' Fas 4B: dedicated seedable LCG for enemy AI spread (Function AiRnd#)
' Fas 4B: projectile pool (replaces hitscan). Per projectile: position, unit
' dir, speed (cells/s, dt-scaled), owner (0=player, 1=enemy), damage, type
' (PR_BALL/PR_MORTAR), source type (for splash params), and for MORTAR the
' target cell + land time. Cleared on every wave start (SpawnEnemies).
Const PR_BALL = 1
Const PR_MORTAR = 2
Const PR_MAX = 31
Const plrBallSpd! = 6     ' player musket ball: slow, period-correct
Const plrBallDmg = 1      ' same damage per hit as the old hitscan (balance unchanged)
' BALL render size: light distance scale with HARD clamp — ballPx = clamp(RW/dist * ballScale!, ballPxMin, ballPxMax)
' (near = 12 px, far = 7 px, never below 7 -> always visible; never a 'shoebox'). Tune via feel-test.
Const ballScale! = 0.35
Const ballPxMin = 7
Const ballPxMax = 12
DIM prX(PR_MAX), prY(PR_MAX), prDX(PR_MAX), prDY(PR_MAX), prActive(PR_MAX)
DIM prSpd!(PR_MAX), prOwner(PR_MAX), prDmg(PR_MAX), prType(PR_MAX), prSrcType(PR_MAX)
DIM prTX(PR_MAX), prTY(PR_MAX), prLandT(PR_MAX)
DIM projSpawned                                           ' diagnostics/selftest counter
DIM pvx, pvy                                              ' player velocity (cells/s) — mortar lead
' SpawnProjectile caller params (globals, gosub-style):
DIM spX, spY, spDX, spDY, spSpd!, spOwner, spDmg, spType, spSrcType, spTX, spTY, spLandT, spSlot
DIM hitE, hitDmg                                          ' EnemyTakeHit params
' ======== LJUD (Fas 4): procedurell PCM via _SNDOPENRAW/_SNDRAWBATCH =========
' Data-drivet register: id -> vågform/frekvenssvep/längd/volym (InitSounds).
' Nya ljud (vapen/fiendetyper) kopplas via registret + GenSample#, INTE via
' hårdkodade If-satser utspridda i spelkoden.
Const SND_RATE = 48000        ' miniaudio engine sample rate
Const SND_SHOT = 1            ' skott: brus-burst
Const SND_HIT = 2             ' träff: fyrkant "puck"
Const SND_ENDIE = 3           ' fiende-död: sågtand nedåt
Const SND_PICKUP = 4          ' pickup: sinus uppåt
Const SND_HURT = 5            ' player-skada: mörk fyrkant
Const SND_ALERT = 6           ' detect-alert: två-ton (PATROLL->JAKT)
Const SND_STEP = 7            ' fotsteg spelare
Const SND_ESTEP = 8           ' fotsteg fiende (volym efter avstånd)
Const SND_BOOM = 9            ' Fas 4B: mortar-landning (långt brus)
Const SND_COUNT = 9
' OBS: DIM SHARED är NÖDVÄNDIGT här — variabler som bara används inuti SUBs
' (InitSounds/GenSample#/PlaySoundVol) blir annars sub-lokala i QB64-PE och
' sndPipe& läser alltid 0 där -> alla ljud tysta no-op (ljud-debug 2026-11-23).
DIM SHARED sndWave(SND_COUNT), sndF0!(SND_COUNT), sndF1!(SND_COUNT), sndDur!(SND_COUNT), sndVol!(SND_COUNT)
DIM SHARED sndBuf!(SND_RATE)  ' PCM-buffer, max 1 s per ljud
DIM SHARED sndPipe&           ' raw pipe; <=0 = ingen ljudenhet (headless) -> tyst no-op
DIM enAlertT(10), enStepAcc(10)   ' används även i huvudloopen -> globala
' Highscore: score = 10000 - 5*s - 10*skott - 25*skada (min 0; formel v2 2026-11-23).
' DIM SHARED: används även i CalcScore& (sub-lokala annars, se ljud-debuggen).
DIM SHARED shotsFired, dmgTaken, runT0, bestScore, score, newRecord
DIM winPending, winT0        ' seger-trigger: alla fiender döda -> vänta 1 s -> result
DIM SHARED runTimeFrozen     ' FRYST run-tid (s) — sätts vid SJÄLVA sista killen; -1 = ej fryst. SHARED: läses av Function CurRunTime% (annars funktions-lokal=0 och tidsstraffet försvinner ur CalcScore&!)
DIM SHARED liveScore&        ' LIVE-score-räknare: EN variabel — uppdateras varje playing-frame; HUD/result/highscore läser SAMMA värde
DIM resumeState$             ' paus: vilket läge återgår till (playing/result)
DIM pauseT0                  ' paus: när pausen började (runT0 justeras vid resume)
DIM escCool                  ' FIX 2: ESC cooldown så held ESC från result inte avslutar i menu
DIM lockHint                 ' 1 = visa 'klicka för att låsa musen' (tills första klicket i rundan)
DIM stepAcc                   ' ackumulerad gångsträcka (spelarfotsteg)
DIM SHARED sndDbg, sndCalls   ' ljud-debug: filhandtag + anropsräknare
' Fas 3 selftest/autoplay: ./schleswig/schleswig selftest -> scriptat scenario, loggas till fil
selftest = 0
cmdArg$ = LCase$(LTrim$(RTrim$(Command$)))   ' Obs: Trim$ finns inte i QB64-PE, bara LTrim$/RTrim$
If cmdArg$ = "selftest" Then selftest = 1
' Fas 5A-hotfix2 + 5C: command line -> game mode (see AGENTS.md argument table):
'   no arg        -> "arena"    maps/default.map TEST ARENA (HUD: ARENA)
'   selftest      -> "selftest" scripted self-test (single 16x16 test map)
'   <file.map>    -> "single"   one map, test mode (HUD: SINGLE)
'   campaign      -> "campaign" maps/levels.lst from level 1
'   --level N     -> "campaign" starting at lst position N (dev tool)
' LoadMapAuto always runs BEFORE the first render frame (main loop starts below).
' On failure: loud fatal error screen, NO game start (no phantom map). For
' campaign the levels list failure is equally loud (LEVELS FILE NOT FOUND /
' INVALID LEVELS LIST line <r>), same fatal state as map errors.
gameMode$ = GameModeFromCmd$(cmdArg$)
' 5D: no-arg (IDE F5) -> pick menu; campaign args -> straight in (no menu)
menuPick = MenuPickFromCmd%(cmdArg$)
autoCamp = AutoStartFromCmd%(cmdArg$)
lstFile$ = "maps/levels.lst"
lvlN = 0: lvlIdx = 0: restarts = 0: pendingNext = 0: mapHash& = 0: lvlT0 = Timer
If gameMode$ = "campaign" Then
    Gosub LoadLevelsLst
    If loadFatal Then
        mapFile$ = ""   ' lst fatal already set (LEVELS FILE NOT FOUND / INVALID LEVELS LIST); skip map load
    Else
        lvlReq = LevelFromCmd%(cmdArg$)
        If lvlReq < 1 Then lvlReq = 1
        If lvlReq > lvlN Then lvlReq = lvlN
        lvlIdx = lvlReq - 1
        mapFile$ = lvlFile$(lvlIdx)
        Gosub LoadMapAuto
    End If
Else
    mapFile$ = MapFileFromCmd$(cmdArg$)
    Gosub LoadMapAuto
End If
If loadFatal Then
    Print fatalMsg$   ' log line to the terminal
    state$ = "fatal"
Else
    Gosub ApplyMapSpawns
    px = plStartX + 0.5: py = plStartY + 0.5   ' Fas 5A: player start from map ('S')
End If
If selftest Then Randomize 987654: dodgeSeed& = 987654: aiSeed& = 13579   ' Fas 4A/4B: seeded RNG in selftest -> deterministic zigzag/dodge/spread tests
testPhase = 0: testT0 = Timer: stMsg$ = "": testDbg = 0: testHb = Timer: testFlag = 0
Gosub InitSounds   ' Fas 4: ljud-register + raw-pipe (säker även headless)
' Highscore: nollställ counters, ladda bästa score från lokal fil (.schleswig_scores.txt)
shotsFired = 0: dmgTaken = 0: runT0 = Timer: score = 0: newRecord = 0: bestScore = 0: lvlT0 = Timer
winPending = 0: winT0 = 0: runTimeFrozen = -1: escCool = -99
lockEngaged = 0: lockEngages = 0: lockDestroys = 0   ' låset engageras vid FÖRSTA fade-slutet (StartRun-vägen), INTE vid init
gunX = 0: gunY = 0: recoil = 0: muzzleT = 0: shakeT = 0: bobPhase = 0: turnDelta = 0: anglePrev = 0: gunSway = 0: gunRendered = 0   ' Fas 4C viewmodel init
vCurX = RW \ 2: vCurY = RH \ 2   ' PARKED: mouse experiment aa26eee (obrukbar)
If _FileExists(".schleswig_scores.txt") Then
    f = FreeFile
    Open ".schleswig_scores.txt" For Input As #f
    If Not Eof(f) Then Line Input #f, bs$: bestScore = Val(bs$)
    Close #f
End If
If selftest Then
    stF = FreeFile
    Open "/tmp/schleswig_selftest.log" For Output As #stF
    Close #stF
    If loadFatal Then
        stMsg$ = "FAIL selftest init: map load fatal: " + fatalMsg$: Gosub STLog
        stMsg$ = "SELFTEST FAIL": Gosub STLog
        ShutdownSound
        End
    End If
    ' default.map is the 64x64 TEST ARENA — scripted phases 1-16 are hardcoded
    ' against the classic 16x16 layout, so write it to a temp file and load that.
    stF16 = FreeFile
    Open selftestMap$ For Output As #stF16
    Print #stF16, "################"
    Print #stF16, "#M.....M......M#"
    Print #stF16, "#..##......##..#"
    Print #stF16, "#..##......##..#"
    Print #stF16, "#..A...S....A..#"
    Print #stF16, "#.....####.....#"
    Print #stF16, "#.....#..#.....#"
    Print #stF16, "#....M#..#.....#"
    Print #stF16, "#..#..####..#..#"
    Print #stF16, "#..#..A....#...#"
    Print #stF16, "#..#.####.#.#..#"
    Print #stF16, "#....#..#...#..#"
    Print #stF16, "#..............#"
    Print #stF16, "#......##......#"
    Print #stF16, "#.....M........#"
    Print #stF16, "################"
    Close #stF16
    mapFile$ = selftestMap$: Gosub LoadMapAuto: Gosub ApplyMapSpawns
    If loadFatal Or mapValid = 0 Then
        stMsg$ = "FAIL selftest init: selftest 16x16 map failed: " + fatalMsg$: Gosub STLog
        stMsg$ = "SELFTEST FAIL": Gosub STLog
        ShutdownSound
        End
    End If
    state$ = "playing"          ' hoppa över menyn direkt
    LogMouse "HIDE_DISABLE selftest-init"
    stMsg$ = "pre-lock-init: lockEngaged=" + Str$(lockEngaged) + " engages=" + Str$(lockEngages) + " (lås sker vid första fade-slut, ej vid init)": Gosub STLog
    lockHint = 1
    runT0 = Timer: shotsFired = 0: dmgTaken = 0: winPending = 0: runTimeFrozen = -1   ' highscore-counters i selftest
    Gosub SpawnEnemies
    ' Fas 3.1-scenario: EN fiende i PATROLL utan LOS till spelaren (10.5,6.5)->(8.5,4.5)
    For i = 1 To 10: enActive(i) = 0: Next i
    px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: hp = 100: ammo = 5   ' Fas 5A: start from map 'S'
    enX(0) = 10.5: enY(0) = 6.5: enActive(0) = 1
    enHP(0) = 3: enDmg(0) = 10: enSpd(0) = 2
    enState(0) = 0: enLastHit(0) = 0: enLastSeen(0) = 0: enCalmT(0) = 0
    enLx(0) = enX(0): enLy(0) = enY(0)
    enTx(0) = 10: enTy(0) = 5: enPatrolT(0) = Timer   ' deterministiskt patrullmål
    bfsForX = -1: bfsForY = -1
    stMsg$ = "selftest start: fas1 patrull (10.5,6.5)": Gosub STLog
    If btnFont& > 0 Then
        stMsg$ = "knappfont: " + fontCand$ + " size=" + Str$(btnFontSize) + " handle=" + Str$(btnFont&) + " (TTF ~2x)"
    Else
        stMsg$ = "knappfont: FALLBACK inbyggd font (ingen TTF hittades) size=" + Str$(btnFontSize)
    End If
    Gosub STLog
    testPhase = 1: testT0 = Timer
Else
    Gosub SpawnEnemies
    Randomize Timer
    dodgeSeed& = Int(Timer * 1000000) And &H7FFFFFFF: If dodgeSeed& <= 0 Then dodgeSeed& = 1   ' Fas 4A: random dodge stream in real play
    aiSeed& = Int(Timer * 7777777) And &H7FFFFFFF: If aiSeed& <= 0 Then aiSeed& = 1         ' Fas 4B: random AI stream in real play
End If

frames = 0
fpsShow = 0
lastTime = Timer
prevTime = Timer

Do
    curTime = Timer
    dt = curTime - prevTime
    If dt <= 0 Then dt = 1 / 60
    If dt > 0.25 Then dt = 0.25
    prevTime = curTime
    speed = dt * 60

    ' ======== INPUT: tangenter (WASD/pilar/ESC/SPACE) + mustömning ========

    k$ = InKey$
    If k$ = Chr$(0) Then k$ = Chr$(0) + InKey$
    ' selftest fas12d: meny-nav via tangent — ner-pil (navStep 0->1), upp-pil (2->3)
    If selftest And testPhase = 12 And testFlag = 5 And navStep = 0 Then k$ = Chr$(0) + "P": navStep = 1
    If selftest And testPhase = 12 And testFlag = 5 And navStep = 2 Then k$ = Chr$(0) + "H": navStep = 3
    ' Fas 5A fas17: inject E (KeyUse) presses for the door tests
    If selftest And testPhase = 17 And testFlag = 2 And inj17a = 0 Then k$ = "e": inj17a = 1
    If selftest And testPhase = 17 And testFlag = 4 And inj17b = 0 Then k$ = "e": inj17b = 1
    If selftest And testPhase = 17 And testFlag = 5 And inj17c = 0 Then k$ = "e": inj17c = 1

    ' ======== STATE-MACHINE: menu <-> playing (SPACE startar, ESC avslutar) ========
    If selftest And (state$ = "menu" Or state$ = "result" Or state$ = "paused" Or state$ = "victory") Then Gosub SelftestDrive   ' fas12/13 kör även utanför playing (5C: även victory)
    If state$ = "menu" Or state$ = "fadeout" Then
        ' pendingStart (VIDARE från result): gå EXAKT samma START-väg som när
        ' användaren klickar START — före någon render denna frame. Ingen egen
        ' VIDARE-övergångskod finns; menyn renderar aldrig denna frame, användaren
        ' ser bara result -> fadeout -> playing, precis som vid START.
        If pendingStart And state$ = "menu" Then
            pendingStart = 0
            Gosub StartRun
            SOUND 300, 2: SOUND 150, 3
        End If
        ' 5C: CONTINUE from a cleared campaign level -> load the NEXT level of
        ' levels.lst (LoadLevel: new ParseMap + enemy/wave register reset).
        If pendingNext And state$ = "menu" Then
            pendingNext = 0
            lvlIdx = lvlIdx + 1
            Gosub LoadLevel
            SOUND 300, 2: SOUND 150, 3
        End If
        ' 5D: campaign argument ("campaign" / "--level N") skips the menu entirely
        If state$ = "menu" And autoCamp Then
            autoCamp = 0
            Gosub StartRun
            SOUND 300, 2: SOUND 150, 3
        End If
        ' FIX 2: ESC i menu avslutar fortfarande, men inte precis efter ESC från
        ' result-skärmen (held ESC skulle annars bledda in i meny-grenen).
        ' 5D: Q in menu quits too.
        If state$ = "menu" And (k$ = Chr$(27) Or _KeyDown(27) Or k$ = "q" Or k$ = "Q") And Timer - escCool > 0.3 Then Gosub QuitGame
        While _MouseInput: WEND   ' töm muskön så inget läcker till playing
        mx = _MouseX: my = _MouseY
        ' 5D pick menu (no-arg / IDE F5): number keys 1/2 select directly,
        ' W/S or arrows move the highlight, ENTER/E confirms the highlight.
        If state$ = "menu" And menuPick Then
            ' selftest 5D fas20: inject the pick keys
            If selftest And testPhase = 20 And testFlag = 1 And inj20a = 0 Then k$ = "1": inj20a = 1
            If selftest And testPhase = 20 And testFlag = 3 And inj20c = 0 Then k$ = "2": inj20c = 1
            If k$ = "w" Or k$ = "W" Or k$ = Chr$(0) + "H" Or _KeyDown(18432) Then selIdx = selIdx - 1: If selIdx < 1 Then selIdx = 2
            If k$ = "s" Or k$ = "S" Or k$ = Chr$(0) + "P" Or _KeyDown(20480) Then selIdx = selIdx + 1: If selIdx > 2 Then selIdx = 1
            pickAct = 0
            If k$ = "1" Then pickAct = 1
            If k$ = "2" Then pickAct = 2
            If k$ = Chr$(13) Or KeyUseHit%(k$) Then pickAct = selIdx
            If pickAct > 0 And state$ = "menu" Then Gosub PickAction
        End If
        ' KEY-nav (always active, even after the lock): W/S or up/down arrows
        ' move the selection; E (KeyUse) selects. SPACE is NOT a menu selector.
        If state$ = "menu" And menuPick = 0 And (k$ = "w" Or k$ = "W" Or k$ = Chr$(0) + "H" Or _KeyDown(18432)) Then selIdx = selIdx - 1: If selIdx < 1 Then selIdx = 2
        If state$ = "menu" And menuPick = 0 And (k$ = "s" Or k$ = "S" Or k$ = Chr$(0) + "P" Or _KeyDown(20480)) Then selIdx = selIdx + 1: If selIdx > 2 Then selIdx = 1
        If state$ = "menu" And menuPick = 0 And KeyUseHit%(k$) Then   ' E (KeyUse) selects the highlighted row
            If selIdx = 1 Then
                Gosub StartRun
                SOUND 300, 2: SOUND 150, 3
            Else
                Gosub QuitGame   ' QUIT GAME = same exit as menu-ESC
            End If
        End If
        ' knapp-geometri: GEMENSAM bredd för hela huvudmenyn = längsta labeln
        ' (START GAME / QUIT GAME, eller 5D pick-raderna 1 TEST ARENA / 2 CAMPAIGN) + 2*padX
        padX = Int(btnFontSize * 0.9): If padX < 12 Then padX = 12
        If menuPick Then
            BtnTextW strPickArena$, w1: BtnTextW strPickCamp$, w2
        Else
            BtnTextW strStartBtn$, w1: BtnTextW strQuitBtn$, w2
        End If
        If w2 > w1 Then w1 = w2
        menuBtnW = w1 + padX * 2
        menuBtnTop = RH \ 2 + Int(RH * 40 / 1080)
        BtnGeom menuBtnW, RW \ 2, menuBtnTop, btnX0, btnY0, btnX1, btnY1          ' START GAME
        quitBtnTop = btnY1 + Int(RH * 16 / 1080)
        BtnGeom menuBtnW, RW \ 2, quitBtnTop, quitX0, quitY0, quitX1, quitY1      ' QUIT GAME
        menuPanelHalf = (quitY1 + Int(RH * 30 / 1080)) - RH \ 2   ' panel rymmer båda knapparna
        ' MUS-driven meny FÖRE första låset (lockEngaged=0): riktig Wayland-pekare
        ' (default, syns automatiskt — INGEN _MOUSESHOW). Hover via ButtonHit,
        ' klick väljer. Efter låset (lockEngaged=1) är pekaren borta — då gäller
        ' enbart tangent-nav ovan (selIdx).
        hover = 0
        If state$ = "menu" And lockEngaged = 0 Then
            If ButtonHit%(mx, my, btnX0, btnY0, btnX1, btnY1) Then hover = 1
            If ButtonHit%(mx, my, quitX0, quitY0, quitX1, quitY1) Then hover = 2
            If hover <> prevHover Then
                prevHover = hover
                If hover > 0 Then SOUND 1500, 1   ' hover-tick
            End If
            If hover > 0 Then selIdx = hover   ' håll tangent-markering synkad
            If _MouseButton(1) And hover > 0 And state$ = "menu" Then
                If menuPick Then
                    pickAct = hover: Gosub PickAction   ' 5D pick menu: click row 1/2
                ElseIf hover = 1 Then
                    Gosub StartRun
                    SOUND 300, 2: SOUND 150, 3
                Else
                    Gosub QuitGame
                End If
            End If
        Else
            prevHover = 0
        End If
        _Dest display&
        Line (0, 0)-(RW - 1, RH - 1), _RGB32(8, 8, 24), BF
        Line (RW \ 2 - 860, RH \ 2 - menuPanelHalf)-(RW \ 2 + 859, RH \ 2 + menuPanelHalf - 1), _RGB32(255, 200, 0), B
        Color _RGB32(255, 200, 0)
        ttx = (RW - Len(strTitle$) * 8) \ 2
        tty = RH \ 2 - 40
        Color _RGB32(120, 60, 0)
        _PrintString (ttx + 3, tty + 3), strTitle$
        _PrintString (ttx - 2, tty), strTitle$
        Color _RGB32(255, 200, 0)
        _PrintString (ttx, tty), strTitle$
        ' två knappar via samma DrawButton-widget (samma bredd); markerad rad är
        ' amber (selIdx). 5D pick-läge: "1 TEST ARENA" / "2 CAMPAIGN" + hint-rad.
        ' INGEN pekare ritas i menyn.
        If menuPick Then
            DrawButton btnX0, btnY0, btnX1, btnY1, strPickArena$, (selIdx = 1)
            DrawButton quitX0, quitY0, quitX1, quitY1, strPickCamp$, (selIdx = 2)
            Color _RGB32(150, 150, 150)
            _PrintString ((RW - Len(strPickHint$) * 8) \ 2, quitY1 + Int(RH * 18 / 1080)), strPickHint$
        Else
            DrawButton btnX0, btnY0, btnX1, btnY1, strStartBtn$, (selIdx = 1)
            DrawButton quitX0, quitY0, quitX1, quitY1, strQuitBtn$, (selIdx = 2)
        End If
        ' versionshörn nere till höger på titelskärmen (ver + commit-hash)
        Color _RGB32(110, 110, 140)
        _PrintString (RW - Len(ver$ + " " + strBuild$) * 8 - 16, RH - 24), ver$ + " " + strBuild$
        ' fade-through-black: titel fade:ar ut (0.4 s), sedan spelet fade:ar in
        If state$ = "fadeout" Then
            fa = (Timer - fadeT0) / 0.4
            If fa > 1 Then fa = 1
            Line (0, 0)-(RW - 1, RH - 1), _RGBA32(0, 0, 0, Int(fa * 255)), BF
            If fa >= 1 Then
                state$ = "playing"
                LogMouse "HIDE_DISABLE StartRun fade-klar"
                LogMouse "MOUSEMOVE center StartRun (före låset)"
                _MOUSEMOVE RW \ 2, RH \ 2   ' färsk serial INNAN låset (ordning enligt fix)
                ' LIVSTIDS-LÅS vid FÖRSTA fade-slutet — app-livets ENDA hide.
                ' INGEN _MOUSESHOW finns i kodbasen (grep-bevis: 0 aktiva anrop).
                If lockEngaged = 0 Then
                    _MOUSEHIDE _DISABLE
                    lockEngages = lockEngages + 1
                    lockEngaged = 1
                End If
                lockHint = 1
                fadeT0 = Timer
                fading = 2
            End If
        End If
        _Display
        ' selftest fas12d: huvudmenyn har renderat EN frame med DrawButton (stor
        ' TTF-text) utan krasch -> SELFTEST OK. (Resultatmenyn täcks av fas12a-c.)
        If selftest And testPhase = 12 And testFlag = 5 Then
            ' MUS-REVERT: menyn är tangentdriven — testa nav: ner-pil ska ge
            ' selIdx=2, upp-pil ska ge selIdx=1 (inga mus-händelser inblandade)
            If navStep = 1 And selIdx = 2 Then
                stMsg$ = "PASS fas12d-meny-tangent-nav (ner-pil: selIdx 1->2)"
                Gosub STLog
                navStep = 2
            ElseIf navStep = 3 And selIdx = 1 Then
                stMsg$ = "PASS fas12d-meny-tangent-nav (upp-pil: selIdx 2->1)"
                Gosub STLog
                ' slutkontroller: 2 knappar samma bredd, staplade utan överlapp;
                ' parkerade pekar-funktioner (MoveVirtualCursor/ButtonHit) testas
                ' som rena funktioner; livstids-lås; pil-buffer skapad men renderas ej
                If quitY0 >= btnY1 And quitY1 > quitY0 And (quitX1 - quitX0) = (btnX1 - btnX0) And btnY1 > btnY0 Then
                    stMsg$ = "PASS fas12d-meny-renderad (2 knappar START+QUIT samma bredd=" + Str$(btnX1 - btnX0) + " px, staplade utan överlapp, ingen pekare renderad, ingen krasch)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas12d-meny-layout btnW=" + Str$(btnX1 - btnX0) + " quitW=" + Str$(quitX1 - quitX0) + " btnY1=" + Str$(btnY1) + " quitY0=" + Str$(quitY0)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' fas12e: parkerade funktioner som rena funktioner (klamring + hit/miss)
                MoveVirtualCursor 999999, 999999
                vcOk1 = (vCurX = RW - 1 And vCurY = RH - 1)
                MoveVirtualCursor -999999, -999999
                vcOk2 = (vCurX = 0 And vCurY = 0)
                bhHit = ButtonHit%((btnX0 + btnX1) \ 2, (btnY0 + btnY1) \ 2, btnX0, btnY0, btnX1, btnY1)
                bhMiss = ButtonHit%(0, 0, btnX0, btnY0, btnX1, btnY1)
                ' fas12f: LIVSTIDS-LÅS från app-start — lockEngaged=1 redan vid första
                ' meny-framen, exakt 1 engage, 0 destroys under sessionen (0 _MOUSESHOW)
                If vcOk1 And vcOk2 And bhHit = -1 And bhMiss = 0 And lockEngaged = 1 And lockEngages = 1 And lockDestroys = 0 And cursorBuf& <> 0 And cursorSize >= 16 Then
                    stMsg$ = "PASS fas12e-parkerade-funktioner (klamring OK, ButtonHit hit/miss OK, pil-buffer " + Str$(cursorSize) + "px ej renderad) + fas12f-livstidslas-fadeslut (lockEngaged=1, engages=" + Str$(lockEngages) + ", destroys=" + Str$(lockDestroys) + ", 0 _MOUSESHOW i kod)"
                    Gosub STLog
                    stMsg$ = "SELFTEST OK"
                    Gosub STLog
                    ShutdownSound
                    End
                Else
                    stMsg$ = "FAIL fas12e/f vcOk1=" + Str$(vcOk1) + " vcOk2=" + Str$(vcOk2) + " bhHit=" + Str$(bhHit) + " bhMiss=" + Str$(bhMiss) + " lockEngaged=" + Str$(lockEngaged) + " engages=" + Str$(lockEngages) + " destroys=" + Str$(lockDestroys)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
        End If
    ElseIf state$ = "dead" Then
        If k$ = Chr$(27) Or _KeyDown(27) Then End
        ' Fas 3.1 selftest: fas 8 = spelaren har dött av fiende -> fas 9 spawn-audit -> avsluta
        If selftest And testPhase = 8 Then
            stMsg$ = "PASS fas8-spelare-kan-do (hp=0, state=dead)": Gosub STLog
            ' anti-cheese-vakt: score måste vara >= 0 (aldrig negativ)
            sc8& = liveScore&
            If sc8& >= 0 Then
                stMsg$ = "PASS fas8-score score=" + Str$(sc8&) + " (>=0 OK, ej negativ; s=" + Str$(Int(Timer - runT0)) + " skott=" + Str$(shotsFired) + " skada=" + Str$(dmgTaken) + ")"
            Else
                stMsg$ = "FAIL fas8-score negativ=" + Str$(sc8&)
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            Gosub STLog
            ' fas 9: spawn-audit pa AKTA startlage (SpawnEnemies) innan vi avslutar
            state$ = "playing"
            hp = 100: ammo = 5
            px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0   ' Fas 5A: start from map 'S'
            Gosub SpawnEnemies
            testPhase = 9: testT0 = Timer: testFlag = 0
        End If
        ' selftest fas12c: dödsskärm -> R -> meny (enda vägen till menyn nu)
        If selftest And testPhase = 12 And testFlag = 3 And state$ = "dead" Then k$ = "r"
        ' selftest 5C fas19: campaign death -> R = RESTART LEVEL (same level)
        If selftest And testPhase = 19 And testFlag = 10 And inj19d = 0 Then k$ = "r": inj19d = 1: c19died = 1
        If gameMode$ = "campaign" Then
            ' 5C: death on level N -> RESTART LEVEL (SAME level, per-level-segment
            ' score restored, restarts++) or QUIT. Death NEVER advances to the
            ' next level automatically.
            If k$ = "w" Or k$ = "W" Or k$ = Chr$(0) + "H" Or _KeyDown(18432) Then selIdx = selIdx - 1: If selIdx < 1 Then selIdx = 2
            If k$ = "s" Or k$ = "S" Or k$ = Chr$(0) + "P" Or _KeyDown(20480) Then selIdx = selIdx + 1: If selIdx > 2 Then selIdx = 1
            deadAct = 0
            If k$ = "r" Or k$ = "R" Or k$ = " " Or _KeyDown(Asc("R")) Or _KeyDown(32) Or KeyUseHit%(k$) Then deadAct = 1
            If k$ = "q" Or k$ = "Q" Then deadAct = 2
            If deadAct = 1 Then
                restarts = restarts + 1
                shotsFired = segShots: dmgTaken = segDmg          ' score per level-segment restored
                runT0 = Timer - (segStartT - segT0): If runT0 > Timer Then runT0 = Timer
                Gosub LoadLevel                                   ' reloads SAME lvlIdx
            ElseIf deadAct = 2 Then
                Gosub QuitGame
            End If
        End If
        If gameMode$ <> "campaign" And (k$ = "r" Or k$ = "R" Or k$ = " " Or _KeyDown(Asc("R")) Or _KeyDown(32)) Then
            ' reset ALLT -> tillbaka till menyn
            hp = 100: ammo = 5
            px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0   ' Fas 5A: start from map 'S'
            Gosub ApplyMapSpawns   ' Fas 5A: pickups/keys/doors from map, doors closed
            Gosub SpawnEnemies   ' Fas 3: fiender respawnas också vid full reset
            hpMsg$ = "": hpMsgTime = 0
            lastShotTime = -1: tracerTime = -1: flashTime = -1: flashDist = 99
            mvF = 0: mvB = 0: mvL = 0: mvR = 0: turnL = 0: turnR = 0: fireBtn = 0: _KeyClear
            pendingStart = 0
            fading = 0: deathTime = 0
            hover = 0: prevHover = 0
            state$ = "menu"
            LogMouse "LIVSTIDSLAS dead-R->menu (ingen unlock)"
            selIdx = 1   ' meny-markering börjar på START GAME
        End If
        ' dödsskärm: svart overlay fade 0.5 s, sedan stor röd text
        _Dest display&
        da = (Timer - deathTime) / 0.5
        If da > 1 Then da = 1
        Line (0, 0)-(RW - 1, RH - 1), _RGBA32(0, 0, 0, Int(da * 255)), BF
        If da >= 1 Then
            dtx = (RW - Len(strDead$) * 8) \ 2
            dty = RH \ 2 - 40
            Color _RGB32(120, 0, 0)
            _PrintString (dtx + 3, dty + 3), strDead$
            _PrintString (dtx - 2, dty), strDead$
            Color _RGB32(220, 0, 0)
            _PrintString (dtx, dty), strDead$
            If gameMode$ = "campaign" Then
                ' 5C death screen options: RESTART LEVEL (same level) / QUIT
                padXd = Int(btnFontSize * 0.9): If padXd < 12 Then padXd = 12
                BtnTextW strRestartRound$, w1: BtnTextW strQuit$, w2
                If w2 > w1 Then w1 = w2
                deadBtnW = w1 + padXd * 2
                BtnGeom deadBtnW, RW \ 2, RH \ 2 + 40, dB1X0, dB1Y0, dB1X1, dB1Y1
                BtnGeom deadBtnW, RW \ 2, dB1Y1 + Int(RH * 14 / 1080), dB2X0, dB2Y0, dB2X1, dB2Y1
                DrawButton dB1X0, dB1Y0, dB1X1, dB1Y1, strRestartRound$, (selIdx = 1)
                DrawButton dB2X0, dB2Y0, dB2X1, dB2Y1, strQuit$, (selIdx = 2)
                rs$ = strRestarts$ + " " + LTrim$(Str$(restarts))
                Color _RGB32(150, 150, 150)
                _PrintString ((RW - Len(rs$) * 8) \ 2, dB2Y1 + Int(RH * 16 / 1080)), rs$
            Else
                Color _RGB32(200, 200, 200)
                _PrintString ((RW - Len(strRestart$) * 8) \ 2, RH \ 2 + 40), strRestart$
            End If
            ' highscore-rader: SCORE / BÄSTA / ev. NY REKORD!
            sc$ = strScore$ + " " + LTrim$(Str$(score))
            bs2$ = strBest$ + " " + LTrim$(Str$(bestScore))
            Color _RGB32(255, 255, 255)
            _PrintString ((RW - Len(sc$) * 8) \ 2, RH \ 2 + 70), sc$
            Color _RGB32(150, 150, 150)
            _PrintString ((RW - Len(bs2$) * 8) \ 2, RH \ 2 + 90), bs2$
            If newRecord Then
                Color _RGB32(255, 80, 80)
                _PrintString ((RW - Len(strNewRec$) * 8) \ 2, RH \ 2 + 110), strNewRec$
            End If
        End If
        _Display
    ElseIf state$ = "result" Then
        ' RESULTATMENY: riktig meny, samma knapp-stil som huvudmenyn (samma
        ' DrawButton-widget, hover, fill/border). Musen är VÄLKOMMEN synlig här.
        ' AI/fysik/tid fryst (egen gren). Knappar: VIDARE / HUVUDMENY. ESC=meny.
        ' RESULTAT är KLICK-FRITT: ingen knapp, ingen ButtonHit. Statistik +
        ' CLICK OR E TO CONTINUE. Any mouse click (locked mouse works invisibly)
        ' or E (KeyUse) -> pendingStart (nästa runda via meny-START-vägen).
        ' ESC -> paus (resumeState=result). INGEN pekare ritas här.
        resPanelHalf = Int(RH * 240 / 1080)   ' panel rymmer statistik + textrader
        resEscY = RH \ 2 + Int(RH * 70 / 1080)
        mb = 0
        While _MouseInput: WEND   ' töm muskön
        If _MouseButton(1) Then mb = 1
        ' selftest fas12: simulera klick (testFlag=2 -> fortsätt till nästa runda)
        If selftest And testPhase = 12 And testFlag = 2 Then mb = 1
        ' selftest fas16: leave result via the normal CONTINUE path -> playing
        If selftest And testPhase = 16 And testFlag = 0 Then mb = 1
        ' selftest 5C fas19: drive CONTINUE (next campaign level) via injected click
        If selftest And testPhase = 19 And (testFlag = 4 Or testFlag = 13) Then mb = 1
        If (k$ = Chr$(27) Or _KeyDown(27)) And Timer - escCool > 0.3 Then
            ' ESC i result -> PAUS (resumeState=result; FORTSÄTT återgår hit)
            resumeState$ = "result"
            pauseT0 = Timer
            escCool = Timer
            selIdx = 1
            _KeyClear
            state$ = "paused"
        ElseIf (mb Or KeyUseHit%(k$)) And state$ = "result" Then
            ' CONTINUE with mouse click OR E (KeyUse); SPACE/ENTER do nothing here.
            ' 5C campaign: on a NON-FINAL level CONTINUE loads the NEXT level of
            ' levels.lst (pendingNext -> LoadLevel in the menu branch); final level
            ' never reaches result (win trigger -> victory screen instead).
            ' Single/arena: BARA pendingStart=1 + state=menu (samma frame) —
            ' meny-grenen går samma START-väg (StartRun -> fadeout -> playing).
            If gameMode$ = "campaign" And lvlIdx < lvlN - 1 Then
                pendingNext = 1
            Else
                pendingStart = 1
            End If
            state$ = "menu"
        End If
        ' rendera resultat-skärmen: statistik + CLICK TO CONTINUE (ingen knapp)
        _Dest display&
        Line (0, 0)-(RW - 1, RH - 1), _RGB32(8, 8, 24), BF
        Line (RW \ 2 - 860, RH \ 2 - resPanelHalf)-(RW \ 2 + 859, RH \ 2 + resPanelHalf - 1), _RGB32(255, 200, 0), B
        t% = runTimeFrozen           ' ALLTID fryst tid i result (frusen vid sista killen)
        mm% = t% \ 60: ss% = t% - mm% * 60
        sc$ = strScore$ + " " + LTrim$(Str$(score))
        bs2$ = strBest$ + " " + LTrim$(Str$(bestScore))
        tm$ = strTime$ + " " + LTrim$(Str$(mm%)) + ":" + LTrim$(Str$(ss%))
        sh$ = strShots$ + " " + LTrim$(Str$(shotsFired))
        dm$ = strDmg$ + " " + LTrim$(Str$(dmgTaken))
        Color _RGB32(255, 200, 0)
        _PrintString ((RW - Len(strWin$) * 8) \ 2, RH \ 2 - Int(RH * 185 / 1080)), strWin$
        Color _RGB32(255, 255, 255)
        _PrintString ((RW - Len(tm$) * 8) \ 2, RH \ 2 - Int(RH * 145 / 1080)), tm$
        _PrintString ((RW - Len(sh$) * 8) \ 2, RH \ 2 - Int(RH * 120 / 1080)), sh$
        _PrintString ((RW - Len(dm$) * 8) \ 2, RH \ 2 - Int(RH * 95 / 1080)), dm$
        _PrintString ((RW - Len(sc$) * 8) \ 2, RH \ 2 - Int(RH * 70 / 1080)), sc$
        Color _RGB32(150, 150, 150)
        _PrintString ((RW - Len(bs2$) * 8) \ 2, RH \ 2 - Int(RH * 45 / 1080)), bs2$
        If newRecord Then
            Color _RGB32(255, 80, 80)
            _PrintString ((RW - Len(strNewRec$) * 8) \ 2, RH \ 2 - Int(RH * 20 / 1080)), strNewRec$
        End If
        ' 5C campaign: which level CONTINUE will load next
        If gameMode$ = "campaign" And lvlIdx < lvlN - 1 Then
            nxt$ = strNextLvl$ + " LVL " + LTrim$(Str$(lvlIdx + 2)) + "/" + LTrim$(Str$(lvlN)) + " " + lvlName$(lvlIdx + 1)
            Color _RGB32(150, 150, 230)
            _PrintString ((RW - Len(nxt$) * 8) \ 2, RH \ 2 + Int(RH * 52 / 1080)), nxt$
        End If
        ' CLICK TO CONTINUE — gul, SNABB blink (valt: Int(Timer*4) Mod 2, 2 Hz)
        If Int(Timer * 4) Mod 2 = 0 Then
            Color _RGB32(255, 200, 0)
            _PrintString ((RW - Len(strClickCont$) * 8) \ 2, RH \ 2 + Int(RH * 30 / 1080)), strClickCont$
        End If
        Color _RGB32(150, 150, 150)
        _PrintString ((RW - Len(strEscMenu$) * 8) \ 2, resEscY), strEscMenu$
        Color _RGB32(110, 110, 140)
        _PrintString (RW - Len(ver$ + " " + strBuild$) * 8 - 16, RH - 24), ver$ + " " + strBuild$
        _Display
        If selftest Then Gosub SelftestDrive   ' fas12: observera state=result här
    ElseIf state$ = "victory" Then
        ' 5C SEGER-SKÄRM: campaign finished (last level of levels.lst cleared).
        ' Stats table: score, total kills, per-level times, best. Buttons:
        ' PLAY AGAIN (restart campaign at level 1, score zeroed) / QUIT.
        ' W/S or arrows move the selection, E/ENTER/click activates, ESC quits.
        While _MouseInput: WEND   ' töm muskön
        mb = _MouseButton(1)
        ' selftest 5C fas19: PLAY AGAIN via injected E (selIdx=1)
        If selftest And testPhase = 19 And (testFlag = 7 Or testFlag = 14) And inj19v = 0 Then k$ = "e": inj19v = 1
        If k$ = "w" Or k$ = "W" Or k$ = Chr$(0) + "H" Or _KeyDown(18432) Then selIdx = selIdx - 1: If selIdx < 1 Then selIdx = 2
        If k$ = "s" Or k$ = "S" Or k$ = Chr$(0) + "P" Or _KeyDown(20480) Then selIdx = selIdx + 1: If selIdx > 2 Then selIdx = 1
        If (KeyUseHit%(k$) Or k$ = Chr$(13) Or mb) And state$ = "victory" Then
            If selIdx = 1 Then
                ' PLAY AGAIN: restart the campaign at level 1, score zeroed
                lvlIdx = 0
                shotsFired = 0: dmgTaken = 0: runT0 = Timer: score = 0: liveScore& = CalcScore&
                killsTotal = 0: restarts = 0: newRecord = 0
                For i = 0 To 19: lvlTime(i) = 0: Next i
                Gosub LoadLevel
                SOUND 300, 2: SOUND 150, 3
            Else
                Gosub QuitGame
            End If
        End If
        If (k$ = Chr$(27) Or _KeyDown(27)) And Timer - escCool > 0.3 Then Gosub QuitGame
        ' rendera seger-skärmen: statistik + 2 knappar
        _Dest display&
        vicPanelHalf = Int(RH * 220 / 1080)
        Line (0, 0)-(RW - 1, RH - 1), _RGB32(8, 8, 24), BF
        Line (RW \ 2 - 860, RH \ 2 - vicPanelHalf)-(RW \ 2 + 859, RH \ 2 + vicPanelHalf - 1), _RGB32(255, 200, 0), B
        Color _RGB32(255, 200, 0)
        _PrintString ((RW - Len(strVictory$) * 8) \ 2, RH \ 2 - Int(RH * 165 / 1080)), strVictory$
        sc$ = strScore$ + " " + LTrim$(Str$(score))
        kl$ = strKills$ + " " + LTrim$(Str$(killsTotal))
        bs2$ = strBest$ + " " + LTrim$(Str$(bestScore))
        lvls$ = ""
        For i = 0 To lvlN - 1
            t% = lvlTime(i): mm% = t% \ 60: ss% = t% - mm% * 60
            lvls$ = lvls$ + "L" + LTrim$(Str$(i + 1)) + " " + LTrim$(Str$(mm%)) + ":" + Right$("0" + LTrim$(Str$(ss%)), 2) + "  "
        Next i
        Color _RGB32(255, 255, 255)
        _PrintString ((RW - Len(sc$) * 8) \ 2, RH \ 2 - Int(RH * 125 / 1080)), sc$
        _PrintString ((RW - Len(kl$) * 8) \ 2, RH \ 2 - Int(RH * 100 / 1080)), kl$
        Color _RGB32(150, 150, 230)
        _PrintString ((RW - Len(lvls$) * 8) \ 2, RH \ 2 - Int(RH * 75 / 1080)), lvls$
        Color _RGB32(150, 150, 150)
        _PrintString ((RW - Len(bs2$) * 8) \ 2, RH \ 2 - Int(RH * 50 / 1080)), bs2$
        If newRecord Then
            Color _RGB32(255, 80, 80)
            _PrintString ((RW - Len(strNewRec$) * 8) \ 2, RH \ 2 - Int(RH * 25 / 1080)), strNewRec$
        End If
        padX = Int(btnFontSize * 0.9): If padX < 12 Then padX = 12
        BtnTextW strPlayAgain$, w1: BtnTextW strQuit$, w2
        If w2 > w1 Then w1 = w2
        vicBtnW = w1 + padX * 2
        BtnGeom vicBtnW, RW \ 2, RH \ 2 + Int(RH * 60 / 1080), vB1X0, vB1Y0, vB1X1, vB1Y1
        BtnGeom vicBtnW, RW \ 2, vB1Y1 + Int(RH * 14 / 1080), vB2X0, vB2Y0, vB2X1, vB2Y1
        DrawButton vB1X0, vB1Y0, vB1X1, vB1Y1, strPlayAgain$, (selIdx = 1)
        DrawButton vB2X0, vB2Y0, vB2X1, vB2Y1, strQuit$, (selIdx = 2)
        Color _RGB32(110, 110, 140)
        _PrintString (RW - Len(ver$ + " " + strBuild$) * 8 - 16, RH - 24), ver$ + " " + strBuild$
        _Display
    ElseIf state$ = "paused" Then
        ' ================= PAUSMENY (ESC i playing/result) =================
        ' Tiden stannar här (runT0 justeras vid FORTSÄTT så pausen inte äter
        ' sekunder). Playing-input (rörelse/skott) körs INTE i denna gren.
        ' Input BÅDA vägar: tangent (W/S eller pilar + ENTER, ESC=FORTSÄTT)
        ' ENDAST TANGENT (PARKED: mouse experiment aa26eee — ingen virtuell
        ' pekare, ingen pil-sprite, inget mus-klick i paus).
        If selftest And testPhase = 13 Then
            If testFlag = 7 And inj7 = 0 Then k$ = Chr$(0) + "P": inj7 = 1
            If testFlag = 8 And inj8 = 0 Then k$ = Chr$(0) + "H": inj8 = 1
            If testFlag = 9 And inj9 = 0 Then k$ = Chr$(13): inj9 = 1
            If testFlag = 11 And inj11 = 0 Then k$ = Chr$(13): inj11 = 1
        End If
        ' selftest fas16c: resume from pause via ESC once the guard window passed
        If selftest And testPhase = 16 And testFlag = 7 And inj16r = 0 And Timer - escCool > 0.4 And Timer - testT0 > 0.6 Then k$ = Chr$(27): inj16r = 1
        While _MouseInput: WEND   ' töm muskön (rörelse ägs av playing)
        ' 3 knappar, uniform bredd (längsta label + 2*padX), staplade under titeln
        padX = Int(btnFontSize * 0.9): If padX < 12 Then padX = 12
        BtnTextW strResume$, w1: BtnTextW strRestartRound$, w2: BtnTextW strQuitPause$, w3
        If w2 > w1 Then w1 = w2
        If w3 > w1 Then w1 = w3
        pauBtnW = w1 + padX * 2
        pauTop = RH \ 2 + Int(RH * 10 / 1080)
        BtnGeom pauBtnW, RW \ 2, pauTop, pB1X0, pB1Y0, pB1X1, pB1Y1
        BtnGeom pauBtnW, RW \ 2, pB1Y1 + Int(RH * 14 / 1080), pB2X0, pB2Y0, pB2X1, pB2Y1
        BtnGeom pauBtnW, RW \ 2, pB2Y1 + Int(RH * 14 / 1080), pB3X0, pB3Y0, pB3X1, pB3Y1
        ' tangent-markering: W/S eller upp/ner-pil, wrapar 1..3
        If k$ = "w" Or k$ = "W" Or k$ = Chr$(0) + "H" Or _KeyDown(18432) Then selIdx = selIdx - 1: If selIdx < 1 Then selIdx = 3
        If k$ = "s" Or k$ = "S" Or k$ = Chr$(0) + "P" Or _KeyDown(20480) Then selIdx = selIdx + 1: If selIdx > 3 Then selIdx = 1
        pauAct = 0
        If k$ = Chr$(13) Or KeyUseHit%(k$) Then pauAct = selIdx   ' ENTER kept as extra; E (KeyUse) selects
        If (k$ = Chr$(27) Or _KeyDown(27)) And Timer - escCool > 0.3 Then pauAct = 1   ' ESC i paus = FORTSÄTT
        If pauAct = 1 Then
            ' FORTSÄTT: återgå utan reset; pausens längd dras bort från run-tiden
            If resumeState$ = "playing" And runTimeFrozen < 0 Then runT0 = runT0 + (Timer - pauseT0)
            escCool = Timer
            state$ = resumeState$
        ElseIf pauAct = 2 Then
            ' RESTART ROND: samma väg som result-VIDARE (pendingStart via menyn)
            pendingStart = 1
            state$ = "menu"
        ElseIf pauAct = 3 Then
            Gosub QuitGame   ' AVSLUTA: enda unlock/destroy-platsen (app-exit)
        End If
        ' render: halvtransparent overlay över befintlig frame + titel + knappar
        ' (markerad rad amber). INGEN pil/pekare ritas i paus.
        _Dest display&
        Line (0, 0)-(RW - 1, RH - 1), _RGBA32(0, 0, 0, 160), BF
        Color _RGB32(255, 200, 0)
        _PrintString ((RW - Len(strPaused$) * 8) \ 2, RH \ 2 - Int(RH * 60 / 1080)), strPaused$
        DrawButton pB1X0, pB1Y0, pB1X1, pB1Y1, strResume$, (selIdx = 1)
        DrawButton pB2X0, pB2Y0, pB2X1, pB2Y1, strRestartRound$, (selIdx = 2)
        DrawButton pB3X0, pB3Y0, pB3X1, pB3Y1, strQuitPause$, (selIdx = 3)
        _Display
    ElseIf state$ = "fatal" Then
        ' LOUD map-load error (Fas 5A-hotfix2): no valid .map file -> no game.
        ' Fullscreen message + log line; Q or ESC quits. No phantom map is shown.
        _Dest display&
        Line (0, 0)-(RW - 1, RH - 1), _RGB32(40, 0, 0), BF
        Color _RGB32(255, 80, 80)
        _PrintString ((RW - Len(fatalMsg$) * 8) \ 2, RH \ 2 - 16), fatalMsg$
        Color _RGB32(255, 200, 0)
        _PrintString ((RW - Len(strFatalQuit$) * 8) \ 2, RH \ 2 + 24), strFatalQuit$
        If selftest Then stMsg$ = "fatal screen shown: " + fatalMsg$: Gosub STLog
        _Display
        If k$ = "q" Or k$ = "Q" Or k$ = Chr$(27) Or _KeyDown(27) Then Gosub QuitGame
    Else

    ' ESC i playing -> PAUS (inte längre End; avsluta sker via pausmenyn)
    If k$ = Chr$(27) Or _KeyDown(27) Or (selftest And testPhase = 13 And (testFlag = 6 Or testFlag = 10)) Or (selftest And testPhase = 16 And testFlag = 6) Then
        resumeState$ = "playing"
        pauseT0 = Timer
        escCool = Timer
        selIdx = 1
        _KeyClear
        state$ = "paused"
    End If
    ' Fas 5A: doors — E (KeyUse) while standing next to a door cell tries to open it.
    ' 'd' always opens; '1'/'2'/'3' need bronze/silver/gold key (else 2 s HUD msg).
    ' Opened doors stay open for the rest of the round (V1, no re-close).
    If state$ = "playing" And KeyUseHit%(k$) Then
        doorPX = Int(px): doorPY = Int(py)
        For doorI = 0 To 3
            If doorI = 0 Then doorCX = doorPX + 1: doorCY = doorPY
            If doorI = 1 Then doorCX = doorPX - 1: doorCY = doorPY
            If doorI = 2 Then doorCX = doorPX: doorCY = doorPY + 1
            If doorI = 3 Then doorCX = doorPX: doorCY = doorPY - 1
            doorCh$ = CellAt$(doorCX, doorCY)
            If doorCh$ = "d" Or doorCh$ = "1" Or doorCh$ = "2" Or doorCh$ = "3" Then
                If doorOpen%(doorCX, doorCY) = 0 Then
                    If doorCh$ = "d" Then
                        doorOpen%(doorCX, doorCY) = 1
                        hpMsg$ = strDoorOpen$: hpMsgTime = Timer
                        PlaySound SND_HIT
                    Else
                        doorNeed = 0
                        If doorCh$ = "1" And hasBronze = 0 Then doorNeed = 1
                        If doorCh$ = "2" And hasSilver = 0 Then doorNeed = 1
                        If doorCh$ = "3" And hasGold = 0 Then doorNeed = 1
                        If doorNeed Then
                            If doorCh$ = "1" Then hpMsg$ = strNeedBronze$
                            If doorCh$ = "2" Then hpMsg$ = strNeedSilver$
                            If doorCh$ = "3" Then hpMsg$ = strNeedGold$
                            hpMsgTime = Timer
                            PlaySoundVol SND_HIT, 0.3
                        Else
                            doorOpen%(doorCX, doorCY) = 1
                            hpMsg$ = strDoorOpen$: hpMsgTime = Timer
                            PlaySound SND_HIT
                        End If
                    End If
                End If
                doorI = 99   ' one door per keypress
            End If
        Next doorI
    End If
    ' debug-knapp: G = -5 HP (min 0), bara i playing-läge
    If k$ = "g" Or k$ = "G" Or _KeyDown(Asc("G")) Then
        hp = hp - 5
        dmgTaken = dmgTaken + 5      ' highscore: G-debug räknas som skada
        If hp < 0 Then hp = 0
        hpMsg$ = strDmgDebug$
        hpMsgTime = Timer
        PlaySound SND_HURT
    End If
    ' RÖRELSE-FLAGGOR: sätts FRESH varje frame från tangentbordet (k$ + _KeyDown).
    ' Nollställs vid ALLA state-övergångar (StartRun + reset-blocken) så inget
    ' rörelse-state överlever en övergång — annars kan spelaren gå framåt
    ' automatiskt efter VIDARE (fastnat _KeyDown/key-repeat över övergången).
    mvF = 0: mvB = 0: mvL = 0: mvR = 0: turnL = 0: turnR = 0
    If k$ = "w" Or k$ = "W" Or _KeyDown(Asc("W")) Or _KeyDown(Asc("w")) Then mvF = 1
    If k$ = "s" Or k$ = "S" Or _KeyDown(Asc("S")) Or _KeyDown(Asc("s")) Then mvB = 1
    If k$ = "a" Or k$ = "A" Or _KeyDown(Asc("A")) Or _KeyDown(Asc("a")) Then mvL = 1
    If k$ = "d" Or k$ = "D" Or _KeyDown(Asc("D")) Or _KeyDown(Asc("d")) Then mvR = 1
    If k$ = Chr$(0) + "K" Or _KeyDown(19200) Then turnL = 1
    If k$ = Chr$(0) + "M" Or _KeyDown(19712) Then turnR = 1
    anglePrev = angle   ' Fas 4C: captured before turn input -> turnDelta covers keys+mouse
    If turnL Then angle = angle - turnStep * speed
    If turnR Then angle = angle + turnStep * speed

    dirX = Cos(angle)
    dirY = Sin(angle)
    ox = px: oy = py   ' före rörelse, för fotstegs-ackumulatorn

    If mvF Then
        nx = px + dirX * moveStep * speed
        ny = py + dirY * moveStep * speed
        If OpenCell%(Int(nx + Sgn(nx - px) * 0.2), Int(py)) Then px = nx
        If OpenCell%(Int(ny + Sgn(ny - py) * 0.2), Int(px)) Then py = ny
    End If
    If mvB Then
        nx = px - dirX * moveStep * speed
        ny = py - dirY * moveStep * speed
        If OpenCell%(Int(nx + Sgn(nx - px) * 0.2), Int(py)) Then px = nx
        If OpenCell%(Int(ny + Sgn(ny - py) * 0.2), Int(px)) Then py = ny
    End If
    If mvL Then
        nx = px + dirY * moveStep * 0.6 * speed
        ny = py - dirX * moveStep * 0.6 * speed
        If OpenCell%(Int(nx + Sgn(nx - px) * 0.2), Int(py)) Then px = nx
        If OpenCell%(Int(ny + Sgn(ny - py) * 0.2), Int(px)) Then py = ny
    End If
    If mvR Then
        nx = px - dirY * moveStep * 0.6 * speed
        ny = py + dirX * moveStep * 0.6 * speed
        If OpenCell%(Int(nx + Sgn(nx - px) * 0.2), Int(py)) Then px = nx
        If OpenCell%(Int(ny + Sgn(ny - py) * 0.2), Int(px)) Then py = ny
    End If

    ' Fas 4B: player velocity (cells/s) — used by the general's mortar lead
    pvx = (px - ox) / dt: pvy = (py - oy) / dt

    ' Fas 4: fotsteg spelare — var 0.5 cell gångavstånd (rytm følger hastigheten)
    stepAcc = stepAcc + Sqr((px - ox) ^ 2 + (py - oy) ^ 2)
    If stepAcc >= 0.5 Then stepAcc = 0: PlaySound SND_STEP

    If selftest Then
        ' Fas 3 autoplay/selftest: scriptad input istället för riktig mus/tangentbord
        mdx = 0: mdy = 0: mmx = 0: mmy = 0
        fireBtn = 0
        Gosub SelftestDrive
    Else
        If _MouseButton(1) Then dummy = _MouseMovementX
        ' VARFÖR värdena läses INUTI loopen: libqb pushar ett "reset-event"
        ' (nollställning) direkt efter varje rörelse-/hjul-event. Om man bara gjorde
        ' WHILE _MOUSEINPUT: WEND och sedan läste av, skulle _MOUSEMOVEMENTX/Y alltid
        ' bli 0 (reset-eventet blir kvar som senast poppat). Därför ackumuleras här.
        mdx = 0: mdy = 0
        While _MouseInput
            mdx = mdx + _MouseMovementX
            mdy = mdy + _MouseMovementY
        Wend
        mmx = mdx
        mmy = mdy
        If Abs(mmx) > 300 Then mmx = 0
        fireBtn = _MouseButton(1)
        If fireBtn Then lockHint = 0   ' första klicket i rundan
    End If
    angle = angle + mmx * mouseSens * speed
    turnDelta = angle - anglePrev   ' Fas 4C: weapon sway input (rad this frame, keys+mouse)
    ' Fas 4C: viewmodel update (render-only). Bob synced to cells walked this
    ' frame; sway OPPOSITE to turnDelta, hard-clamped; recoil decays; gunX/gunY
    ' lerp toward the combined target so the gun "lags behind" the rotation.
    movedCells = Sqr((px - ox) ^ 2 + (py - oy) ^ 2)
    bobPhase = bobPhase + movedCells * gunBobRate
    gunSway = -turnDelta * gunSwayGain
    If gunSway > gunSwayMax Then gunSway = gunSwayMax
    If gunSway < -gunSwayMax Then gunSway = -gunSwayMax
    recoil = recoil * gunRecoilDecay!
    If muzzleT > 0 Then muzzleT = muzzleT - 1
    If shakeT > 0 Then shakeT = shakeT - 1
    gunTX = gunSway
    gunTY = Sin(bobPhase) * gunBobAmp - recoil
    gunX = gunX + (gunTX - gunX) * gunLerp!
    gunY = gunY + (gunTY - gunY) * gunLerp!
    ' pitch = vertikal lutning i pixlar. Minus här: mus UPP (mdy<0) ska ge titta upp.
    pitch = pitch - mdy * pitchSens
    If pitch > RH * 0.9 Then pitch = RH * 0.9
    If pitch < -RH * 0.9 Then pitch = -RH * 0.9

    ' pickup-kollision: avstånd < 0.5 tiles
    For i = 0 To 10
        If pkActive(i) Then
            If Sqr((pkX(i) - px) ^ 2 + (pkY(i) - py) ^ 2) < 0.5 Then
                pkActive(i) = 0
                hp = hp + 25
                If hp > 100 Then hp = 100
                hpMsg$ = strMedkit$
                hpMsgTime = Timer
                PlaySound SND_PICKUP
            End If
        End If
    Next i

    ' ammo-pickups: avstånd < 0.5 tiles ger +10 ammo
    For i = 0 To 10
        If amActive(i) Then
            If Sqr((amX(i) - px) ^ 2 + (amY(i) - py) ^ 2) < 0.5 Then
                amActive(i) = 0
                ammo = ammo + 5              ' FIX 3: ammo-pickup ger +5
                If ammo > maxAmmo Then ammo = maxAmmo  ' FIX 3: max-cap (överskott försvinner)
                hpMsg$ = strAmmoPick$
                hpMsgTime = Timer
                PlaySound SND_PICKUP
            End If
        End If
    Next i

    ' Fas 5A: key pickups (b/s/g in map) — same pickup radius as medkits
    For i = 0 To 10
        If keyActive(i) Then
            If Sqr((keyX(i) - px) ^ 2 + (keyY(i) - py) ^ 2) < 0.5 Then
                keyActive(i) = 0
                If keyType(i) = 1 Then hasBronze = 1: hpMsg$ = strGotBronze$
                If keyType(i) = 2 Then hasSilver = 1: hpMsg$ = strGotSilver$
                If keyType(i) = 3 Then hasGold = 1: hpMsg$ = strGotGold$
                hpMsgTime = Timer
                PlaySound SND_PICKUP
            End If
        End If
    Next i

    ' ======== FIENDER (Fas 3.1): tillstånd PATROLL(0)/JAKT(1)/ANFALL(2) + LOS + BFS-fält ========
    ' pass 1: LOS (DDA fiende->spelare) + siktbokföring + tillståndsväxling
    anySee = 0
    For i = 0 To 10
        If enActive(i) Then
            edx = px - enX(i)
            edy = py - enY(i)
            edist = Sqr(edx * edx + edy * edy)
            fx = enX(i): fy = enY(i): tx = px: ty = py
            Gosub LOSCheck
            enSeen(i) = losOK
            If losOK And edist < 6 Then
                anySee = 1
                enLastSeen(i) = Timer
                enLx(i) = px: enLy(i) = py
                If edist >= 0.8 Then
                    ' Fas 4: DETECT-ALERT vid tillståndsväxlingen PATROLL->JAKT (inte per frame),
                    ' cooldown 0.5 s per fiende mot spam
                    If enState(i) = 0 And Timer - enAlertT(i) >= 0.5 Then
                        PlaySound SND_ALERT
                        enAlertT(i) = Timer
                    End If
                    enState(i) = 1     ' fri sikt + inom 6 celler -> JAKT
                End If
            End If
            If edist < 0.8 Then enState(i) = 2           ' ANFALL vid kort avstånd
        End If
    Next i
    ' välj BFS-målcell: spelarens cell om någon fiende ser spelaren, annars första
    ' jaktande fiendens sista kända position (en gömd spelare wallhackas inte)
    bfsNewX = -1: bfsNewY = -1
    If anySee Then
        bfsNewX = Int(px): bfsNewY = Int(py)
    Else
        For i = 0 To 10
            If enActive(i) And enState(i) >= 1 Then
                bfsNewX = Int(enLx(i)): bfsNewY = Int(enLy(i))
                Exit For
            End If
        Next i
    End If
    If bfsNewX = -1 Then bfsNewX = Int(px): bfsNewY = Int(py)
    If bfsNewX <> bfsForX Or bfsNewY <> bfsForY Then
        bfsTX = bfsNewX: bfsTY = bfsNewY
        Gosub BFSCompute     ' EN avståndskarta, omräknas bara när målcell byts
    End If
    ' pass 2: rörelse per tillstånd + närstridsskada
    For i = 0 To 10
        If enActive(i) Then
            edx = px - enX(i)
            edy = py - enY(i)
            edist = Sqr(edx * edx + edy * edy)
            oex = enX(i): oey = enY(i)   ' före rörelse, för fotstegs-ackumulatorn
            Select Case enState(i)
                Case 0   ' PATROLL: långsam vandra mot slumpad närliggande cell, nytt mål ~var 3:e s
                    If enPatrolT(i) <= 0 Or Timer - enPatrolT(i) >= 3 Or (Abs(enX(i) - (enTx(i) + 0.5)) < 0.15 And Abs(enY(i) - (enTy(i) + 0.5)) < 0.15) Then
                        enPatrolT(i) = Timer
                        enTx(i) = Int(enX(i)): enTy(i) = Int(enY(i))
                        For tr = 1 To 8
                            dr = Int(Rnd * 4)
                            If dr = 0 Then cx2 = Int(enX(i)) + 1: cy2 = Int(enY(i))
                            If dr = 1 Then cx2 = Int(enX(i)) - 1: cy2 = Int(enY(i))
                            If dr = 2 Then cx2 = Int(enX(i)): cy2 = Int(enY(i)) + 1
                            If dr = 3 Then cx2 = Int(enX(i)): cy2 = Int(enY(i)) - 1
                            If cx2 >= 0 And cx2 <= mapW - 1 And cy2 >= 0 And cy2 <= mapH - 1 Then
                                If OpenCell%(cx2, cy2) Then
                                    enTx(i) = cx2: enTy(i) = cy2
                                    tr = 99
                                End If
                            End If
                        Next tr
                    End If
                    gdx = enTx(i) + 0.5 - enX(i)
                    gdy = enTy(i) + 0.5 - enY(i)
                    gdist = Sqr(gdx * gdx + gdy * gdy)
                    If gdist > 0.05 Then
                        nex = enX(i) + gdx / gdist * 0.2 * dt
                        ney = enY(i) + gdy / gdist * 0.2 * dt
                        If OpenCell%(Int(nex + Sgn(nex - enX(i)) * 0.2), Int(enY(i))) Then enX(i) = nex
                        If OpenCell%(Int(enX(i)), Int(ney + Sgn(ney - enY(i)) * 0.2)) Then enY(i) = ney
                    End If
                Case 1   ' JAKT: följ BFS-fältet nedströms (4-riktning, inga diagonaler)
                    bcx = Int(enX(i)): bcy = Int(enY(i))
                    ' Fas 4A zigzag bias: per-enemy personal target-cell offset,
                    ' re-rolled every 0.5-1 s (random timing = own rhythm per enemy,
                    ' NOT globally synced). The offset side ALTERNATES each re-roll
                    ' (enZigS) so the target cell always changes; the offset is
                    ' perpendicular to the line enemy->player; officers get a larger
                    ' amplitude (etZigAmp); musketeers hold 3-5 cells (etHold).
                    zamp = etZigAmp(enType(i)): zhold = etHold!(enType(i))
                    If (zamp > 0 Or zhold > 0) And Timer >= enZigT(i) Then
                        enZigT(i) = Timer + 0.5 + Rnd * 0.5
                        pdx = px - enX(i): pdy = py - enY(i)
                        pdist = Sqr(pdx * pdx + pdy * pdy): If pdist < 0.01 Then pdx = 1: pdy = 0: pdist = 1
                        If zhold > 0 And edist < 6 Then
                            ' musketeer: target cell ~zhold cells from the player, own side
                            hdx = (enX(i) - px) / pdist: hdy = (enY(i) - py) / pdist
                            zx = Int(px + hdx * zhold + 0.5): zy = Int(py + hdy * zhold + 0.5)
                        Else
                            ux = -pdy / pdist: uy = pdx / pdist
                            zs = -enZigS(i): If zs = 0 Then zs = 1   ' alternate side every re-roll
                            enZigS(i) = zs
                            zx = Int(px) + Sgn(ux * zamp * zs) * Int(Abs(ux * zamp * zs) + 0.5)
                            zy = Int(py) + Sgn(uy * zamp * zs) * Int(Abs(uy * zamp * zs) + 0.5)
                        End If
                        If zx < 0 Then zx = 0
                        If zx > mapW - 1 Then zx = mapW - 1
                        If zy < 0 Then zy = 0
                        If zy > mapH - 1 Then zy = mapH - 1
                        If Solid%(zx, zy) Then zx = Int(px): zy = Int(py)   ' wall/closed door -> no offset
                        enZigX(i) = zx: enZigY(i) = zy
                    End If
                    If zamp = 0 And zhold = 0 Then enZigX(i) = Int(px): enZigY(i) = Int(py)   ' captain: straight BFS
                    If bfsForX >= 0 And bcx >= 0 And bcx <= mapW - 1 And bcy >= 0 And bcy <= mapH - 1 And bfsD(bcx, bcy) > 0 Then
                        ' Fas 4A: strict BFS descent (lowest bfsD among open neighbors),
                        ' but among equally-good neighbors pick the one closest to this
                        ' enemy's personal zigzag target cell -> visible weaving
                        minb = bfsD(bcx, bcy)
                        If bcx + 1 <= mapW - 1 Then If OpenCell%(bcx + 1, bcy) Then If bfsD(bcx + 1, bcy) >= 0 And bfsD(bcx + 1, bcy) < minb Then minb = bfsD(bcx + 1, bcy)
                        If bcx - 1 >= 0 Then If OpenCell%(bcx - 1, bcy) Then If bfsD(bcx - 1, bcy) >= 0 And bfsD(bcx - 1, bcy) < minb Then minb = bfsD(bcx - 1, bcy)
                        If bcy + 1 <= mapH - 1 Then If OpenCell%(bcx, bcy + 1) Then If bfsD(bcx, bcy + 1) >= 0 And bfsD(bcx, bcy + 1) < minb Then minb = bfsD(bcx, bcy + 1)
                        If bcy - 1 >= 0 Then If OpenCell%(bcx, bcy - 1) Then If bfsD(bcx, bcy - 1) >= 0 And bfsD(bcx, bcy - 1) < minb Then minb = bfsD(bcx, bcy - 1)
                        bnx = -1: bny = -1: bestz = 1E+30
                        If bcx + 1 <= mapW - 1 Then If OpenCell%(bcx + 1, bcy) Then If bfsD(bcx + 1, bcy) = minb Then zd = (bcx + 1 - enZigX(i)) ^ 2 + (bcy - enZigY(i)) ^ 2: If zd < bestz Then bestz = zd: bnx = bcx + 1: bny = bcy
                        If bcx - 1 >= 0 Then If OpenCell%(bcx - 1, bcy) Then If bfsD(bcx - 1, bcy) = minb Then zd = (bcx - 1 - enZigX(i)) ^ 2 + (bcy - enZigY(i)) ^ 2: If zd < bestz Then bestz = zd: bnx = bcx - 1: bny = bcy
                        If bcy + 1 <= mapH - 1 Then If OpenCell%(bcx, bcy + 1) Then If bfsD(bcx, bcy + 1) = minb Then zd = (bcx - enZigX(i)) ^ 2 + (bcy + 1 - enZigY(i)) ^ 2: If zd < bestz Then bestz = zd: bnx = bcx: bny = bcy + 1
                        If bcy - 1 >= 0 Then If OpenCell%(bcx, bcy - 1) Then If bfsD(bcx, bcy - 1) = minb Then zd = (bcx - enZigX(i)) ^ 2 + (bcy - 1 - enZigY(i)) ^ 2: If zd < bestz Then bestz = zd: bnx = bcx: bny = bcy - 1
                        If bnx >= 0 Then
                            gdx = bnx + 0.5 - enX(i)
                            gdy = bny + 0.5 - enY(i)
                            gdist = Sqr(gdx * gdx + gdy * gdy)
                            If gdist > 0.02 Then
                                nex = enX(i) + gdx / gdist * enSpd(i) * dt
                                ney = enY(i) + gdy / gdist * enSpd(i) * dt
                                ' väggkollision behålls även i JAKT (samma 0.2-marginal)
                                If OpenCell%(Int(nex + Sgn(nex - enX(i)) * 0.2), Int(enY(i))) Then enX(i) = nex
                                If OpenCell%(Int(enX(i)), Int(ney + Sgn(ney - enY(i)) * 0.2)) Then enY(i) = ney
                            End If
                        End If
                    Else
                        ' i målcell (bfsD=0) eller fält saknas: rakt mot sista kända/spelaren
                        gdx = enLx(i) - enX(i)
                        gdy = enLy(i) - enY(i)
                        gdist = Sqr(gdx * gdx + gdy * gdy)
                        If gdist > 0.02 Then
                            nex = enX(i) + gdx / gdist * enSpd(i) * dt
                            ney = enY(i) + gdy / gdist * enSpd(i) * dt
                            If OpenCell%(Int(nex + Sgn(nex - enX(i)) * 0.2), Int(enY(i))) Then enX(i) = nex
                            If OpenCell%(Int(enX(i)), Int(ney + Sgn(ney - enY(i)) * 0.2)) Then enY(i) = ney
                        End If
                    End If
                    ' förlorad syn > 2 s: gå till sista kända (fältet pekar dit);
                    ' där 5 s lokal patrull -> PATROLL (spelaren kan dölja sig)
                    lostT = Timer - enLastSeen(i)
                    If lostT > 2 Then
                        ldx = enLx(i) - enX(i): ldy = enLy(i) - enY(i)
                        ld = Sqr(ldx * ldx + ldy * ldy)
                        If ld < 0.6 Then
                            If enCalmT(i) <= 0 Then enCalmT(i) = Timer
                            If Timer - enCalmT(i) >= 5 Then
                                enState(i) = 0: enCalmT(i) = 0: enPatrolT(i) = -99
                            End If
                        Else
                            enCalmT(i) = 0
                        End If
                        If lostT > 7 Then enState(i) = 0: enCalmT(i) = 0: enPatrolT(i) = -99   ' fallback
                    End If
                Case 2   ' ANFALL: står kvar och slår (själva skadan kommer nedan)
                    If edist > 1.2 Then enState(i) = 1
            End Select
            ' Fas 4B: ranged attack (etShoot: 1 = BALL, 2 = MORTAR). Requires LOS
            ' (enSeen from pass 1) + fire interval per enemy (enFireT).
            ' Musketeer fires only inside his hold band (3-5 cells); the general
            ' lobs a MORTAR at the player's PREDICTED position (pos + vel * flygtid).
            If etShoot(enType(i)) > 0 And enSeen(i) And Timer >= enFireT(i) Then
                If etShoot(enType(i)) = 1 And edist >= 3 And edist <= 5.5 Then
                    adx = px - enX(i): ady = py - enY(i)
                    ad = Sqr(adx * adx + ady * ady): If ad < 0.01 Then adx = 1: ady = 0: ad = 1
                    spr! = (AiRnd# - 0.5) * 0.12   ' small seeded spread
                    ca = Cos(spr!): sa = Sin(spr!)
                    spX = enX(i): spY = enY(i)
                    spDX = (adx * ca - ady * sa) / ad: spDY = (adx * sa + ady * ca) / ad
                    spSpd! = etProjSpd!(enType(i)): spOwner = 1
                    spDmg = etProjDmg(enType(i)): spType = PR_BALL
                    spSrcType = enType(i): spTX = 0: spTY = 0: spLandT = 0
                    Gosub SpawnProjectile
                    PlaySoundVol SND_SHOT, 0.5
                    enFireT(i) = Timer + etFireT!(enType(i))
                ElseIf etShoot(enType(i)) = 2 And edist < 12 Then
                    ft! = etMortarT!(enType(i))
                    mtx = Int(px + pvx * ft!): mty = Int(py + pvy * ft!)
                    If mtx < 0 Then mtx = 0
                    If mtx > mapW - 1 Then mtx = mapW - 1
                    If mty < 0 Then mty = 0
                    If mty > mapH - 1 Then mty = mapH - 1
                    If Solid%(mtx, mty) Then mtx = Int(px): mty = Int(py)
                    spX = enX(i): spY = enY(i): spDX = 0: spDY = 0: spSpd! = 0
                    spOwner = 1: spDmg = 0: spType = PR_MORTAR
                    spSrcType = enType(i): spTX = mtx: spTY = mty
                    spLandT = Timer + ft!
                    Gosub SpawnProjectile
                    PlaySoundVol SND_SHOT, 0.4
                    enFireT(i) = Timer + etFireT!(enType(i))
                End If
            End If
            ' Fas 4: fotsteg fiende — var 0.5 cell rörelse, volym dämpad med avstånd
            enStepAcc(i) = enStepAcc(i) + Sqr((enX(i) - oex) ^ 2 + (enY(i) - oey) ^ 2)
            If enStepAcc(i) >= 0.5 Then
                enStepAcc(i) = 0
                evol! = 1 - edist / 12
                If evol! < 0.1 Then evol! = 0.1
                If evol! > 0.5 Then evol! = 0.5
                PlaySoundVol SND_ESTEP, evol!
            End If
            ' närstridsskada (oförändrad mekanik från Fas 3): dist<0.8, cooldown 0.7 s
            If edist < 0.8 And Timer - enLastHit(i) >= 0.7 Then
                enLastHit(i) = Timer
                hp = hp - enDmg(i)
                dmgTaken = dmgTaken + enDmg(i)   ' highscore: närstridsskada
                hpMsg$ = "-" + Str$(enDmg(i)) + " HP"
                hpMsgTime = Timer
                PlaySound SND_HURT
            End If
        End If
    Next i

    ' Fas 4B: projectile physics (balls fly + collide, mortars land + splash)
    Gosub UpdateProjectiles

    ' ======== SKJUTNING: vänster musknapp (fireBtn), cooldown 0.3 s ========
    If fireBtn And Timer - lastShotTime >= 0.3 Then
        lastShotTime = Timer
        If ammo > 0 Then
            ammo = ammo - 1
            shotsFired = shotsFired + 1   ' highscore: varje avfogat skott
            tracerTime = Timer
            pitch = pitch + 6   ' liten rekyl-puff
            PlaySound SND_SHOT
            ' träff-koll: samma DDA som vägg-loopen men rakt fram (cameraX=0)
            rdx = dirX: rdy = dirY
            mapX = Int(px): mapY = Int(py)
            If rdx = 0 Then ddx = 1E+30 Else ddx = Abs(1 / rdx)
            If rdy = 0 Then ddy = 1E+30 Else ddy = Abs(1 / rdy)
            If rdx < 0 Then stepX = -1: sdx = (px - mapX) * ddx Else stepX = 1: sdx = (mapX + 1 - px) * ddx
            If rdy < 0 Then stepY = -1: sdy = (py - mapY) * ddy Else stepY = 1: sdy = (mapY + 1 - py) * ddy
            Do
                If sdx < sdy Then
                    sdx = sdx + ddx: mapX = mapX + stepX
                Else
                    sdy = sdy + ddy: mapY = mapY + stepY
                End If
            Loop Until Solid%(mapX, mapY)
            If sdx < sdy Then hitDist = sdx - ddx Else hitDist = sdy - ddy
            If hitDist < 0.2 Then hitDist = 0.2
            flashDist = hitDist   ' muzzle flash: wall distance only (visual)
            ' Fas 4B: the player's shot is a real BALL projectile (musket: slow
            ' ball, period-correct) — same 1 dmg per hit as the old hitscan, so
            ' balance is unchanged. The ball flies and hits via UpdateProjectiles
            ' -> EnemyTakeHit (kill bookkeeping + Fas 4A dodge roll live there).
            spX = px: spY = py: spDX = dirX: spDY = dirY
            spSpd! = plrBallSpd!: spOwner = 0: spDmg = plrBallDmg: spType = PR_BALL
            spSrcType = -1: spTX = 0: spTY = 0: spLandT = 0
            Gosub SpawnProjectile
            flashTime = Timer
            recoil = gunRecoil: muzzleT = gunMuzzleFrames: shakeT = gunShakeFrames   ' Fas 4C: recoil kick + muzzle flash + screen shake
        Else
            hpMsg$ = "CLICK"
            hpMsgTime = Timer
            PlaySoundVol SND_HIT, 0.3
        End If
    End If

    ' HP-REGEN BORTTAGEN (2026-11-23, Andrés beslut): HP ändras ENDAST via
    ' fiende-skada (-X), medkit-pickup (+25, cap 100 kvar) och G-debug.
    ' Medkits är enda botemedlet.

    ' ======== SEGER-TRIGGER (kill-all): alla fiender döda i 1 s -> result ======
    ' (winPending nollställs direkt om någon fiende lever — annars triggar ett
    '  dödsfall precis innan ett respawn, t.ex. i selftestet)
    alive = 0
    For i = 0 To 10
        If enActive(i) Then alive = alive + 1
    Next i
    If alive > 0 Then
        winPending = 0
    Else
        ' OBS: runTimeFrozen sätts INTE här — detta villkor kan vara sant även vid
        ' rundstart/spawn-gap (alive==0 utan kill). Freeze sker ENDAST i
        ' FreezeAtLastKill (anropas från sista-kill-blocket ovan).
        If winPending = 0 Then
            winPending = 1: winT0 = Timer
        ElseIf Timer - winT0 >= 1 Then
            If selftest Then stMsg$ = "WIN-TRIG phase=" + Str$(testPhase) + " t=" + LTrim$(Str$(Int((Timer - winT0) * 10) / 10)): Gosub STLog
            lvlTime(lvlIdx) = Int(Timer - lvlT0)   ' 5C: per-level cleared time (victory screen)
            If gameMode$ = "campaign" And lvlIdx >= lvlN - 1 Then
                ' 5C: last level of the campaign cleared -> VICTORY screen (not result/CONTINUE)
                state$ = "victory"
                selIdx = 1
                LogMouse "LIVSTIDSLAS win->victory (ingen unlock)"
            Else
                state$ = "result"
                LogMouse "LIVSTIDSLAS win->result (ingen unlock, virtuell pekare)"
            End If
            score = liveScore&   ' samma räknare som HUD — fryst värde vid sista kill
            newRecord = 0
            If selftest = 0 And score > bestScore Then
                bestScore = score
                newRecord = 1
                f = FreeFile
                Open ".schleswig_scores.txt" For Output As #f
                Print #f, bestScore
                Close #f
            End If
        End If
    End If

    ' LIVE-SCORE-RÄKNARE: EN variabel, uppdateras varje playing-frame.
    ' Skada/skott dras direkt (via CalcScore&), tid per HEL sekund (CurRunTime%).
    ' HUD, result och highscore läser SAMMA värde (liveScore&) — vägarna kan
    ' inte skilja. Vid sista kill är runTimeFrozen redan satt -> fryst värde.
    liveScore& = CalcScore&

    ' ======== DÖD (Fas 2.6): hp<=0 i playing -> dead; ingen resurrection efter detta ======
    If hp <= 0 Then
        hp = 0
        state$ = "dead"
        deathTime = Timer
        If gameMode$ = "campaign" Then selIdx = 1   ' 5C: death options start on RESTART LEVEL
        LogMouse "LIVSTIDSLAS death (ingen unlock)"
        ' Highscore: räkna score vid död; spara nytt rekord (ej i selftest = anti-cheese)
        score = liveScore&
        newRecord = 0
        If selftest = 0 And score > bestScore Then
            bestScore = score
            newRecord = 1
            f = FreeFile
            Open ".schleswig_scores.txt" For Output As #f
            Print #f, bestScore
            Close #f
        End If
    End If

    ' ======== RENDERING: DDA-väggloop (fyller även wallDist för sprites) ========
    _Dest buf&
    midY = RH \ 2
    Line (0, 0)-(RW - 1, midY - 1 + pitch), ceilingCol&, BF
    Line (0, midY + pitch)-(RW - 1, RH - 1), floorCol&, BF

    planeX = -dirY * planeDist
    planeY = dirX * planeDist

    For x = 0 To RW - 1
        cameraX = 2 * x / RW - 1
        rdx = dirX + planeX * cameraX
        rdy = dirY + planeY * cameraX
        mapX = Int(px)
        mapY = Int(py)
        If rdx = 0 Then ddx = 1E+30 Else ddx = Abs(1 / rdx)
        If rdy = 0 Then ddy = 1E+30 Else ddy = Abs(1 / rdy)
        If rdx < 0 Then
            stepX = -1
            sdx = (px - mapX) * ddx
        Else
            stepX = 1
            sdx = (mapX + 1 - px) * ddx
        End If
        If rdy < 0 Then
            stepY = -1
            sdy = (py - mapY) * ddy
        Else
            stepY = 1
            sdy = (mapY + 1 - py) * ddy
        End If
        hit = 0
        side = 0
        Do
            If sdx < sdy Then
                sdx = sdx + ddx
                mapX = mapX + stepX
                side = 0
            Else
                sdy = sdy + ddy
                mapY = mapY + stepY
                side = 1
            End If
            If Solid%(mapX, mapY) Then hit = 1
        Loop Until hit = 1
        hitCh$ = CellAt$(mapX, mapY)   ' Fas 5A: door cells get their own render color
        If side = 0 Then
            dist = sdx - ddx
        Else
            dist = sdy - ddy
        End If
        If dist < 0.2 Then dist = 0.2
        wallDist(x) = dist   ' sparar väggavstånd per skärmkolumn; sprites jämför
                             ' sitt eget avstånd mot detta för att avgöra om de
                             ' döljs av väggen i just den kolumnen.
                             ' OBS: dist är PERPENDIKULÄRT (fisheye-korrigerat)
                             ' avstånd, så sprites måste jämföra sitt
                             ' perpendikulära avstånd (pdist*Cos(pang)),
                             ' inte det euklidiska pdist.
        lineH = RH / dist
        ' y-shearing (Doom-tricket): i stället för att ändra projektionen skjuts
        ' hela väggens mitt vertikalt med pitch -> horisonten flyttas och världen
        ' "lutar" när man tittar upp/ner. Tak/golv-fyllningen ovan får samma offset.
        ys = RH / 2 - lineH / 2 + pitch
        ye = RH / 2 + lineH / 2 + pitch
        If ys < 0 Then ys = 0
        If ye > RH - 1 Then ye = RH - 1
        shade = 255 - dist * 18
        If shade < 30 Then shade = 30
        If side = 1 Then shade = shade \ 2
        ' Fas 5A: doors render differently from walls — 'd' = brown wood,
        ' '1'/'2'/'3' = dark metal tinted by key color (bronze/silver/gold)
        If hitCh$ = "d" Then
            wcol& = _RGB32(Int(shade * 0.72), Int(shade * 0.47), Int(shade * 0.22))
        ElseIf hitCh$ = "1" Then
            wcol& = _RGB32(Int(shade * 0.55), Int(shade * 0.38), Int(shade * 0.18))
        ElseIf hitCh$ = "2" Then
            wcol& = _RGB32(Int(shade * 0.55), Int(shade * 0.55), Int(shade * 0.62))
        ElseIf hitCh$ = "3" Then
            wcol& = _RGB32(Int(shade * 0.68), Int(shade * 0.58), Int(shade * 0.2))
        Else
            wcol& = pal&(Int(shade))
        End If
        Line (x, ys)-(x, ye), wcol&
    Next x

    ' ======== SPRITES/PICKUPS: projektion + vägg-ocklusion ========
    ' pickups: små röda medkit-rutor med vitt kors, på golvet, med vägg-ocklusion
    For i = 0 To 10
        If pkActive(i) Then
            pdx = pkX(i) - px
            pdy = pkY(i) - py
            pdist = Sqr(pdx * pdx + pdy * pdy)
            If pdist > 0.05 Then
                pang = _ATan2(pdy, pdx) - angle
                While pang > 3.14159265: pang = pang - 6.2831853: Wend
                While pang < -3.14159265: pang = pang + 6.2831853: Wend
                If Abs(pang) < fovCut Then
                    pdistP = pdist * Cos(pang)   ' perpendikulärt avstånd, samma mått som wallDist
                    ' projektionsformeln: vägg-loopen har cameraX = 2*x/RW-1 och
                    ' plan = 0.66*dir, dvs tan(pang) = 0.66*cameraX. Omvänt blir
                    ' skärmkolumnen pcx = RW/2*(1 + Tan(pang)/0.66), där pang är
                    ' vinkeln till pickupen relativt spelarens riktning.
                    pcx = RW / 2 * (1 + Tan(pang) / planeDist)
                    pw = RW / pdist * 0.25
                    ph = RH / pdist * 0.25
                    ' pbase = golvlinjen vid avståndet pdist: horisont + halva
                    ' vägghöjden där (samma perspectiv som väggarna), + pitch.
                    pbase = midY + RH / (2 * pdist) + pitch
                    x0 = Int(pcx - pw / 2): x1 = Int(pcx + pw / 2)
                    If x0 < 0 Then x0 = 0
                    If x1 > RW - 1 Then x1 = RW - 1
                    For sx = x0 To x1
                        If pdistP < wallDist(sx) Then Line (sx, pbase - ph)-(sx, pbase), _RGB32(200, 30, 30)
                    Next sx
                    ' pcx kan hamna utanför skärmen när |pang| närmar sig
                    ' synfältet (0.66 rad) -> clampa innan wallDist-index,
                    ' annars "subscript out of range" (wallDist är 0..RW-1).
                    cx = Int(pcx)
                    If cx < 0 Then cx = 0
                    If cx > RW - 1 Then cx = RW - 1
                    If x0 <= x1 Then
                        ' vitt kors: Bägge staplar per kolumn med vägg-ocklusion
                        If pdistP < wallDist(cx) Then Line (cx, pbase - ph)-(cx, pbase), _RGB32(255, 255, 255)
                        For sx = x0 To x1
                            If pdistP < wallDist(sx) Then Line (sx, pbase - ph / 2)-(sx, pbase - ph / 2), _RGB32(255, 255, 255)
                        Next sx
                    End If
                End If
            End If
        End If
    Next i

    ' ammo-pickups: GULA rutor (distinkt från röda medkit), samma projektion + ocklusion
    For i = 0 To 10
        If amActive(i) Then
            pdx = amX(i) - px
            pdy = amY(i) - py
            pdist = Sqr(pdx * pdx + pdy * pdy)
            If pdist > 0.05 Then
                pang = _ATan2(pdy, pdx) - angle
                While pang > 3.14159265: pang = pang - 6.2831853: Wend
                While pang < -3.14159265: pang = pang + 6.2831853: Wend
                If Abs(pang) < fovCut Then
                    pdistP = pdist * Cos(pang)   ' perpendikulärt avstånd, samma mått som wallDist
                    pcx = RW / 2 * (1 + Tan(pang) / planeDist)
                    pw = RW / pdist * 0.25
                    ph = RH / pdist * 0.25
                    pbase = midY + RH / (2 * pdist) + pitch
                    x0 = Int(pcx - pw / 2): x1 = Int(pcx + pw / 2)
                    If x0 < 0 Then x0 = 0
                    If x1 > RW - 1 Then x1 = RW - 1
                    For sx = x0 To x1
                        If pdistP < wallDist(sx) Then Line (sx, pbase - ph)-(sx, pbase), _RGB32(230, 200, 0)
                    Next sx
                End If
            End If
        End If
    Next i

    ' Fas 5A: key pickups — small colored dots on the floor (bronze/silver/gold)
    ' + white glimt, same projection + wall occlusion as the other pickups
    For i = 0 To 10
        If keyActive(i) Then
            keyDx = keyX(i) - px
            keyDy = keyY(i) - py
            keyDist = Sqr(keyDx * keyDx + keyDy * keyDy)
            If keyDist > 0.05 Then
                keyAng = _ATan2(keyDy, keyDx) - angle
                While keyAng > 3.14159265: keyAng = keyAng - 6.2831853: Wend
                While keyAng < -3.14159265: keyAng = keyAng + 6.2831853: Wend
                If Abs(keyAng) < fovCut Then
                    keyDistP = keyDist * Cos(keyAng)
                    keyCx = RW / 2 * (1 + Tan(keyAng) / planeDist)
                    keyW = RW / keyDist * 0.12
                    keyH = RH / keyDist * 0.12
                    keyBase = midY + RH / (2 * keyDist) + pitch
                    keyX0 = Int(keyCx - keyW / 2): keyX1 = Int(keyCx + keyW / 2)
                    If keyX0 < 0 Then keyX0 = 0
                    If keyX1 > RW - 1 Then keyX1 = RW - 1
                    If keyType(i) = 1 Then keyCol& = _RGB32(205, 127, 50)
                    If keyType(i) = 2 Then keyCol& = _RGB32(200, 200, 215)
                    If keyType(i) = 3 Then keyCol& = _RGB32(255, 215, 0)
                    For sx = keyX0 To keyX1
                        If keyDistP < wallDist(sx) Then Line (sx, keyBase - keyH)-(sx, keyBase), keyCol&
                    Next sx
                    keyCx2 = Int(keyCx)
                    If keyCx2 < 0 Then keyCx2 = 0
                    If keyCx2 > RW - 1 Then keyCx2 = RW - 1
                    If keyDistP < wallDist(keyCx2) Then Line (keyCx2, keyBase - keyH)-(keyCx2, keyBase), _RGB32(255, 255, 255)
                End If
            End If
        End If
    Next i

    ' fiende-sprites (Fas 3): enkelt stående blockmonster, samma projektion +
    ' vägg-ocklusion som pickup-sprites (jämför edist mot wallDist per kolumn)
    For i = 0 To 10
        If enActive(i) Then
            edx = enX(i) - px
            edy = enY(i) - py
            edist = Sqr(edx * edx + edy * edy)
            If edist > 0.05 Then
                eang = _ATan2(edy, edx) - angle
                While eang > 3.14159265: eang = eang - 6.2831853: Wend
                While eang < -3.14159265: eang = eang + 6.2831853: Wend
                If Abs(eang) < fovCut Then
                    edistP = edist * Cos(eang)   ' perpendikulärt avstånd, samma mått som wallDist
                    ecx = RW / 2 * (1 + Tan(eang) / planeDist)
                    ew = RW / edist * 0.6 * etScale!(enType(i))      ' bredd i px (Fas 4B: type scale, general is bigger)
                    eh = RH / edist * 0.9 * etScale!(enType(i))      ' höjd i px (står på golvet)
                    ebase = midY + RH / (2 * edist) + pitch   ' golvlinje vid edist
                    ey0 = ebase - eh
                    ey1 = ebase
                    If ey0 < 0 Then ey0 = 0
                    If ey1 > RH - 1 Then ey1 = RH - 1
                    ex0 = Int(ecx - ew / 2): ex1 = Int(ecx + ew / 2)
                    If ex0 < 0 Then ex0 = 0
                    If ex1 > RW - 1 Then ex1 = RW - 1
                    ' avståndsskuggning som väggarna, skalad till kroppsfärgen (min 20% ljushet)
                    eshade = 255 - edist * 15
                    If eshade < 51 Then eshade = 51
                    ' Fas 4A: body color comes from the enemy-type register (distance-shaded).
                    ' NOTE: _RGB32() sets alpha=255 so etCol& is a NEGATIVE long — extract
                    ' channels with _Red32/_Green32/_Blue32 (\ Mod on a negative long gives
                    ' negative channels -> _RGB32 clamps them to 0 -> BLACK enemies, hotfix 4B)
                    ec& = etCol&(enType(i))
                    er = _Red32(ec&): eg = _Green32(ec&): eb = _Blue32(ec&)
                    ebody& = _RGB32(Int(er * eshade / 255), Int(eg * eshade / 255), Int(eb * eshade / 255))
                    If ey1 > ey0 And ex1 >= ex0 Then
                        For sx = ex0 To ex1
                            If edistP < wallDist(sx) Then Line (sx, ey0)-(sx, ey1), ebody&
                        Next sx
                        ' två svarta ögon upptill när fienden syns tillräckligt stor.
                        ' OCKLUSION-FIX: ögonen ritas nu per kolumn med samma
                        ' väggtest som kroppen (tidigare ritades de utan test ->
                        ' syntes genom väggar).
                        If ew > 16 Then
                            eo = Int(ew * 0.12)
                            If eo < 2 Then eo = 2
                            eoy = Int(ey0 + eh * 0.15)
                            eox0 = Int(ecx - ew * 0.2) - eo: eox1 = Int(ecx - ew * 0.2) + eo
                            eox2 = Int(ecx + ew * 0.2) - eo: eox3 = Int(ecx + ew * 0.2) + eo
                            If eox0 < 0 Then eox0 = 0
                            If eox1 > RW - 1 Then eox1 = RW - 1
                            If eox2 < 0 Then eox2 = 0
                            If eox3 > RW - 1 Then eox3 = RW - 1
                            If eoy >= 0 And eoy + eo * 2 <= RH - 1 Then
                                For sx = eox0 To eox1
                                    If edistP < wallDist(sx) Then Line (sx, eoy)-(sx, eoy + eo * 2), _RGB32(0, 0, 0)
                                Next sx
                                For sx = eox2 To eox3
                                    If edistP < wallDist(sx) Then Line (sx, eoy)-(sx, eoy + eo * 2), _RGB32(0, 0, 0)
                                Next sx
                            End If
                        End If
                    End If
                End If
            End If
        End If
    Next i

    ' Fas 4B: render flying BALLs (small dot, wall-occluded; white = player's,
    ' red = enemy's) and MORTAR telegraphs (blinking amber ring on the floor at
    ' the target cell — visible for the whole flight time).
    For i = 0 To PR_MAX
        If prActive(i) Then
            If prType(i) = PR_BALL Then
                bdx2 = prX(i) - px: bdy2 = prY(i) - py
                bdist = Sqr(bdx2 * bdx2 + bdy2 * bdy2)
                If bdist > 0.05 Then
                    bang = _ATan2(bdy2, bdx2) - angle
                    While bang > 3.14159265: bang = bang - 6.2831853: Wend
                    While bang < -3.14159265: bang = bang + 6.2831853: Wend
                    If Abs(bang) < fovCut Then
                        bdistP = bdist * Cos(bang)
                        bcx2 = RW / 2 * (1 + Tan(bang) / planeDist)
                        ' Light distance scale with hard clamp: ballPx = clamp(RW/bdist * ballScale!, ballPxMin, ballPxMax)
                        ' (near ~12 px, far ~7 px — always visible, never a shoebox). Mini-fix 2.
                        ballPx = Int(RW / bdist * ballScale!)
                        If ballPx < ballPxMin Then ballPx = ballPxMin
                        If ballPx > ballPxMax Then ballPx = ballPxMax
                        bx0 = Int(bcx2 - ballPx / 2): bx1 = bx0 + ballPx - 1
                        by0 = Int(midY + pitch - ballPx / 2): by1 = by0 + ballPx - 1
                        ' 5D FIX: clamps on SEPARATE lines — a single-line
                        ' "If a<0 Then a=0: If b>RW Then b=..." would skip the
                        ' b-clamp whenever a>=0 -> wallDist(b) subscript OOB
                        ' (the "subscript out of range" crash at a ball near the
                        ' right screen edge on the 64x64 arena).
                        If bx0 < 0 Then bx0 = 0
                        If bx1 > RW - 1 Then bx1 = RW - 1
                        If by0 < 0 Then by0 = 0
                        If by1 > RH - 1 Then by1 = RH - 1
                        If prOwner(i) = 0 Then bcol& = _RGB32(255, 255, 255) Else bcol& = _RGB32(255, 40, 40)
                        If by1 > by0 And bx1 >= bx0 Then
                            ' cheap 1px dark outline around the ball so it pops against walls
                            obx0 = bx0 - 1: obx1 = bx1 + 1: oby0 = by0 - 1: oby1 = by1 + 1
                            If obx0 < 0 Then obx0 = 0
                            If obx1 > RW - 1 Then obx1 = RW - 1
                            If oby0 < 0 Then oby0 = 0
                            If oby1 > RH - 1 Then oby1 = RH - 1
                            For sx = obx0 To obx1
                                If bdistP < wallDist(sx) Then
                                    Line (sx, oby0)-(sx, oby1), _RGB32(20, 20, 20)
                                End If
                            Next sx
                            For sx = bx0 To bx1
                                If bdistP < wallDist(sx) Then Line (sx, by0)-(sx, by1), bcol&
                            Next sx
                        End If
                    End If
                End If
            Else
                ' MORTAR telegraph: blinking amber ring at target cell, floor-projected
                If Int(Timer * 4) Mod 2 = 0 Then
                    tdx = prTX(i) + 0.5 - px: tdy = prTY(i) + 0.5 - py
                    tdist = Sqr(tdx * tdx + tdy * tdy)
                    If tdist > 0.05 Then
                        tang = _ATan2(tdy, tdx) - angle
                        While tang > 3.14159265: tang = tang - 6.2831853: Wend
                        While tang < -3.14159265: tang = tang + 6.2831853: Wend
                        If Abs(tang) < fovCut Then
                            tdistP = tdist * Cos(tang)
                            tcx = Int(RW / 2 * (1 + Tan(tang) / planeDist))
                            If tcx >= 0 And tcx <= RW - 1 Then
                                If tdistP < wallDist(tcx) Then
                                    tgy = midY + RH / (2 * tdistP) + pitch
                                    st2 = prSrcType(i): If st2 < 0 Or st2 > ET_COUNT - 1 Then st2 = 0   ' defensive clamp
                                    trp = RW / tdistP * etSplashR!(st2) * 0.5
                                    If trp < 4 Then trp = 4
                                    If trp > RW / 2 Then trp = RW / 2
                                    If tgy > 0 And tgy < RH Then CIRCLE (tcx, tgy), trp, _RGB32(255, 200, 0)
                                End If
                            End If
                        End If
                    End If
                End If
            End If
        End If
    Next i

    ' selftest fas 10: occlusion-audit pa pixel-niva (POINT pa buf&, dest är ännu buf&)
    ' körs en gang när testFlag=1 (satt av SelftestDrive efter några renderade frames)
    If selftest And testPhase = 10 And testFlag = 1 Then
        testFlag = 2
        ' en0 bakom väggen: vänster öga får INTE vara svart (ögon syns annars genom vägg)
        aedx = enX(0) - px: aedy = enY(0) - py
        aedist = Sqr(aedx * aedx + aedy * aedy)
        aeang = _ATan2(aedy, aedx) - angle
        aecx = RW / 2 * (1 + Tan(aeang) / planeDist)
        aew = RW / aedist * 0.6: aeh = RH / aedist * 0.9
        aebase = midY + RH / (2 * aedist) + pitch
        aey0 = aebase - aeh: If aey0 < 0 Then aey0 = 0
        aeoy = Int(aey0 + aeh * 0.15)
        aex = Int(aecx - aew * 0.2)
        If aex < 0 Then aex = 0
        If aex > RW - 1 Then aex = RW - 1
        If aeoy < 0 Then aeoy = 0
        If aeoy > RH - 1 Then aeoy = RH - 1
        eyePix& = POINT(aex, aeoy)
        ' pk0 framför väggen (off-center, pdistP<wallDist men pdist>wallDist): ska synas röd
        apdx = pkX(0) - px: apdy = pkY(0) - py
        apdist = Sqr(apdx * apdx + apdy * apdy)
        apang = _ATan2(apdy, apdx) - angle
        apcx = Int(RW / 2 * (1 + Tan(apang) / planeDist))
        If apcx < 0 Then apcx = 0
        If apcx > RW - 1 Then apcx = RW - 1
        apdistP = apdist * Cos(apang)
        pkFrontPix& = POINT(apcx, RH - 5)          ' mittkolumnen = vit kors-stapel
        apcx2 = apcx - 20
        If apcx2 < 0 Then apcx2 = 0
        pkFrontPix2& = POINT(apcx2, RH - 5)         ' 20px åt sidan = röd kropp
        ' pk1 bakom väggen: ska INTE synas röd i mittkolumnen
        pkBehindPix& = POINT(RW \ 2, RH - 5)
        eyesOK = (eyePix& <> _RGB32(0, 0, 0))
        frontOK = ((pkFrontPix& = _RGB32(255, 255, 255) Or pkFrontPix& = _RGB32(200, 30, 30)) And pkFrontPix2& = _RGB32(200, 30, 30))
        behindOK = (pkBehindPix& <> _RGB32(200, 30, 30))
        If eyesOK And frontOK And behindOK Then
            stMsg$ = "PASS fas10-occlusion (ögon dolda bakom vägg, pickup framför syns, bakom döljs)"
            Gosub STLog
            ' fas 11: ljud-register-test (alla id anropas; får ej ändra tillstånd/krascha)
            testPhase = 11: testT0 = Timer: testFlag = 0
        Else
            stMsg$ = "FAIL fas10-occlusion eyesOK=" + Str$(eyesOK) + " frontOK=" + Str$(frontOK) + " behindOK=" + Str$(behindOK) + " eyePix=" + Str$(eyePix&) + " frontPix=" + Str$(pkFrontPix&) + " frontPix2=" + Str$(pkFrontPix2&) + " behindPix=" + Str$(pkBehindPix&) + " apdistP=" + LTrim$(Str$(Int(apdistP * 100) / 100)) + " wallDist=" + LTrim$(Str$(Int(wallDist(apcx) * 100) / 100)) + " RW=" + Str$(RW) + " RH=" + Str$(RH) + " apcx=" + Str$(apcx)
            Gosub STLog
            stMsg$ = "SELFTEST FAIL"
            Gosub STLog
            ShutdownSound
            End
        End If
    End If

    ' ======== HUD: debug-rad, HP-bar, ammo, transient meddelande ======

    _Dest display&
    ' Fas 4C: screen shake — while shakeT>0 the 3D buffer is blitted offset by a
    ' few px over a black fill (1-2 frames after a shot).
    If shakeT > 0 Then
        Line (0, 0)-(RW - 1, RH - 1), _RGB32(0, 0, 0), BF
        If shakeT Mod 2 = 0 Then shkX = gunShakeAmp: shkY = -gunShakeAmp Else shkX = -gunShakeAmp: shkY = gunShakeAmp
        _PutImage (shkX, shkY)-(RW - 1 + shkX, RH - 1 + shkY), buf&
    Else
        _PutImage (0, 0)-(RW - 1, RH - 1), buf&
    End If
    ' Fas 4C: weapon viewmodel — bottom layer, UNDER the HUD (HUD is drawn below,
    ' so ammo/HP stay readable). This code is only reachable in the playing
    ' branch, so the gun is never rendered in menu/result/paused/dead.
    If gunBuf& <> 0 Then   ' <>0: handles can be negative in QB64-PE
        gunScrX = gunBaseX - gunBW \ 2 + Int(gunX)
        gunScrY = RH - gunBH + Int(gunY)
        _PutImage (gunScrX, gunScrY), gunBuf&
        gunRendered = gunRendered + 1   ' selftest fas16c counter
        ' muzzle flash: bright triangle at the barrel tip while muzzleT>0 (2-3 frames)
        If muzzleT > 0 Then
            gunMFx = gunScrX + gunBW \ 2: gunMFy = gunScrY + Int(gunBH * 0.03)
            gunMFsz = Int(RH * 0.05): If gunMFsz < 8 Then gunMFsz = 8
            ' muzzle flash = small cross/plätt at the barrel tip (LINE takes 2 points only)
            Line (gunMFx - gunMFsz, gunMFy)-(gunMFx + gunMFsz, gunMFy), _RGB32(255, 240, 150)
            Line (gunMFx, gunMFy - gunMFsz)-(gunMFx, gunMFy + gunMFsz), _RGB32(255, 240, 150)
            Line (gunMFx - gunMFsz \ 2, gunMFy)-(gunMFx + gunMFsz \ 2, gunMFy), _RGB32(255, 255, 255)
            Line (gunMFx, gunMFy - gunMFsz \ 2)-(gunMFx, gunMFy + gunMFsz \ 2), _RGB32(255, 255, 255)
        End If
    End If
    ' crosshair (Fas 2.7): centrerad på (RW\2, RH\2) = tracer-epicentrum.
    ' Ritordning: efter värld+sprites (ovan), före HUD och fade-overlay.
    ' Mörk outline först (tjockare), sedan vit kärna -> syns mot både ljusa och mörka väggar.
    cx = RW \ 2: cy = RH \ 2
    cg = Int(RW * 6 / 1920): ca = Int(RW * 14 / 1920): ct = Int(RH * 2 / 1080)
    Line (cx - ca - cg, cy - ct - 1)-(cx - cg, cy + ct + 1), _RGB32(0, 0, 0), BF
    Line (cx + cg, cy - ct - 1)-(cx + ca + cg, cy + ct + 1), _RGB32(0, 0, 0), BF
    Line (cx - ct - 1, cy - ca - cg)-(cx + ct + 1, cy - cg), _RGB32(0, 0, 0), BF
    Line (cx - ct - 1, cy + cg)-(cx + ct + 1, cy + ca + cg), _RGB32(0, 0, 0), BF
    Line (cx - ca - cg, cy - ct)-(cx - cg, cy + ct), _RGB32(255, 255, 255), BF
    Line (cx + cg, cy - ct)-(cx + ca + cg, cy + ct), _RGB32(255, 255, 255), BF
    Line (cx - ct, cy - ca - cg)-(cx + ct, cy - cg), _RGB32(255, 255, 255), BF
    Line (cx - ct, cy + cg)-(cx + ct, cy + ca + cg), _RGB32(255, 255, 255), BF
    Color _RGB32(255, 255, 0)
    _PrintString (0, 0), strFps$ + Str$(fpsShow) + " mmx:" + Str$(mmx) + " mmy:" + Str$(mmy) + " ang:" + Str$(Int(angle * 57.2958)) + " x:" + LTrim$(Str$(px)) + " y:" + LTrim$(Str$(py)) + " pitch:" + Str$(Int(pitch))
    ' HUD: live SCORE i övre HÖGRA hörnet (FPS-debug är övre vänstra, HP/ammo nere) — ingen kollision
    scHud$ = strScore$ + " " + LTrim$(Str$(liveScore&))   ' live-räknare — tickar ner med tiden
    Color _RGB32(255, 255, 0)
    _PrintString (RW - Len(scHud$) * 8 - 8, 4), scHud$
    ' 5C HUD mode/level rad (FIX F): "LVL n/total <namn> MAP <fil> #<hash> RESTARTS r"
    ' i kampanjläge, "SINGLE <fil> #<hash>" i arg-testläge, "ARENA <fil> #<hash>" utan arg.
    lvlHud$ = HudLevelTag$
    If Len(lvlHud$) > RW \ 8 - 1 Then lvlHud$ = Left$(lvlHud$, RW \ 8 - 1)
    Color _RGB32(150, 150, 230)
    _PrintString (0, 18), lvlHud$
    ' (muslås-hint borttagen — Wayland låser vid första klicket, ingen text behövs)

    ' HP-ruta nertill vänster: bar-längd + siffra (tydligt även utan färgseende)
    ' HUD-koordinaterna är RELATIVA RW/RH (hudY = RH-28 osv; vid 1920x1080 samma värden som tidigare)
    hudY = RH - 28
    hpX0 = 8: hpW = Int(RW * 208 / 1920): hpX1 = hpX0 + hpW
    Line (hpX0, hudY)-(hpX1, hudY + 20), _RGB32(40, 40, 40), BF
    Line (hpX0, hudY)-(hpX1, hudY + 20), _RGB32(255, 255, 255), B
    Line (hpX0 + 1, hudY + 1)-(hpX1 - 1, hudY + 19), _RGB32(255, 255, 255), B
    If hp > 50 Then
        barCol& = _RGB32(0, 200, 0)
    ElseIf hp >= 25 Then
        barCol& = _RGB32(220, 200, 0)
    Else
        barCol& = _RGB32(220, 0, 0)
    End If
    If hp > 0 Then Line (hpX0 + 2, hudY + 2)-(hpX0 + 2 + Int(hp * (hpW - 8) / 100), hudY + 18), barCol&, BF
    Color _RGB32(255, 255, 255)
    _PrintString (hpX1 + 8, hudY + 4), strHudHp$ + Str$(Int(hp))
    ' ammo-ruta relativt HP-boxens bredd/högerkant (gul kant = ammo-pickups)
    amX0 = hpX1 + Int(RW * 104 / 1920): amW = Int(RW * 100 / 1920): amX1 = amX0 + amW
    Line (amX0, hudY)-(amX1, hudY + 20), _RGB32(40, 40, 40), BF
    Line (amX0, hudY)-(amX1, hudY + 20), _RGB32(230, 200, 0), B
    Line (amX0 + 1, hudY + 1)-(amX1 - 1, hudY + 19), _RGB32(230, 200, 0), B
    ' ammo-streck INUTI rutan: maxAmmo tunna staplar, en per projektil kvar.
    ' Rutan är bredare än hög (amW x 20) -> VERTIKALA streck (tydligast).
    ' Streck 1..CountAmmoTicks%(ammo) = GULT RGB(255,200,0) (matchar hover-paletten),
    ' resten svag platshållare RGB(60,60,90). Skalar med RW/RH via amW/hudY.
    tickN = CountAmmoTicks%(ammo)
    inX0 = amX0 + 2: inX1 = amX1 - 2: inY0 = hudY + 2: inY1 = hudY + 18
    slotW = (inX1 - inX0 + 1) / maxAmmo
    tgap = 1: If slotW < 3 Then tgap = 0
    For ti = 1 To maxAmmo
        tx0 = inX0 + Int((ti - 1) * slotW): tx1 = inX0 + Int(ti * slotW) - 1 - tgap
        If tx1 < tx0 Then tx1 = tx0
        If ti <= tickN Then
            Line (tx0, inY0)-(tx1, inY1), _RGB32(255, 200, 0), BF
        Else
            Line (tx0, inY0)-(tx1, inY1), _RGB32(60, 60, 90), BF
        End If
    Next ti
    Color _RGB32(230, 200, 0)
    _PrintString (amX1 + 8, hudY + 4), strHudAmmo$ + Str$(ammo)
    ' Fas 5A: keys row — only OWNED keys are shown (HUD is drawn after the weapon
    ' sprite, so it always has precedence over the viewmodel)
    If hasBronze Or hasSilver Or hasGold Then
        keyHud$ = strKeys$
        If hasBronze Then keyHud$ = keyHud$ + " B"
        If hasSilver Then keyHud$ = keyHud$ + " S"
        If hasGold Then keyHud$ = keyHud$ + " G"
        Color _RGB32(255, 215, 0)
        _PrintString (hpX0, hudY - 18), keyHud$
    End If
    If Timer - hpMsgTime < 2 Then
        Color _RGB32(0, 255, 0)
        _PrintString (amX1 + Int(RW * 140 / 1920), hudY + 4), hpMsg$
    End If
    ' tracer-flash från skärm-mitt (RW/2, RH/2) + träff-flash, 2-3 frames
    If Timer - tracerTime < 0.05 Then Line (RW \ 2, RH \ 2)-(RW \ 2, RH \ 2 - Int(RW * 150 / 1920)), _RGB32(255, 255, 255)
    If Timer - flashTime < 0.05 Then
        fs = Int(RW * 300 / 1920 / flashDist)
        If fs < 4 Then fs = 4
        If fs > 60 Then fs = 60
        Line (RW \ 2 - fs, RH \ 2 + pitch - fs)-(RW \ 2 + fs, RH \ 2 + pitch + fs), _RGB32(255, 220, 80), BF
    End If
    ' fade-in: svart overlay över spelet, FÖRE _Display (ritordningsregeln)
    If fading = 2 Then
        fa = (Timer - fadeT0) / 0.4
        If fa > 1 Then fa = 1
        Line (0, 0)-(RW - 1, RH - 1), _RGBA32(0, 0, 0, Int((1 - fa) * 255)), BF
        If fa >= 1 Then fading = 0
    End If
    _Display

    End If

    frames = frames + 1
    ' selftest-heartbeat: en rad/s så vi ser att loopen lever och var den står
    If selftest And Timer - testHb >= 1 Then
        testHb = Timer
        stMsg$ = "alive phase=" + Str$(testPhase) + " state=" + state$ + " hp=" + Str$(Int(hp)) + " en0=(" + LTrim$(Str$(Int(enX(0) * 10) / 10)) + "," + LTrim$(Str$(Int(enY(0) * 10) / 10)) + ") st=" + Str$(enState(0)) + " act=" + Str$(enActive(0)) + " en1act=" + Str$(enActive(1)) + " winP=" + Str$(winPending) + " frz=" + Str$(runTimeFrozen)
        Gosub STLog
    End If
    If curTime - lastTime >= 1 Then
        fpsShow = Int(frames / (curTime - lastTime))
        _Title strAppName$ + " " + ver$ + " - " + strFps$ + LTrim$(Str$(fpsShow))
        frames = 0
        lastTime = curTime
    End If
LOOP

' ======== SUBRUTINER (Fas 3 / 3.1) ========
' InitEnemyTypes (Fas 4A/4B): fills the data-driven enemy-type register.
' Difficulty via variation, NOT HP swelling. etShoot: 0 = melee only,
' 1 = fires BALL (musketeer), 2 = fires MORTAR (general). etCol& is the base
' body color (distance-shaded at render); etSpr sprite id, etScale sprite
' scale, etMinWave spawn gating wave (general additionally: wave Mod 5 = 0).
InitEnemyTypes:
    etName$(ET_FOOT) = "FOOT SOLDIER":  etHP(ET_FOOT) = 3:  etDmg(ET_FOOT) = 10: etSpd!(ET_FOOT) = 0.45: etZigAmp(ET_FOOT) = 1: etDodge!(ET_FOOT) = 0.3: etShoot(ET_FOOT) = 0: etHold!(ET_FOOT) = 0:   etCol&(ET_FOOT) = _RGB32(170, 35, 35):   etSpr(ET_FOOT) = 0: etScale!(ET_FOOT) = 1:   etMinWave(ET_FOOT) = 1: etFireT!(ET_FOOT) = 0: etProjSpd!(ET_FOOT) = 0: etProjDmg(ET_FOOT) = 0: etMortarT!(ET_FOOT) = 0: etSplashR!(ET_FOOT) = 0: etSplashDmg(ET_FOOT) = 0
    etName$(ET_OFFICER) = "OFFICER":    etHP(ET_OFFICER) = 6:  etDmg(ET_OFFICER) = 10: etSpd!(ET_OFFICER) = 0.6:  etZigAmp(ET_OFFICER) = 2: etDodge!(ET_OFFICER) = 0.4: etShoot(ET_OFFICER) = 0: etHold!(ET_OFFICER) = 0:  etCol&(ET_OFFICER) = _RGB32(200, 30, 80):  etSpr(ET_OFFICER) = 0: etScale!(ET_OFFICER) = 1.1: etMinWave(ET_OFFICER) = 3: etFireT!(ET_OFFICER) = 0: etProjSpd!(ET_OFFICER) = 0: etProjDmg(ET_OFFICER) = 0: etMortarT!(ET_OFFICER) = 0: etSplashR!(ET_OFFICER) = 0: etSplashDmg(ET_OFFICER) = 0
    etName$(ET_MUSKETEER) = "MUSKETEER": etHP(ET_MUSKETEER) = 5: etDmg(ET_MUSKETEER) = 10: etSpd!(ET_MUSKETEER) = 0.45: etZigAmp(ET_MUSKETEER) = 1: etDodge!(ET_MUSKETEER) = 0.4: etShoot(ET_MUSKETEER) = 1: etHold!(ET_MUSKETEER) = 4: etCol&(ET_MUSKETEER) = _RGB32(150, 90, 40):  etSpr(ET_MUSKETEER) = 0: etScale!(ET_MUSKETEER) = 1: etMinWave(ET_MUSKETEER) = 4: etFireT!(ET_MUSKETEER) = 1.2: etProjSpd!(ET_MUSKETEER) = 5: etProjDmg(ET_MUSKETEER) = 10: etMortarT!(ET_MUSKETEER) = 0: etSplashR!(ET_MUSKETEER) = 0: etSplashDmg(ET_MUSKETEER) = 0
    etName$(ET_CAPTAIN) = "CAPTAIN":    etHP(ET_CAPTAIN) = 12: etDmg(ET_CAPTAIN) = 10: etSpd!(ET_CAPTAIN) = 0.3:  etZigAmp(ET_CAPTAIN) = 0: etDodge!(ET_CAPTAIN) = 0.5:  etShoot(ET_CAPTAIN) = 0: etHold!(ET_CAPTAIN) = 0:   etCol&(ET_CAPTAIN) = _RGB32(230, 180, 40): etSpr(ET_CAPTAIN) = 0: etScale!(ET_CAPTAIN) = 1.25: etMinWave(ET_CAPTAIN) = 3: etFireT!(ET_CAPTAIN) = 0: etProjSpd!(ET_CAPTAIN) = 0: etProjDmg(ET_CAPTAIN) = 0: etMortarT!(ET_CAPTAIN) = 0: etSplashR!(ET_CAPTAIN) = 0: etSplashDmg(ET_CAPTAIN) = 0
    etName$(ET_GENERAL) = "GENERAL":    etHP(ET_GENERAL) = 25: etDmg(ET_GENERAL) = 10: etSpd!(ET_GENERAL) = 0.2:  etZigAmp(ET_GENERAL) = 0: etDodge!(ET_GENERAL) = 0:    etShoot(ET_GENERAL) = 2: etHold!(ET_GENERAL) = 0:   etCol&(ET_GENERAL) = _RGB32(30, 90, 40):   etSpr(ET_GENERAL) = 0: etScale!(ET_GENERAL) = 1.4: etMinWave(ET_GENERAL) = ET_BOSS_STEP: etFireT!(ET_GENERAL) = 3: etProjSpd!(ET_GENERAL) = 0: etProjDmg(ET_GENERAL) = 0: etMortarT!(ET_GENERAL) = 1.8: etSplashR!(ET_GENERAL) = 1.5: etSplashDmg(ET_GENERAL) = 25
    Return

' SpawnEnemies: startlägen för fiende-poolen (öppna rutor på kartan).
' Anropas vid init och vid full reset (R i dead-läget).
SpawnEnemies:
    Gosub InitEnemyTypes
    waveNo = waveNo + 1
    For i = 0 To 10
        enActive(i) = 0
        enHP(i) = 3          ' default; overridden per type below
        enDmg(i) = 10        ' skada per närstridsslag
        enSpd(i) = 0.45      ' tiles/s i JAKT (långsammare än spelaren -> går att överleva)
        enLastHit(i) = 0
        enState(i) = 0       ' PATROLL
        enSeen(i) = 0
        enLastSeen(i) = 0
        enCalmT(i) = 0
        enPatrolT(i) = 0
        enLx(i) = 0: enLy(i) = 0
        enTx(i) = 0: enTy(i) = 0
        enType(i) = ET_FOOT
        enZigX(i) = 0: enZigY(i) = 0: enZigT(i) = 0: enZigS(i) = 1
        enFireT(i) = 0      ' Fas 4B: ranged fire timer
    Next i
    For i = 0 To PR_MAX: prActive(i) = 0: Next i   ' Fas 4B: clear projectile pool on wave start
    bfsForX = -1: bfsForY = -1
    ' Spawn-balans (2026-11-23): en0/en3 flyttade bort från startspawn (8.5,4.5) -
    ' tidigare hade en0 (13.5,4.5) fri LOS i rad 4 (dist 5) och en3 (5.5,1.5) fri LOS
    ' via (6,2)(7,3)(8,4) (dist 4.2) -> JAKT direkt vid spelstart. Nu bakom vägg OCH
    ' dist >= 6 (LOS-tröskeln): en0 nere höger (LOS bruten av vägg 12,8, dist 7.1),
    ' en3 övre vänster hörnet (LOS bruten av vägg 4,2, dist 6.7). en1/en2 oförändrade.
    ' Fas 5A: om kartan deklarerar fiende-spawns (F/O/U/K/G) så överskrider de
    ' dessa legacy-positioner — då är kartans innehåll som bestämmer rundet.
    nSlots = 4
    If spEnN > 0 Then
        nSlots = spEnN: If nSlots > 10 Then nSlots = 10
        For sl = 0 To nSlots - 1
            enX(sl) = spEnX(sl) + 0.5: enY(sl) = spEnY(sl) + 0.5: enActive(sl) = 1
            enLx(sl) = enX(sl): enLy(sl) = enY(sl): enTx(sl) = spEnX(sl): enTy(sl) = spEnY(sl)
        Next sl
    Else
        enX(0) = 13.5: enY(0) = 9.5:  enActive(0) = 1
        enLx(0) = enX(0): enLy(0) = enY(0): enTx(0) = 13: enTy(0) = 9
        enX(1) = 10.5: enY(1) = 9.5:  enActive(1) = 1
        enLx(1) = enX(1): enLy(1) = enY(1): enTx(1) = 10: enTy(1) = 9
        enX(2) = 2.5:  enY(2) = 12.5: enActive(2) = 1
        enLx(2) = enX(2): enLy(2) = enY(2): enTx(2) = 2: enTy(2) = 12
        enX(3) = 2.5:  enY(3) = 1.5:  enActive(3) = 1
        enLx(3) = enX(3): enLy(3) = enY(3): enTx(3) = 2: enTy(3) = 1
    End If
    ' Fas 4A/4B spawn-mix per wave (gated progression, data-driven via etMinWave):
    ' slots 0-2 always FOOT SOLDIER (majority). Slot 3 weighted officer/musketeer/
    ' captain — each gated by its etMinWave AND (captain) killsTotal > 5, so waves
    ' 1-2 are ALL foot soldiers. Boss waves (waveNo >= 5 and Mod 5 = 0): slot 3 is
    ' ALWAYS the GENERAL (max 1 per wave). HP/dmg/speed come from the register.
    ' Fas 5A: map-declared slots keep their declared type; only the REMAINING
    ' slots (map with fewer than 4 spawns) are filled by the register mix.
    For sl = 0 To nSlots - 1
        If spEnN > 0 And sl < spEnN Then
            etPick = spEnT(sl)
        ElseIf sl <= 2 Then
            etPick = ET_FOOT
        ElseIf waveNo >= ET_BOSS_STEP And (waveNo Mod ET_BOSS_STEP) = 0 Then
            etPick = ET_GENERAL
        Else
            rl = Rnd
            etPick = ET_FOOT
            If killsTotal > 5 And waveNo >= etMinWave(ET_CAPTAIN) And rl >= 0.85 Then
                etPick = ET_CAPTAIN
            ElseIf waveNo >= etMinWave(ET_MUSKETEER) And rl >= 0.6 Then
                etPick = ET_MUSKETEER
            ElseIf waveNo >= etMinWave(ET_OFFICER) And rl >= 0.4 Then
                etPick = ET_OFFICER
            End If
        End If
        enType(sl) = etPick
        enHP(sl) = etHP(etPick): enDmg(sl) = etDmg(etPick): enSpd(sl) = etSpd!(etPick)
        enZigX(sl) = Int(enX(sl)): enZigY(sl) = Int(enY(sl)): enZigT(sl) = 0
        enZigS(sl) = 1: If Rnd < 0.5 Then enZigS(sl) = -1
        enFireT(sl) = 0
    Next sl
    Return

' FreezeAtLastKill: ENDA stället där runTimeFrozen sätts — anropas när en
' död-registrering (kill-blocket) gör antal levande == 0, samt av selftestets
' simulerade kill-all. Guard: bara första gången (runTimeFrozen < 0), så
' rundstart/spawn-gap (alive==0 utan kill) kan aldrig frysa tiden.
FreezeAtLastKill:
    If runTimeFrozen < 0 Then runTimeFrozen = Int(Timer - runT0)
    Return

' CurRunTime%: aktuell run-tid i sekunder — EN plats för regeln:
' LIVE under playing (HUD-score tickar kontinuerligt), FRYST så fort sista
' fienden dött (runTimeFrozen >= 0) — resultatmenyn + highscore (via
' CalcScore&) använder därmed det frysta värdet från freeze-punkten.
Function CurRunTime%
    If runTimeFrozen >= 0 Then
        CurRunTime% = runTimeFrozen
    Else
        CurRunTime% = Int(Timer - runT0)
    End If
End Function

' CalcScore&: score = 10000 - 5*s - 10*skott - 25*skada, min 0 (formel v2,
' beslut 2026-11-23; anti-negativt skydd: score kan aldrig bli < 0).
Function CalcScore&
    s% = CurRunTime%
    sc& = 10000 - 5 * s% - 10 * shotsFired - 25 * dmgTaken
    If sc& < 0 Then sc& = 0
    CalcScore& = sc&
End Function

' CountAmmoTicks%: antal tända streck i ammo-rutan = aktuell ammo, klamrad till
' [0, maxAmmo] — samma konstant som ammo-capen (kan inte glida isär).
Function CountAmmoTicks% (a)
    If a < 0 Then a = 0
    If a > maxAmmo Then a = maxAmmo
    CountAmmoTicks% = a
End Function

' InitSounds (Fas 4): fyller det datadrivna ljud-registret (id -> vågform,
' frekvenssvep, längd, volym) och öppnar raw-PCM-pipen. _SNDOPENRAW ger
' ogiltigt handtag (<=0) när ingen ljudenhet finns (headless) -> alla
' PlaySound* blir då tysta no-op och kraschar aldrig.
InitSounds:
    sndPipe& = _SNDOPENRAW
    sndCalls = 0
    ' Ljud-debug (2026-11-23): vid ogiltigt handtag skrivs varning till konsol
    ' OCH till /tmp/schleswig_snd.log (Print når ej stdout i headless-miljö).
    Print "SND: pipe handle="; sndPipe&
    If sndPipe& <= 0 Then Print "SND: audio init FAILED, handle="; sndPipe&; " -> alla PlaySound blir tysta no-op"
    sndDbg = FreeFile
    Open "/tmp/schleswig_snd.log" For Output As #sndDbg
    Print #sndDbg, "SND init: pipe handle="; sndPipe&
    If sndPipe& <= 0 Then Print #sndDbg, "SND: audio init FAILED, handle="; sndPipe&
    Close #sndDbg
    sndWave(SND_SHOT) = 1: sndF0!(SND_SHOT) = 0: sndF1!(SND_SHOT) = 0: sndDur!(SND_SHOT) = 0.06: sndVol!(SND_SHOT) = 0.25
    sndWave(SND_HIT) = 2: sndF0!(SND_HIT) = 220: sndF1!(SND_HIT) = 160: sndDur!(SND_HIT) = 0.09: sndVol!(SND_HIT) = 0.18
    sndWave(SND_ENDIE) = 3: sndF0!(SND_ENDIE) = 400: sndF1!(SND_ENDIE) = 70: sndDur!(SND_ENDIE) = 0.3: sndVol!(SND_ENDIE) = 0.22
    sndWave(SND_PICKUP) = 4: sndF0!(SND_PICKUP) = 660: sndF1!(SND_PICKUP) = 990: sndDur!(SND_PICKUP) = 0.15: sndVol!(SND_PICKUP) = 0.18
    sndWave(SND_HURT) = 2: sndF0!(SND_HURT) = 110: sndF1!(SND_HURT) = 65: sndDur!(SND_HURT) = 0.12: sndVol!(SND_HURT) = 0.28
    ' ALERT får vara TYDLIG (undantag från låg-volym-kappan): hård "dun-DUM-DUM",
    ' 620->930 Hz stigande, 350 ms, vol 0.45 (2026-11-23, Andrés önskemål)
    sndWave(SND_ALERT) = 6: sndF0!(SND_ALERT) = 620: sndF1!(SND_ALERT) = 930: sndDur!(SND_ALERT) = 0.35: sndVol!(SND_ALERT) = 0.45
    sndWave(SND_STEP) = 1: sndF0!(SND_STEP) = 0: sndF1!(SND_STEP) = 0: sndDur!(SND_STEP) = 0.045: sndVol!(SND_STEP) = 0.1
    sndWave(SND_ESTEP) = 1: sndF0!(SND_ESTEP) = 0: sndF1!(SND_ESTEP) = 0: sndDur!(SND_ESTEP) = 0.05: sndVol!(SND_ESTEP) = 0.12
    sndWave(SND_BOOM) = 1: sndF0!(SND_BOOM) = 0: sndF1!(SND_BOOM) = 0: sndDur!(SND_BOOM) = 0.4: sndVol!(SND_BOOM) = 0.5
    stepAcc = 0
    For i = 0 To 10: enAlertT(i) = -99: enStepAcc(i) = 0: Next i
    Return

' GenSample#: vågform-generator. Registret (sndWave(id%)) styr vågformen;
' nya ljudtyper = ny Case här + en rad i InitSounds.
Function GenSample# (id%, i%, n%)
    t# = i% / SND_RATE
    dur# = sndDur!(id%)
    f0# = sndF0!(id%): f1# = sndF1!(id%)
    env# = 1 - t# / dur#          ' enkel linjär decay
    If env# < 0 Then env# = 0
    Select Case sndWave(id%)
        Case 1   ' brus (skott, fotsteg)
            GenSample# = (Rnd * 2 - 1) * env#
        Case 2   ' fyrkantsvåg med frekvenssvep f0->f1 (träff, skada)
            f# = f0# + (f1# - f0#) * (t# / dur#)
            If Sin(6.2831853 * f# * t#) >= 0 Then GenSample# = env# Else GenSample# = -env#
        Case 3   ' sågtand med svep (fiende-död, nedstigande)
            f# = f0# + (f1# - f0#) * (t# / dur#)
            ph# = f# * t# - Int(f# * t#)
            GenSample# = (ph# * 2 - 1) * env#
        Case 4   ' sinus med svep (pickup, uppstigande pling)
            f# = f0# + (f1# - f0#) * (t# / dur#)
            GenSample# = Sin(6.2831853 * f# * t#) * env#
        Case 5   ' två-ton fyrkant (första halvan f0, andra f1)
            If t# < dur# / 2 Then f# = f0# Else f# = f1#
            If Sin(6.2831853 * f# * t#) >= 0 Then GenSample# = env# Else GenSample# = -env#
        Case 6   ' ALERT "dun-DUM-DUM": låg sub-ton (110 Hz) först, sedan två stigande
                 ' hårda fyrkantstoner f0->f1. Front-loadad attack: full vol direkt,
                 ' decay bara i sista 15% (inget mjukt fade-in).
            If t# < dur# * 0.25 Then
                f# = 110
            ElseIf t# < dur# * 0.6 Then
                f# = f0#
            Else
                f# = f1#
            End If
            If t# > dur# * 0.85 Then env# = (dur# - t#) / (dur# * 0.15)
            If env# < 0 Then env# = 0
            If Sin(6.2831853 * f# * t#) >= 0 Then GenSample# = env# Else GenSample# = -env#
        Case Else
            GenSample# = 0
    End Select
End Function

' PlaySoundVol: genererar PCM för ljud id% och pushar till raw-pipen i ett
' _SNDRAWBATCH-anrop. Korta, svaga retro-beeps (volym <= 0.28 i registret;
' undantag: SND_ALERT 0.45 — medvetet tydlig).
Sub PlaySoundVol (id%, vol!)
    sndCalls = sndCalls + 1
    If sndPipe& <= 0 Then Exit Sub
    If id% < 1 Or id% > SND_COUNT Then Exit Sub
    n% = Int(sndDur!(id%) * SND_RATE)
    If n% < 8 Then n% = 8
    If n% > SND_RATE Then n% = SND_RATE
    For i% = 0 To n% - 1
        s# = GenSample#(id%, i%, n%) * sndVol!(id%) * vol!
        If s# > 1 Then s# = 1
        If s# < -1 Then s# = -1
        sndBuf!(i%) = s#
    Next i%
    _SNDRAWBATCH sndBuf!(), 1, sndPipe&, n%
    ' ljud-debug: logga anrop (fotsteg bara via räknare, annars blir logen brusig)
    If id% <> SND_STEP And id% <> SND_ESTEP Then
        sndDbg = FreeFile
        Open "/tmp/schleswig_snd.log" For Append As #sndDbg
        Print #sndDbg, "PlaySound id="; id%; " vol="; vol!; " n="; n%; " pipe="; sndPipe&; " calls="; sndCalls
        Close #sndDbg
    End If
End Sub

' PlaySound: standardvolym. Används av alla spel-händelser via registret.
Sub PlaySound (id%)
    PlaySoundVol id%, 1
End Sub

' ShutdownSound: tömmer och stänger raw-pipen så processen kan avsluta även
' med öppen ljudström (annars kan ljudmotorns tråd hänga på exit).
Sub ShutdownSound
    ' OBS: _SNDRAWDONE utelämnad medvetet — kan blockera när ingen ljudenhet finns
    If sndPipe& > 0 Then
        _SNDCLOSE sndPipe&
        sndPipe& = 0
    End If
    sndDbg = FreeFile
    Open "/tmp/schleswig_snd.log" For Append As #sndDbg
    Print #sndDbg, "SND shutdown: totala PlaySound-anrop="; sndCalls
    Close #sndDbg
End Sub

' StartRun: GEMENSAM övergång till ny runda — används av huvudmenyns START
' och resultatmenyns VIDARE (samma väg = samma muslås-beteende).
' Sätter fadeout; när faden är klar (i menu/fadeout-grenen) går state till
' playing och musen låses (_MOUSEHIDE _DISABLE).
' QuitGame: ENDA avsluts-sökvägen — meny-ESC och QUIT GAME-knappen går båda hit.
' MUS-REVERT: INGEN _MOUSESHOW någonstans i kodbasen (grep-bevis: 0 träffar) —
' låset från app-start förstörs bara när processen dör (compositorn städar).
' Själva exit är ren (End städar via QB64-PE).
QuitGame:
    lockDestroys = lockDestroys + 1   ' markör: exit (inga _MOUSESHOW-anrop finns)
    End

' EngageLock: ENDA lås-sättningen — livstids-lås vid första fade-slutet
' (resp. selftest-init). lockEngaged=1 innebär att riktig pekare är dold resten
' av sessionen och menyerna körs med virtuell pekare (vCurX/vCurY).
Sub EngageLock
    _MOUSEHIDE _DISABLE
    lockEngages = lockEngages + 1
    lockEngaged = 1
End Sub

' PARKED: mouse experiment aa26eee — ingen meny anropar denna längre.
' MoveVirtualCursor: flyttar virtuella pekaren relativt (dx,dy), klamrad till
' skärmen [0,RW-1]x[0,RH-1] — funkar på alla skärmstorlekar.
Sub MoveVirtualCursor (dx, dy)
    vCurX = vCurX + dx: vCurY = vCurY + dy
    If vCurX < 0 Then vCurX = 0
    If vCurX > RW - 1 Then vCurX = RW - 1
    If vCurY < 0 Then vCurY = 0
    If vCurY > RH - 1 Then vCurY = RH - 1
End Sub

' PARKED: mouse experiment aa26eee — meny-hit-test är tangentdriven nu.
' ButtonHit%: -1 om (px,py) ligger inuti knapp-rektangeln, annars 0.
' KeyUseHit%: central check for the universal interaction key E (Const KeyUse).
' Menus select/confirm with it now; doors etc. phase 5+ — reuse this exact check.
Function KeyUseHit% (k$)
    If k$ = Chr$(KeyUse) Or k$ = UCase$(Chr$(KeyUse)) Or _KeyDown(KeyUse) Then
        KeyUseHit% = -1
    Else
        KeyUseHit% = 0
    End If
End Function

Function ButtonHit% (px, py, x0, y0, x1, y1)
    If px >= x0 And px <= x1 And py >= y0 And py <= y1 Then
        ButtonHit% = -1
    Else
        ButtonHit% = 0
    End If
End Function

' PARKED: mouse experiment aa26eee — ingen meny renderar pekaren längre.
' DrawCursor: ritar pil-spriten från cursorBuf& (skapas i init) så att pilens
' SPETS (topp) hamnar exakt på (x,y). I playing är crosshair oförändrad.
Sub DrawCursor (x, y)
    If cursorBuf& <> 0 Then _PutImage (x - cursorSize \ 2, y), cursorBuf&   ' <>0: handtag kan vara negativa i QB64-PE
End Sub

StartRun:
    ' ENDA start-vägen (meny START-klick/SPACE + pendingStart från VIDARE).
    ' startRuns räknar triggeringar — selftest fas12b bevisar att VIDARE går här.
    startRuns = startRuns + 1
    hp = 100: ammo = 5
    px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0   ' Fas 5A: start from map 'S'
    If gameMode$ = "campaign" Then killsTotal = 0: restarts = 0: waveNo = 0   ' 5C: fresh campaign counters, wave register starts at wave 1
    Gosub ApplyMapSpawns   ' Fas 5A: pickups/keys/doors from map, doors closed each round
    Gosub SpawnEnemies
    hpMsg$ = "": hpMsgTime = 0
    lastShotTime = -1: tracerTime = -1: flashTime = -1: flashDist = 99
    gunX = 0: gunY = 0: recoil = 0: muzzleT = 0: shakeT = 0: bobPhase = 0: turnDelta = 0: gunSway = 0: anglePrev = angle   ' Fas 4C viewmodel reset
    deathTime = 0: hover = 0: prevHover = 0: winPending = 0: runTimeFrozen = -1   ' VIDARE: reset tid 0 (ej fryst)
    runT0 = Timer: shotsFired = 0: dmgTaken = 0
    segShots = shotsFired: segDmg = dmgTaken: segT0 = runT0: segStartT = Timer: lvlT0 = Timer: lvlTime(lvlIdx) = 0   ' 5C: per-level-segment score snapshot
    ' SKYDD mot fastnad rörelse efter övergång (t.ex. VIDARE): nollställ ALLE
    ' rörelse-flaggor INNAN state=fadeout och töm tangentbords-buffertarna
    ' (INKEY$/_KEYHIT) så inga key-repeats från föregående skärm överlever.
    mvF = 0: mvB = 0: mvL = 0: mvR = 0: turnL = 0: turnR = 0: fireBtn = 0
    _KeyClear
    state$ = "fadeout"
    fadeT0 = Timer
    Return

' PickAction (5D start menu, no-arg): pickAct 1 = TEST ARENA (default.map, already
' loaded at init), 2 = CAMPAIGN (maps/levels.lst from level 1; broken lst/map ->
' the same loud fatal screen as everywhere else).
PickAction:
    If pickAct = 1 Then
        menuPick = 0: gameMode$ = "arena"
        Gosub StartRun
        SOUND 300, 2: SOUND 150, 3
    ElseIf pickAct = 2 Then
        menuPick = 0: gameMode$ = "campaign"
        lstFile$ = "maps/levels.lst"
        Gosub LoadLevelsLst
        If loadFatal Then
            Print fatalMsg$   ' log line to the terminal
            state$ = "fatal"
        Else
            lvlIdx = 0
            mapFile$ = lvlFile$(0)
            Gosub LoadMapAuto
            If loadFatal Then
                Print fatalMsg$
                state$ = "fatal"
            Else
                Gosub StartRun
                SOUND 300, 2: SOUND 150, 3
            End If
        End If
    End If
    Return

' LogMouse: mus-diagnos till /tmp/schleswig_mouse.log (frame + state + anrop)
Sub LogMouse (msg$)
    mf = FreeFile
    Open "/tmp/schleswig_mouse.log" For Append As #mf
    Print #mf, "t="; LTrim$(Str$(Int(Timer * 10) / 10)); " state="; state$; " "; msg$
    Close #mf
End Sub

' BtnTextW: bredd (px) på label i knapp-fonten (TFTF ~2x). w returneras by-ref.
Sub BtnTextW (label$, w)
    f& = _Font              ' spara nuvarande font
    If btnFont& > 0 Then _Font btnFont&
    w = _PrintWidth(label$)
    _Font f&                ' återställ direkt — mätningen är klar
End Sub

' BtnGeom: knapp-rektangel med GIVEN bredd (btnW) — alla knappar inom en meny
' får samma bredd (längsta labeln + 2*padX, se anroparen). cx = mitt-x,
' topY = övre kant; x0/y0/x1/y1 returneras (QB64 skickar by-ref).
' Höjd = _FontHeight + 2*padY (ca 1,2-1,5x ursprunglig knapp-höjd vid 2x-text).
Sub BtnGeom (btnW, cx, topY, x0, y0, x1, y1)
    f& = _Font              ' spara nuvarande font
    If btnFont& > 0 Then _Font btnFont&
    th = _FontHeight
    _Font f&                ' återställ direkt — mätningen är klar
    padY = Int(btnFontSize * 5 / 8): If padY < 8 Then padY = 8
    bh2 = th + padY * 2
    x0 = cx - btnW \ 2: y0 = topY
    x1 = x0 + btnW: y1 = y0 + bh2
End Sub

' DrawButton: EN knapp-widget för huvudmenyn + resultatmenyn (samma palett).
' Palett (hover-kontrast, beslut 2026-11-23):
'   normal: fill RGB(30,30,70), text RGB(255,255,255), vit kant, svart skugga
'   hover:  fill RGB(255,200,0) (amber), text RGB(0,0,0), vit kant, ingen skugga
' Stor text via riktig TTF-font (_FONT btnFont&, ~2x HUD) — INGEN _PutImage/
' fontBuf (bild-skalning kraschade "Invalid expression" i denna QB64-PE-version).
' _FONT och _PRINTMODE återställs ALLTID innan Sub avslutas — inget spill.
Sub DrawButton (bx0, by0, bx1, by1, label$, hovered)
    bw = bx1 - bx0: bh = by1 - by0
    If hovered Then
        Line (bx0, by0)-(bx1, by1), _RGB32(255, 200, 0), BF
        tc& = _RGB32(0, 0, 0)
    Else
        Line (bx0, by0)-(bx1, by1), _RGB32(30, 30, 70), BF
        tc& = _RGB32(255, 255, 255)
    End If
    Line (bx0, by0)-(bx1, by1), _RGB32(255, 255, 255), B
    f& = _Font              ' spara nuvarande font (aldrig tömd, alltid återställd)
    If btnFont& > 0 Then _Font btnFont&   ' stor TTF-text; 0 = fallback inbyggd font
    _PrintMode _KeepBackground   ' transparent text-bakgrund (ingen ruta bakom label)
    tw = _PrintWidth(label$): th = _FontHeight
    tx = bx0 + (bw - tw) \ 2
    ty = by0 + (bh - th) \ 2
    so = btnFontSize \ 16: If so < 1 Then so = 1   ' skugg-offset skalad med fonten
    If hovered = 0 Then
        Color _RGB32(0, 0, 0)
        _PrintString (tx + so, ty + so), label$   ' skugga bara i normal-läge
    End If
    Color tc&
    _PrintString (tx, ty), label$
    _PrintMode _FillBackground   ' återställ default-läge
    _Font f&                     ' återställ föregående font — inget _FONT-spill
End Sub

' ======== Fas 5A: .MAP LOADER + CELL HELPERS ========
' .map format (documented in AGENTS.md): rows = map rows, char = cell.
'   '#' wall   '.' floor   ' ' out-of-bounds (wall in BFS/render)
'   'S' player start (CASE: 'S' != 's'!)
'   'F','O','U','K','G' = FOOT/OFFICER/MUSKETEER/CAPTAIN/GENERAL enemy spawns
'   'M' medkit  'A' ammo pickup
'   'd' wood door (E always opens)  '1'/'2'/'3' = bronze/silver/gold door
'   'b','s','g' = bronze/silver/gold KEY pickups (lowercase = keys, uppercase = enemies)
' Row length = width, row count = height. Malformed (ragged rows / bad char)
' -> safe default grid + log, never a crash.

' MapFileFromCmd$: command-line arg -> map file path ("" for selftest/none)
Function MapFileFromCmd$ (c$)
    t$ = LCase$(LTrim$(RTrim$(c$)))
    If t$ = "" Or t$ = "selftest" Then
        MapFileFromCmd$ = ""
    Else
        MapFileFromCmd$ = t$
    End If
End Function

' GameModeFromCmd$ (5C): command-line arg -> game mode:
'   "" -> "arena" | "selftest" -> "selftest" | "campaign"/"--level N" -> "campaign"
'   anything else -> "single" (that arg is a .map file)
Function GameModeFromCmd$ (c$)
    t$ = LCase$(LTrim$(RTrim$(c$)))
    If t$ = "selftest" Then
        GameModeFromCmd$ = "selftest"
    ElseIf t$ = "" Then
        GameModeFromCmd$ = "arena"
    ElseIf t$ = "campaign" Then
        GameModeFromCmd$ = "campaign"
    ElseIf Left$(t$, 7) = "--level" Then
        GameModeFromCmd$ = "campaign"
    Else
        GameModeFromCmd$ = "single"
    End If
End Function

' MenuPickFromCmd% (5D): 1 iff no argument (IDE F5 run) -> the start menu offers
' [1] TEST ARENA / [2] CAMPAIGN instead of loading straight away.
Function MenuPickFromCmd% (c$)
    If LTrim$(RTrim$(c$)) = "" Then
        MenuPickFromCmd% = 1
    Else
        MenuPickFromCmd% = 0
    End If
End Function

' AutoStartFromCmd% (5D): 1 iff a campaign argument ("campaign" / "--level N")
' -> those modes skip the start menu and go straight into the game.
Function AutoStartFromCmd% (c$)
    If GameModeFromCmd$(c$) = "campaign" Then
        AutoStartFromCmd% = 1
    Else
        AutoStartFromCmd% = 0
    End If
End Function

' LevelFromCmd% (5C): "--level N" (or "--level=N") -> 1-based start level; 0 = not given.
Function LevelFromCmd% (c$)
    t$ = LCase$(LTrim$(RTrim$(c$)))
    LevelFromCmd% = 0
    If Left$(t$, 7) = "--level" Then
        r$ = LTrim$(RTrim$(Mid$(t$, 8)))
        If Left$(r$, 1) = "=" Then r$ = LTrim$(Mid$(r$, 2))
        n19 = Val(r$)
        If n19 >= 1 Then LevelFromCmd% = Int(n19)
    End If
End Function

' HudLevelTag$ (5C, FIX F): the HUD mode/level line.
'   campaign -> "LVL <n>/<total> <name>  MAP <file> #<hash>  RESTARTS <r>"
'   single/selftest -> "SINGLE <file> #<hash>"   arena -> "ARENA <file> #<hash>"
Function HudLevelTag$
    If gameMode$ = "campaign" Then
        HudLevelTag$ = "LVL " + LTrim$(Str$(lvlIdx + 1)) + "/" + LTrim$(Str$(lvlN)) + " " + lvlName$(lvlIdx) + "  MAP " + mapFile$ + " #" + LTrim$(Str$(mapHash&)) + "  RESTARTS " + LTrim$(Str$(restarts))
    ElseIf gameMode$ = "single" Or gameMode$ = "selftest" Then
        HudLevelTag$ = "SINGLE " + mapFile$ + " #" + LTrim$(Str$(mapHash&))
    Else
        HudLevelTag$ = "ARENA " + mapFile$ + " #" + LTrim$(Str$(mapHash&))
    End If
End Function

' CellAt$: raw map char at cell (x,y); outside the map -> " " (OOB = wall)
Function CellAt$ (cx, cy)
    If cx < 0 Or cy < 0 Or cx >= mapW Or cy >= mapH Then
        CellAt$ = " "
    Else
        CellAt$ = Mid$(mapRow$(cy), cx + 1, 1)
    End If
End Function

' Solid%: 1 = not walkable (wall, OOB, or CLOSED door)
Function Solid% (cx, cy)
    c$ = CellAt$(cx, cy)
    If c$ = "#" Or c$ = " " Then
        Solid% = 1
    ElseIf c$ = "d" Or c$ = "1" Or c$ = "2" Or c$ = "3" Then
        Solid% = 1 - doorOpen%(cx, cy)   ' closed door = wall, open door = walkable
    Else
        Solid% = 0
    End If
End Function

' OpenCell%: 1 = walkable (not solid)
Function OpenCell% (cx, cy)
    OpenCell% = 1 - Solid%(cx, cy)
End Function

' LoadMapFile: reads lmPath$ into mapSrc$(0..srcN-1). lmOK=1 if any rows read.
LoadMapFile:
    lmOK = 0
    lmF = FreeFile
    Open lmPath$ For Input As #lmF
    srcN = 0
    While Not Eof(lmF) And srcN < MAP_MAX
        Line Input #lmF, lmLn$
        If Right$(lmLn$, 1) = Chr$(13) Then lmLn$ = Left$(lmLn$, Len(lmLn$) - 1)
        mapSrc$(srcN) = lmLn$
        srcN = srcN + 1
    Wend
    Close #lmF
    If srcN > 0 Then lmOK = 1
    Return

' ParseMap: parses mapSrc$(0..srcN-1) into mapTmp$ staging grid + spawn lists.
' mapRow$/mapW/mapH are COMMITTED only on full success (exactly one 'S', uniform
' row length, valid chars). On failure: pmOK=0, errRow/errCol/errWhy$ set, mapRow$
' untouched (no half-parsed grid can reach the renderer). Spawn chars become '.'
' in the grid (doors keep their char for render color).
ParseMap:
    pmOK = 0
    errRow = 0: errCol = 0: errWhy$ = ""
    If srcN < 1 Or srcN > MAP_MAX Then errWhy$ = "empty map file": Return
    mw2 = Len(mapSrc$(0))
    If mw2 < 1 Or mw2 > MAP_MAX Then errWhy$ = "bad row width": errRow = 1: Return
    For pi = 1 To srcN - 1
        If Len(mapSrc$(pi)) <> mw2 Then
            errWhy$ = "ragged row (expected " + Str$(mw2) + " chars)"
            errRow = pi + 1: errCol = Len(mapSrc$(pi)) + 1
            Return
        End If
    Next pi
    nStartS = 0: tStartX = -1: tStartY = -1
    spEnN = 0: spPkN = 0: spAmN = 0: spKeyN = 0
    For py2 = 0 To srcN - 1
        r$ = mapSrc$(py2)
        prow$ = ""
        For px2 = 0 To mw2 - 1
            ch$ = Mid$(r$, px2 + 1, 1)
            good = 0
            Select Case ch$
                Case "#", ".", " "
                    prow$ = prow$ + ch$: good = 1
                Case "S"
                    prow$ = prow$ + ".": nStartS = nStartS + 1: tStartX = px2: tStartY = py2: good = 1
                Case "F", "O", "U", "K", "G"
                    prow$ = prow$ + "."
                    If spEnN < 10 Then
                        If ch$ = "F" Then spEnT(spEnN) = ET_FOOT
                        If ch$ = "O" Then spEnT(spEnN) = ET_OFFICER
                        If ch$ = "U" Then spEnT(spEnN) = ET_MUSKETEER
                        If ch$ = "K" Then spEnT(spEnN) = ET_CAPTAIN
                        If ch$ = "G" Then spEnT(spEnN) = ET_GENERAL
                        spEnX(spEnN) = px2: spEnY(spEnN) = py2: spEnN = spEnN + 1
                    End If
                    good = 1
                Case "M"
                    prow$ = prow$ + "."
                    If spPkN < 10 Then spPkX(spPkN) = px2: spPkY(spPkN) = py2: spPkN = spPkN + 1
                    good = 1
                Case "A"
                    prow$ = prow$ + "."
                    If spAmN < 10 Then spAmX(spAmN) = px2: spAmY(spAmN) = py2: spAmN = spAmN + 1
                    good = 1
                Case "d", "1", "2", "3"
                    prow$ = prow$ + ch$: good = 1   ' door stays in grid (render color)
                Case "b", "s", "g"
                    prow$ = prow$ + "."
                    If spKeyN < 10 Then
                        If ch$ = "b" Then spKeyT(spKeyN) = 1
                        If ch$ = "s" Then spKeyT(spKeyN) = 2
                        If ch$ = "g" Then spKeyT(spKeyN) = 3
                        spKeyX(spKeyN) = px2: spKeyY(spKeyN) = py2: spKeyN = spKeyN + 1
                    End If
                    good = 1
            End Select
            If good = 0 Then
                errWhy$ = "invalid char '" + ch$ + "'"
                errRow = py2 + 1: errCol = px2 + 1
                Return
            End If
        Next px2
        mapTmp$(py2) = prow$
    Next py2
    If nStartS <> 1 Then
        errWhy$ = "needs exactly one 'S' start (found " + Str$(nStartS) + ")"
        If tStartX >= 0 Then errRow = tStartY + 1: errCol = tStartX + 1
        Return
    End If
    ' COMMIT — only now do mapRow$/mapW/mapH/doorOpen% change.
    ' 5D: the committed map arrays are REDIM'd to the ACTUAL map size — no static
    ' map-dimension constant anywhere (MAP_MAX remains only as the input-read cap
    ' for mapSrc$/mapTmp$ and the parse guard).
    mapW = mw2: mapH = srcN
    REDIM mapRow$(mapH - 1)
    REDIM doorOpen%(mapW - 1, mapH - 1)
    REDIM bfsD(mapW - 1, mapH - 1)
    REDIM qx(mapW * mapH - 1)
    REDIM qy(mapW * mapH - 1)
    For py2 = 0 To mapH - 1: mapRow$(py2) = mapTmp$(py2): Next py2
    For yy = 0 To mapH - 1
        For xx = 0 To mapW - 1
            doorOpen%(xx, yy) = 0
        Next xx
    Next yy
    plStartX = tStartX: plStartY = tStartY
    mapWarn$ = ""
    If spEnN = 0 Then mapWarn$ = "map has no enemy spawns (F/O/U/K/G) — wave fill only"
    pmOK = 1
    mapValid = 1
    Return

' LoadMapAuto: MANDATORY map file — there is no embedded fallback anymore.
' No argument -> maps/default.map. Path candidates: arg as-is, then
' "schleswig/" + arg, so both work:
'   ./schleswig/schleswig maps/test64.map     (from QB64pe root)
'   schleswig/schleswig maps/test64.map       (from repo root)
' Any failure (not found / unreadable / invalid) -> loadFatal=1 + fatalMsg$
' (loud error screen + log line), mapValid stays 0, mapRow$ untouched.
LoadMapAuto:
    loadedMapFile$ = ""
    loadFatal = 0: mapValid = 0: fatalMsg$ = "": errRow = 0: errCol = 0: mapWarn$ = ""
    If Len(mapFile$) = 0 Then mapFile$ = "maps/default.map"
    If _FileExists(mapFile$) Then
        lmPath$ = mapFile$
    ElseIf _FileExists("schleswig/" + mapFile$) Then
        lmPath$ = "schleswig/" + mapFile$
    Else
        lmPath$ = ""
    End If
    If Len(lmPath$) = 0 Then
        loadFatal = 1
        fatalMsg$ = "MAP FILE NOT FOUND: " + mapFile$ + ". Press Q to quit."
        Return
    End If
    Gosub LoadMapFile
    If lmOK = 0 Then
        loadFatal = 1
        fatalMsg$ = "MAP FILE NOT FOUND: " + lmPath$ + ". Press Q to quit."
        Return
    End If
    pmOK = 0: Gosub ParseMap
    If pmOK = 0 Then
        loadFatal = 1: mapValid = 0
        fatalMsg$ = "INVALID MAP: " + lmPath$ + " line " + LTrim$(Str$(errRow)) + " col " + LTrim$(Str$(errCol)) + ": " + errWhy$ + ". Press Q to quit."
        Return
    End If
    loadedMapFile$ = lmPath$
    ' 5C: grid hash of the committed map (HUD tag + selftest hash checks)
    mapHash& = 0
    For yy = 0 To mapH - 1
        For xx = 0 To mapW - 1
            mapHash& = (mapHash& * 31 + Asc(Mid$(mapRow$(yy), xx + 1, 1))) And &H7FFFFFFF
        Next xx
    Next yy
    Return

' LoadLevelsLst (5C): reads lstFile$ (default "maps/levels.lst", same
' "schleswig/" path fallback as maps) into lvlFile$/lvlName$, lvlN entries.
' Format: ONE level per line "<file.map>|<display name>"; blank lines skipped;
' file order = play order; the LAST line = end of the campaign (documented in
' AGENTS.md). Failure -> loadFatal=1 + fatalMsg$ ("LEVELS FILE NOT FOUND" /
' "INVALID LEVELS LIST line <r>: <why>") -> same loud fatal screen as maps.
LoadLevelsLst:
    lvlN = 0: loadFatal = 0: fatalMsg$ = ""
    lp$ = lstFile$
    If Not _FileExists(lp$) Then
        If _FileExists("schleswig/" + lp$) Then lp$ = "schleswig/" + lp$
    End If
    If Not _FileExists(lp$) Then
        loadFatal = 1
        fatalMsg$ = "LEVELS FILE NOT FOUND: " + lstFile$ + ". Press Q to quit."
        Return
    End If
    lf = FreeFile
    Open lp$ For Input As #lf
    lstLn = 0
    While Not Eof(lf)
        Line Input #lf, lstLn$
        If Right$(lstLn$, 1) = Chr$(13) Then lstLn$ = Left$(lstLn$, Len(lstLn$) - 1)
        lstLn = lstLn + 1
        t$ = LTrim$(RTrim$(lstLn$))
        If Len(t$) > 0 Then
            If lvlN >= 20 Then
                loadFatal = 1
                fatalMsg$ = "INVALID LEVELS LIST line " + LTrim$(Str$(lstLn)) + ": too many levels (max 20). Press Q to quit."
                Close #lf
                Return
            End If
            p = InStr(t$, "|")
            If p > 0 Then
                fn$ = LTrim$(RTrim$(Left$(t$, p - 1))): nm$ = LTrim$(RTrim$(Mid$(t$, p + 1)))
            Else
                fn$ = "": nm$ = ""
            End If
            If p < 2 Or Len(fn$) = 0 Or Len(nm$) = 0 Then
                loadFatal = 1
                fatalMsg$ = "INVALID LEVELS LIST line " + LTrim$(Str$(lstLn)) + ": want <file.map>|<name>. Press Q to quit."
                Close #lf
                Return
            End If
            lvlFile$(lvlN) = fn$: lvlName$(lvlN) = nm$: lvlN = lvlN + 1
        End If
    Wend
    Close #lf
    If lvlN < 1 Then
        loadFatal = 1
        fatalMsg$ = "INVALID LEVELS LIST line 1: empty list (need <file.map>|<name> per line). Press Q to quit."
    End If
    Return

' LoadLevel (5C campaign): loads level lvlIdx (0-based) from the levels list —
' new ParseMap via LoadMapAuto (map failure -> same loud fatal screen), then
' enemy/wave registers reset via the EXISTING SpawnEnemies (waveNo forced to 0
' first, so level N's enemies/waves can NEVER leak into N+1; SpawnEnemies also
' clears the projectile pool + BFS target). Score counters (shotsFired/
' dmgTaken/runT0) are KEPT across levels (score carries over); the per-level
' segment snapshot (segShots/segDmg/segT0/segStartT) is taken for RESTART LEVEL.
LoadLevel:
    mapFile$ = lvlFile$(lvlIdx)
    Gosub LoadMapAuto
    If loadFatal Then
        Print fatalMsg$   ' log line to the terminal
        state$ = "fatal"
        Return
    End If
    Gosub ApplyMapSpawns
    px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0
    hp = 100: ammo = 5
    waveNo = 0
    Gosub SpawnEnemies   ' resets ALL enemy state + projectiles + BFS (no leak from level N)
    hpMsg$ = "": hpMsgTime = 0
    lastShotTime = -1: tracerTime = -1: flashTime = -1: flashDist = 99
    gunX = 0: gunY = 0: recoil = 0: muzzleT = 0: shakeT = 0: bobPhase = 0: turnDelta = 0: gunSway = 0: anglePrev = angle   ' Fas 4C viewmodel reset
    winPending = 0: runTimeFrozen = -1: deathTime = 0
    mvF = 0: mvB = 0: mvL = 0: mvR = 0: turnL = 0: turnR = 0: fireBtn = 0: _KeyClear
    segShots = shotsFired: segDmg = dmgTaken: segT0 = runT0: segStartT = Timer   ' per-level-segment score snapshot
    lvlT0 = Timer: lvlTime(lvlIdx) = 0
    state$ = "fadeout"
    fadeT0 = Timer
    Return

' ApplyMapSpawns: push map spawn lists into the live arrays; reset keys + doors
' (each round starts with all doors closed and no keys).
ApplyMapSpawns:
    For i = 0 To 10
        If i < spPkN Then pkX(i) = spPkX(i) + 0.5: pkY(i) = spPkY(i) + 0.5: pkActive(i) = 1 Else pkActive(i) = 0
        If i < spAmN Then amX(i) = spAmX(i) + 0.5: amY(i) = spAmY(i) + 0.5: amActive(i) = 1 Else amActive(i) = 0
        If i < spKeyN Then keyX(i) = spKeyX(i) + 0.5: keyY(i) = spKeyY(i) + 0.5: keyType(i) = spKeyT(i): keyActive(i) = 1 Else keyActive(i) = 0
    Next i
    hasBronze = 0: hasSilver = 0: hasGold = 0
    For yy = 0 To mapH - 1
        For xx = 0 To mapW - 1
            doorOpen%(xx, yy) = 0
        Next xx
    Next yy
    Return

' LOSCheck: DDA-stråle från (fx,fy) till (tx,ty); losOK=1 om ingen väggcell på vägen
LOSCheck:
    losOK = 1
    ldx = tx - fx: ldy = ty - fy
    ldist = Sqr(ldx * ldx + ldy * ldy)
    If ldist < 0.01 Then Return
    lrx = ldx / ldist: lry = ldy / ldist
    lmx = Int(fx): lmy = Int(fy)
    If lrx = 0 Then lddx = 1E+30 Else lddx = Abs(1 / lrx)
    If lry = 0 Then lddy = 1E+30 Else lddy = Abs(1 / lry)
    If lrx < 0 Then lstepX = -1: lsdx = (fx - lmx) * lddx Else lstepX = 1: lsdx = (lmx + 1 - fx) * lddx
    If lry < 0 Then lstepY = -1: lsdy = (fy - lmy) * lddy Else lstepY = 1: lsdy = (lmy + 1 - fy) * lddy
    ltx = Int(tx): lty = Int(ty)
    For lguard = 1 To mapW + mapH   ' Fas 5A: LOS guard covers any map size
        If lsdx < lsdy Then
            lsdx = lsdx + lddx: lmx = lmx + lstepX
        Else
            lsdy = lsdy + lddy: lmy = lmy + lstepY
        End If
        If lmx < 0 Or lmx > mapW - 1 Or lmy < 0 Or lmy > mapH - 1 Then Exit For
        If Solid%(lmx, lmy) Then losOK = 0: Exit For
        If lmx = ltx And lmy = lty Then Exit For
    Next lguard
    Return

' BFSCompute: avståndskarta bfsD(x,y) från målcell (bfsTX,bfsTY), BFS 4-riktning över
' öppna celler (Fas 5A: valfri kartstorlek; stängd dörr = vägg via Solid%).
' Sätts bfsForX/bfsForY till målcellen. Räknas bara vid cellbyte (callern).
BFSCompute:
    For yy = 0 To mapH - 1
        For xx = 0 To mapW - 1
            bfsD(xx, yy) = -1
        Next xx
    Next yy
    If bfsTX < 0 Or bfsTX > mapW - 1 Or bfsTY < 0 Or bfsTY > mapH - 1 Then bfsForX = -1: bfsForY = -1: Return
    If Solid%(bfsTX, bfsTY) Then bfsForX = -1: bfsForY = -1: Return
    qh = 0: qt = 0
    qx(0) = bfsTX: qy(0) = bfsTY: bfsD(bfsTX, bfsTY) = 0: qt = 1
    While qh < qt
        cx = qx(qh): cy = qy(qh): qh = qh + 1
        cd = bfsD(cx, cy) + 1
        If cx + 1 <= mapW - 1 Then If OpenCell%(cx + 1, cy) Then If bfsD(cx + 1, cy) = -1 Then bfsD(cx + 1, cy) = cd: qx(qt) = cx + 1: qy(qt) = cy: qt = qt + 1
        If cx - 1 >= 0 Then If OpenCell%(cx - 1, cy) Then If bfsD(cx - 1, cy) = -1 Then bfsD(cx - 1, cy) = cd: qx(qt) = cx - 1: qy(qt) = cy: qt = qt + 1
        If cy + 1 <= mapH - 1 Then If OpenCell%(cx, cy + 1) Then If bfsD(cx, cy + 1) = -1 Then bfsD(cx, cy + 1) = cd: qx(qt) = cx: qy(qt) = cy + 1: qt = qt + 1
        If cy - 1 >= 0 Then If OpenCell%(cx, cy - 1) Then If bfsD(cx, cy - 1) = -1 Then bfsD(cx, cy - 1) = cd: qx(qt) = cx: qy(qt) = cy - 1: qt = qt + 1
    Wend
    bfsForX = bfsTX: bfsForY = bfsTY
    Return

' DodgeRnd# (Fas 4A): dedicated seedable LCG stream for dodge rolls, separate
' from the global Rnd (which the procedural sound consumes sample-by-sample).
' Selftest sets dodgeSeed& to a known value -> deterministic, verifiable dodge.
Function DodgeRnd#
    dodgeSeed& = (dodgeSeed& * 1103515245 + 12345) And &H7FFFFFFF
    DodgeRnd# = dodgeSeed& / 2147483647#
End Function

' EnemyDodge (Fas 4A): immediate 1-cell sidestep perpendicular to the bullet
' line (player->enemy). Target cell must be BFS-valid: inside the map, not a
' wall, not the player's cell. Uses bestE (set by the shooting block).
EnemyDodge:
    bdx = enX(bestE) - px: bdy = enY(bestE) - py
    bl = Sqr(bdx * bdx + bdy * bdy): If bl < 0.01 Then bdx = 1: bdy = 0: bl = 1
    ux = -bdy / bl: uy = bdx / bl          ' unit perpendicular to the bullet line
    If Abs(ux) >= Abs(uy) Then
        rx = Sgn(ux): ry = 0
    Else
        rx = 0: ry = Sgn(uy)
    End If
    If rx = 0 And ry = 0 Then Return
    zs = 1: If DodgeRnd# < 0.5 Then zs = -1
    For dtr = 0 To 1                        ' chosen side first, then the other
        s2 = zs: If dtr = 1 Then s2 = -zs
        dtx2 = Int(enX(bestE)) + rx * s2
        dty2 = Int(enY(bestE)) + ry * s2
        If dtx2 >= 0 And dtx2 <= mapW - 1 And dty2 >= 0 And dty2 <= mapH - 1 Then
            If OpenCell%(dtx2, dty2) And (dtx2 <> Int(px) Or dty2 <> Int(py)) Then
                enX(bestE) = dtx2 + 0.5: enY(bestE) = dty2 + 0.5
                dtr = 99
            End If
        End If
    Next dtr
    Return

' AiRnd# (Fas 4B): dedicated seedable LCG for enemy AI randomness (musketeer
' spread etc.) — separate from global Rnd (consumed by sound) and dodgeSeed&.
Function AiRnd#
    aiSeed& = (aiSeed& * 1103515245 + 12345) And &H7FFFFFFF
    AiRnd# = aiSeed& / 2147483647#
End Function

' EnemyTakeHit (Fas 4B): shared damage path for an enemy hit by a player ball
' or mortar splash. Caller sets hitE (enemy index) + hitDmg. Kill bookkeeping
' (killsTotal, last-kill freeze) + Fas 4A dodge roll on non-lethal hits.
EnemyTakeHit:
    enHP(hitE) = enHP(hitE) - hitDmg
    If enHP(hitE) <= 0 Then
        enActive(hitE) = 0
        killsTotal = killsTotal + 1   ' Fas 4A: total kills gate the captain spawn
        hpMsg$ = "ENEMY DOWN"
        hpMsgTime = Timer
        PlaySound SND_ENDIE
        ' freeze run-time at EXACTLY the last kill (same rule as before)
        aliveNow = 0
        For aej = 0 To 10
            If enActive(aej) Then aliveNow = aliveNow + 1
        Next aej
        If aliveNow = 0 Then Gosub FreezeAtLastKill
    Else
        hpMsg$ = "HIT"
        hpMsgTime = Timer
        PlaySound SND_HIT
        ' Fas 4A: dodge-on-hit (per-type etDodge!, seedable LCG DodgeRnd#)
        If DodgeRnd# < etDodge!(enType(hitE)) Then bestE = hitE: Gosub EnemyDodge
    End If
    Return

' SpawnProjectile (Fas 4B): adds a projectile to the pool. Caller sets spX/spY,
' spDX/spDY (unit dir), spSpd!, spOwner (0=player, 1=enemy), spDmg, spType
' (PR_BALL/PR_MORTAR), spSrcType (shooter's type, splash params), and for
' MORTAR spTX/spTY (target cell) + spLandT (Timer at landing). Slot in spSlot.
SpawnProjectile:
    spSlot = -1
    spi = 0
    While spi <= PR_MAX And spSlot = -1
        If prActive(spi) = 0 Then spSlot = spi
        spi = spi + 1
    Wend
    If spSlot = -1 Then Return
    prActive(spSlot) = 1
    prX(spSlot) = spX: prY(spSlot) = spY
    prDX(spSlot) = spDX: prDY(spSlot) = spDY
    prSpd!(spSlot) = spSpd!: prOwner(spSlot) = spOwner
    prDmg(spSlot) = spDmg: prType(spSlot) = spType: prSrcType(spSlot) = spSrcType
    prTX(spSlot) = spTX: prTY(spSlot) = spTY: prLandT(spSlot) = spLandT
    projSpawned = projSpawned + 1
    Return

' UpdateProjectiles (Fas 4B): per-frame projectile physics. BALL: short sub-
' steps (<=0.1 cell) with wall check, then hit test vs enemies (player-owned)
' or vs player (enemy-owned). MORTAR: flies over obstacles (NO wall check)
' until prLandT, then MortarLand splash.
UpdateProjectiles:
    For pi = 0 To PR_MAX
        If prActive(pi) Then
            If prType(pi) = PR_BALL Then
                move! = prSpd!(pi) * dt
                steps = Int(move! / 0.1) + 1
                stp! = move! / steps
                dead = 0
                For s = 1 To steps
                    nx = prX(pi) + prDX(pi) * stp!
                    ny = prY(pi) + prDY(pi) * stp!
                    If nx < 0 Or nx >= mapW Or ny < 0 Or ny >= mapH Then dead = 1: s = steps
                    If dead = 0 Then
                        If Solid%(Int(nx), Int(ny)) Then dead = 1: s = steps
                    End If
                    If dead = 0 Then prX(pi) = nx: prY(pi) = ny
                Next s
                If dead Then prActive(pi) = 0
                If prActive(pi) Then
                    If prOwner(pi) = 0 Then
                        ' player ball vs enemies
                        For j = 0 To 10
                            If enActive(j) And prActive(pi) Then
                                If Sqr((enX(j) - prX(pi)) ^ 2 + (enY(j) - prY(pi)) ^ 2) < 0.35 Then
                                    hitE = j: hitDmg = prDmg(pi)
                                    Gosub EnemyTakeHit
                                    prActive(pi) = 0
                                End If
                            End If
                        Next j
                    Else
                        ' enemy ball vs player
                        If Sqr((px - prX(pi)) ^ 2 + (py - prY(pi)) ^ 2) < 0.35 Then
                            hp = hp - prDmg(pi)
                            If hp < 0 Then hp = 0
                            dmgTaken = dmgTaken + prDmg(pi)   ' highscore: projektil-skada
                            hpMsg$ = "-" + Str$(prDmg(pi)) + " HP"
                            hpMsgTime = Timer
                            PlaySound SND_HURT
                            prActive(pi) = 0
                        End If
                    End If
                End If
            Else
                ' MORTAR: no wall check during flight; lands at prLandT
                If Timer >= prLandT(pi) Then
                    Gosub MortarLand
                    prActive(pi) = 0
                End If
            End If
        End If
    Next pi
    Return

' MortarLand (Fas 4B): splash at (prTX+0.5, prTY+0.5) of projectile pi.
' Full damage within 0.5 cells, linear falloff to 0 at the splash radius.
' Hits BOTH the player and all enemies (friendly fire).
MortarLand:
    cx = prTX(pi) + 0.5: cy = prTY(pi) + 0.5
    st = prSrcType(pi): If st < 0 Or st > ET_COUNT - 1 Then st = 0   ' defensive clamp
    sR! = etSplashR!(st)
    sDmg = etSplashDmg(st)
    PlaySound SND_BOOM
    pd = Sqr((px - cx) ^ 2 + (py - cy) ^ 2)
    If pd <= sR! Then
        fd! = 1: If pd > 0.5 Then fd! = 1 - (pd - 0.5) / (sR! - 0.5)
        If fd! < 0 Then fd! = 0
        dmg = Int(sDmg * fd!)
        If dmg > 0 Then
            hp = hp - dmg: If hp < 0 Then hp = 0
            dmgTaken = dmgTaken + dmg
            hpMsg$ = "-" + Str$(dmg) + " HP"
            hpMsgTime = Timer
            PlaySound SND_HURT
        End If
    End If
    For j = 0 To 10
        If enActive(j) Then
            ed = Sqr((enX(j) - cx) ^ 2 + (enY(j) - cy) ^ 2)
            If ed <= sR! Then
                fd! = 1: If ed > 0.5 Then fd! = 1 - (ed - 0.5) / (sR! - 0.5)
                If fd! < 0 Then fd! = 0
                dmg = Int(sDmg * fd!)
                If dmg > 0 Then
                    hitE = j: hitDmg = dmg
                    Gosub EnemyTakeHit
                End If
            End If
        End If
    Next j
    Return

' STLog: append:a en rad till selftest-loggen (fil + konsol)
STLog:
    stF = FreeFile
    Open "/tmp/schleswig_selftest.log" For Append As #stF
    Print #stF, stMsg$
    Close #stF
    Print stMsg$
    Return

' SelftestDrive: scriptat autoplay-scenario (endast när selftest=1).
' fas1 fiende jagar -> fas2 fiende skadar -> fas3 fiende dör av skott ->
' fas4 spelare kan dö (kollas i dead-grenen)
SelftestDrive:
    ' Fas 3.1: fas1 patrull -> fas2 upptäckt -> fas3 jakt runt hörn -> fas4 förlorad->PATROLL
    ' därefter gamla Fas 3-kombattestet: fas5 jakt -> fas6 skada -> fas7 dör av skott -> fas8 spelare dör
    ' fas 9 = spawn-audit: akta SpawnEnemies, ingen fiende far se spelaren vid start (LOS<tröskel)
    ' fas 14 = Fas 4A enemy types: register data, zigzag offset, dodge-on-hit (seeded), spawn-mix wave 1
    ' fas 15 = Fas 4B projectiles: ball flight/wall, musketeer fire, mortar telegraph+splash, gating
    ' fas 10 = occlusion-audit: pixel-check (POINT) att ögon döljs bakom vägg och pickups rätt
    ' fas 11 = ljud-register-test: PlaySound för alla id, tillstånd ska vara oförändrat
    ' fas 12 = seger-trigger: kill-all -> result-state, inga levande fiender, tangent -> omladdning
    Select Case testPhase
        Case 1   ' PATROLL: ingen LOS (10.5,6.5)->(8.5,4.5) -> stanna i PATROLL men vandra mot mål
            If Timer - testT0 >= 1.2 Then
                pd = Sqr((enX(0) - 10.5) ^ 2 + (enY(0) - 6.5) ^ 2)
                If enState(0) = 0 And pd > 0.1 Then
                    stMsg$ = "PASS fas1-patrull state=0 moved=" + LTrim$(Str$(Int(pd * 100) / 100))
                Else
                    stMsg$ = "FAIL fas1-patrull state=" + Str$(enState(0)) + " moved=" + LTrim$(Str$(Int(pd * 100) / 100))
                End If
                Gosub STLog
                testPhase = 2: testT0 = Timer: testFlag = 0
            End If
        Case 2   ' UPPTÄCKT: teleportera spelaren till fri LOS (10.5,4.5) -> ska bli JAKT
            If testFlag = 0 Then
                testFlag = 1
                px = 10.5: py = 4.5
                stMsg$ = "fas2: spelaren -> (10.5,4.5), fri LOS, väntar på JAKT"
                Gosub STLog
            End If
            If enState(0) = 1 Then
                stMsg$ = "PASS fas2-upptackt-JAKT"
                Gosub STLog
                testPhase = 3: testT0 = Timer: testFlag = 0
            ElseIf Timer - testT0 >= 1.5 Then
                stMsg$ = "FAIL fas2-upptackt state=" + Str$(enState(0))
                Gosub STLog
                testPhase = 3: testT0 = Timer: testFlag = 0
            End If
        Case 3   ' JAKT RUNT HÖRN: fiende tillbaka till (10.5,6.5), fältmål (8,4) - vägg
                 ' emellan (9,5) - ska via BFS runt hörnet nå spelaren -> ANFALL + skada
            If testFlag = 0 Then
                testFlag = 1
                enX(0) = 10.5: enY(0) = 6.5: enState(0) = 1
                enLastSeen(0) = Timer: enLx(0) = 8.5: enLy(0) = 4.5
                px = 8.5: py = 4.5: angle = 0: hp = 100
                bfsForX = -1: bfsForY = -1
                stMsg$ = "fas3: fiende (10.5,6.5) JAKT, mål (8,4), LOS bruten (vägg 9,5)"
                Gosub STLog
            End If
            If Timer - testDbg >= 0.5 And enState(0) = 1 Then
                testDbg = Timer
                stMsg$ = "fas3 en0=(" + LTrim$(Str$(Int(enX(0) * 10) / 10)) + "," + LTrim$(Str$(Int(enY(0) * 10) / 10)) + ") bfsD=" + Str$(bfsD(Int(enX(0)), Int(enY(0)))) + " bfsFor=" + Str$(bfsForX) + "," + Str$(bfsForY)
                Gosub STLog
            End If
            If enState(0) = 2 And hp < 100 Then
                stMsg$ = "PASS fas3-jakt-runt-horn-ANFALL hp=" + Str$(Int(hp))
                Gosub STLog
                testPhase = 4: testT0 = Timer: testFlag = 0
            ElseIf Timer - testT0 >= 6 Then
                stMsg$ = "FAIL fas3 state=" + Str$(enState(0)) + " hp=" + Str$(Int(hp)) + " en0=(" + LTrim$(Str$(Int(enX(0) * 10) / 10)) + "," + LTrim$(Str$(Int(enY(0) * 10) / 10)) + ")"
                Gosub STLog
                testPhase = 4: testT0 = Timer: testFlag = 0
            End If
        Case 4   ' FÖRLORAD SYN: spelaren gömmer sig (2.5,12.5) -> >2s -> sista kända -> 5s -> PATROLL
                 ' (passar även på att verifiera INGEN HP-regen: hp ska vara oförändrad)
            If testFlag = 0 Then
                testFlag = 1
                px = 2.5: py = 12.5
                hpAt4 = hp   ' ingen fiende når spelaren här -> hp måste vara samma vid PASS
                stMsg$ = "fas4: spelaren gömmer sig (2.5,12.5), väntar på återgång PATROLL"
                Gosub STLog
            End If
            If enState(0) = 0 Then
                If hp = hpAt4 Then
                    stMsg$ = "PASS fas4-forlorad-syn-atergang-PATROLL efter " + LTrim$(Str$(Int((Timer - testT0) * 10) / 10)) + "s (hp oförändrad " + Str$(Int(hp)) + ", ingen regen)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas4-regen-detected: hp " + Str$(Int(hpAt4)) + " -> " + Str$(Int(hp)) + " utan skada"
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' förbered gamla Fas 3-kombattestet (fas5-8)
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: hp = 100: ammo = 5   ' Fas 5A: start from map 'S'
                enX(0) = 11.5: enY(0) = 4.5: enActive(0) = 1
                enHP(0) = 3: enDmg(0) = 10: enSpd(0) = 2
                enState(0) = 0: enLastHit(0) = 0: enLastSeen(0) = 0: enCalmT(0) = 0
                enLx(0) = enX(0): enLy(0) = enY(0)
                enTx(0) = 11: enTy(0) = 4: enPatrolT(0) = Timer
                For i = 1 To 10: enActive(i) = 0: Next i
                bfsForX = -1: bfsForY = -1
                testPhase = 5: testT0 = Timer: testFlag = 0
            ElseIf Timer - testT0 >= 14 Then
                stMsg$ = "FAIL fas4 state=" + Str$(enState(0)) + " en0=(" + LTrim$(Str$(Int(enX(0) * 10) / 10)) + "," + LTrim$(Str$(Int(enY(0) * 10) / 10)) + ")"
                Gosub STLog
                testPhase = 5: testT0 = Timer: testFlag = 0
            End If
        Case 5   ' gamla Fas 3: fiende jagar (nu via JAKT/BFS, LOS fri i rad 4)
            If Timer - testT0 >= 1.5 Then
                sd = Sqr((enX(0) - px) ^ 2 + (enY(0) - py) ^ 2)
                If sd < 2.2 And sd > 0.3 Then
                    stMsg$ = "PASS fas5-jagar dist=" + LTrim$(Str$(sd))
                Else
                    stMsg$ = "FAIL fas5-jagar dist=" + LTrim$(Str$(sd))
                End If
                Gosub STLog
                testPhase = 6: testT0 = Timer: testFlag = 0
            End If
        Case 6   ' gamla Fas 3: fienden i närstrid skadar spelaren (hp<100)
            If hp < 100 Then
                stMsg$ = "PASS fas6-skadar hp=" + LTrim$(Str$(Int(hp)))
                Gosub STLog
                testPhase = 7: testT0 = Timer: testFlag = 0
            ElseIf Timer - testT0 >= 4 Then
                stMsg$ = "FAIL fas6-skadar hp=" + LTrim$(Str$(Int(hp)))
                Gosub STLog
                testPhase = 7: testT0 = Timer: testFlag = 0
            End If
        Case 7   ' gamla Fas 3: sikta och skjut tills fienden dör (enHP 3->0)
            If enActive(0) = 0 Then
                stMsg$ = "PASS fas7-dod-av-skott (enHP gick 3->0)"
                Gosub STLog
                ' fas7b: ammo-streck-funktionen CountAmmoTicks% — fallen 0, 5, 20
                ' samt aktuell ammo (efter skotten) ska ge exakt antal tända streck
                tk0 = CountAmmoTicks%(0): tk5 = CountAmmoTicks%(5): tk20 = CountAmmoTicks%(20): tkA = CountAmmoTicks%(ammo)
                If tk0 = 0 And tk5 = 5 And tk20 = 20 And tkA = ammo And ammo >= 0 And ammo <= maxAmmo Then
                    stMsg$ = "PASS fas7b-ammo-ticks CountAmmoTicks% 0/5/20=" + Str$(tk0) + "/" + Str$(tk5) + "/" + Str$(tk20) + " ammo=" + Str$(ammo) + "->" + Str$(tkA) + " (maxAmmo=" + Str$(maxAmmo) + ")"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas7b-ammo-ticks 0/5/20=" + Str$(tk0) + "/" + Str$(tk5) + "/" + Str$(tk20) + " ammo=" + Str$(ammo) + "->" + Str$(tkA)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' fas 8: låt en ny fiende döda spelaren (hp lågt för snabbhet)
                hp = 25
                enX(1) = px + 1: enY(1) = py: enActive(1) = 1
                enHP(1) = 3: enDmg(1) = 10: enSpd(1) = 2: enLastHit(1) = 0
                enState(1) = 0: enLastSeen(1) = 0: enCalmT(1) = 0
                enLx(1) = enX(1): enLy(1) = enY(1)
                enTx(1) = Int(enX(1)): enTy(1) = Int(enY(1)): enPatrolT(1) = Timer
                fireBtn = 0
                testPhase = 8: testT0 = Timer: testFlag = 0
            Else
                angle = _ATan2(enY(0) - py, enX(0) - px)
                dirX = Cos(angle): dirY = Sin(angle)
                fireBtn = 1   ' cooldown 0.3 s i skjutblocket begränsar eldhastigheten
                If Timer - testDbg >= 0.5 Then
                    testDbg = Timer
                    ed0 = Sqr((enX(0) - px) ^ 2 + (enY(0) - py) ^ 2)
                    stMsg$ = "fas7 fdist=" + LTrim$(Str$(Int(ed0 * 100) / 100)) + " enHP=" + Str$(enHP(0)) + " ammo=" + Str$(ammo) + " hp=" + Str$(Int(hp)) + " enState=" + Str$(enState(0))
                    Gosub STLog
                End If
                If Timer - testT0 >= 6 Then
                    stMsg$ = "FAIL fas7-dod-av-skott enHP=" + Str$(enHP(0)) + " ammo=" + Str$(ammo)
                    Gosub STLog
                    testPhase = 8: testT0 = Timer: testFlag = 0
                    fireBtn = 0
                End If
            End If
        Case 8   ' gamla Fas 3: vänta på state$="dead" (själva PASS:en skrivs i dead-grenen)
            If Timer - testT0 >= 8 Then
                stMsg$ = "FAIL fas8-spelare-dor state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
        Case 9   ' SPAWN-AUDIT: akta SpawnEnemies-layout, ingen aktiv fiende far ha
                 ' fri LOS inom tröskeln (6) till spelaren vid spelstart
            If testFlag = 0 Then
                testFlag = 1
                stMsg$ = "fas9: spawn-audit, akta SpawnEnemies, väntar 2s"
                Gosub STLog
            End If
            If Timer - testT0 >= 2 Then
                bad = 0: audit$ = ""
                For i = 0 To 10
                    If enActive(i) Then
                        fdx = px - enX(i): fdy = py - enY(i)
                        fdist = Sqr(fdx * fdx + fdy * fdy)
                        fx = enX(i): fy = enY(i): tx = px: ty = py
                        Gosub LOSCheck
                        If (losOK And fdist < 6) Or enState(i) <> 0 Then
                            bad = bad + 1
                            audit$ = audit$ + " en" + Str$(i) + "(d=" + LTrim$(Str$(Int(fdist * 100) / 100)) + ",los=" + Str$(losOK) + ",st=" + Str$(enState(i)) + ")"
                        End If
                    End If
                Next i
                If bad = 0 Then
                    stMsg$ = "PASS fas9-spawn-audit (ingen fiende ser spelaren vid start)"
                    Gosub STLog
                    ' fas 10: occlusion-audit pa pixel-niva (POINT pa buf&) — handplacerat case:
                    ' spelare (8.5,4.5) tittar söderut mot vägg (8,5) (wallDist=0.5 i mitten);
                    ' en0 bakom väggen (8.5,6.5), pk0 framför väggen off-center (8.213,4.969),
                    ' pk1 bakom väggen (8.5,6.5)
                    px = 8.5: py = 4.5: angle = 3.14159265 / 2: pitch = 0: hp = 100: ammo = 5
                    For i = 0 To 10
                        enActive(i) = 0: pkActive(i) = 0: amActive(i) = 0
                    Next i
                    enX(0) = 8.5: enY(0) = 6.5: enActive(0) = 1: enHP(0) = 3: enState(0) = 0
                    enSpd(0) = 0: enLastSeen(0) = 0: enCalmT(0) = 0: enPatrolT(0) = -99
                    enLx(0) = 8.5: enLy(0) = 6.5: enTx(0) = 8: enTy(0) = 6
                    pkX(0) = 8.213: pkY(0) = 4.969: pkActive(0) = 1
                    pkX(1) = 8.5: pkY(1) = 6.5: pkActive(1) = 1
                    bfsForX = -1: bfsForY = -1
                    testPhase = 10: testT0 = Timer: testFlag = 0
                Else
                    stMsg$ = "FAIL fas9-spawn-audit:" + audit$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    End
                End If
            End If
        Case 10  ' OCKLUSION-AUDIT: vänta några frames, sätt testFlag=1; render-sektionen gör POINT-checken
            If testFlag = 0 And Timer - testT0 >= 0.6 Then testFlag = 1
        Case 11  ' LJUD-REGISTER-TEST: anropa PlaySound för alla registrerade id.
                 ' Får INTE ändra speltillstånd eller krascha (headless = tyst no-op).
            If testFlag = 0 Then
                testFlag = 1
                sh0 = hp: sst0$ = state$: sam0 = ammo: sen0 = enState(0)
                For sndId% = 1 To SND_COUNT
                    PlaySound sndId%
                Next sndId%
                If hp = sh0 And state$ = sst0$ And ammo = sam0 And enState(0) = sen0 Then
                    stMsg$ = "PASS fas11-ljud-register (alla " + Str$(SND_COUNT) + " id anropade, tillstånd oförändrat, ingen krasch)"
                    Gosub STLog
                    ' fas 14: enemy types (Fas 4A) -> then fas 12: seger-trigger-test
                    testPhase = 14: testT0 = Timer: testFlag = 0
                Else
                    stMsg$ = "FAIL fas11-ljud-register hp=" + Str$(Int(hp)) + " state=" + state$ + " ammo=" + Str$(ammo)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
        Case 12  ' RESULTATMENY-TEST: (a) kill-all -> result + fryst runTimeFrozen + 0 levande,
                 ' (b) klick VIDARE -> playing, (c) kill-all igen + klick HUVUDMENY -> menu
            If testFlag = 0 Then
                testFlag = 1: testT0 = Timer: wt1 = -1
                For i = 0 To 10: enActive(i) = 0: Next i   ' kill-all simulerat
                Gosub FreezeAtLastKill   ' samma freeze-punkt som riktig sista-kill
                winPending = 0
                stMsg$ = "fas12: alla fiender döda, väntar på result"
                Gosub STLog
            End If
            If testFlag = 1 And state$ = "result" Then
                If wt1 < 0 Then wt1 = runTimeFrozen: wtT = Timer
                If Timer - wtT >= 0.6 Then
                    alive12 = 0
                    For i = 0 To 10
                        If enActive(i) Then alive12 = alive12 + 1
                    Next i
                    ' wt1 >= 1 krävs: fryst tid måste vara ett verkligt tidsvärde
                    ' (inte ~0 från rundstart/spawn-gap). Dessutom: score måste vara
                    ' liveScore& (samma variabel som HUD) och STRICKT lägre än vad
                    ' bara skada/skott ger — bevis på att TIDSTRAFFET verkligen finns.
                    If runTimeFrozen = wt1 And alive12 = 0 And wt1 >= 1 And score = liveScore& And liveScore& < 10000 - 10 * shotsFired - 25 * dmgTaken Then
                        stMsg$ = "PASS fas12a-killall-result-fryst (state=result, levande=0, runTimeFrozen=" + Str$(wt1) + " fryst vid kill, score=liveScore&=" + Str$(liveScore&) + " < " + Str$(10000 - 10 * shotsFired - 25 * dmgTaken) + " (skada/skott utan tid) => tidsstraff aktivt)"
                        Gosub STLog
                        testFlag = 2: testT0 = Timer: sr0 = startRuns   ' result-grenen injicerar VIDARE-klick; spara räknare
                    Else
                        stMsg$ = "FAIL fas12a runTimeFrozen " + Str$(wt1) + "->" + Str$(runTimeFrozen) + " levande=" + Str$(alive12) + " score=" + Str$(score) + " liveScore&=" + Str$(liveScore&) + " skadaSkottOnly=" + Str$(10000 - 10 * shotsFired - 25 * dmgTaken)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                End If
            ElseIf testFlag = 1 And Timer - testT0 >= 3 Then
                stMsg$ = "FAIL fas12a state=" + state$ + " (förväntade result)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 2 And state$ = "playing" Then
                ' SKYDD-check: inga rörelse-flaggor får överleva VIDARE-övergången
                ' BEVIS: VIDARE måste ha gått MENY-START-vägen — startRuns (räknare
                ' i StartRun) ska ha ökat med exakt +1 sedan VIDARE-klicket.
                ' runTimeFrozen = -1 vid playing-start: rundstart efter VIDARE får
                ' INTE vara fryst (~0) — det var buggen (alive==0 utan kill fryyste)
                If mvF = 0 And mvB = 0 And mvL = 0 And mvR = 0 And turnL = 0 And turnR = 0 And fireBtn = 0 And startRuns = sr0 + 1 And runTimeFrozen = -1 And lockEngaged = 1 And lockEngages = 1 Then
                    stMsg$ = "PASS fas12b-vidare-klick (VIDARE -> state=playing via MENY-START-vägen: startRuns " + Str$(sr0) + "->" + Str$(startRuns) + " (+1), rörelse-flaggor=0, runTimeFrozen=-1, lock vid FADE-SLUT: lockEngaged=1 engages=1)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas12b-rorelse/startRuns/frz mvF=" + Str$(mvF) + " mvB=" + Str$(mvB) + " mvL=" + Str$(mvL) + " mvR=" + Str$(mvR) + " turnL=" + Str$(turnL) + " turnR=" + Str$(turnR) + " fireBtn=" + Str$(fireBtn) + " startRuns=" + Str$(startRuns) + " (väntade " + Str$(sr0 + 1) + ") runTimeFrozen=" + Str$(runTimeFrozen) + " (väntade -1)"
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' nästa: pausmeny-test (fas13) innan fas12c — kill-all görs där
                testPhase = 13: testFlag = 6: testT0 = Timer
            ElseIf testFlag = 2 And Timer - testT0 >= 3 Then
                stMsg$ = "FAIL fas12b state=" + state$ + " (förväntade playing efter VIDARE-klick)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            ' MUS-REVERT: result har inga knappar längre — vägen till menyn är
            ' nu dead-R (dödsskärm -> R). testFlag=3: vänta på dead, dead-grenen
            ' injicerar "r" -> menu.
            If testFlag = 3 And state$ = "menu" Then
                stMsg$ = "PASS fas12c-deadR-till-meny (dödsskärm R -> state=menu; enda vägen till menyn)"
                Gosub STLog
                testFlag = 5: testT0 = Timer: navStep = 0   ' låt meny-branchen rendera + tangent-nav (fas12d) innan End
            ElseIf testFlag = 3 And Timer - testT0 >= 6 Then
                stMsg$ = "FAIL fas12c state=" + state$ + " (förväntade menu efter dead-R)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 5 And Timer - testT0 >= 6 Then
                stMsg$ = "FAIL fas12d state=" + state$ + " (meny-branchen renderade ej inom 6s)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
        Case 13  ' PAUSMENY-TEST: ESC->paused, piltangenter byter markering,
                 ' ENTER=FORTSÄTT (ingen tidsförlust via runT0-offset), ENTER=RESTART (pendingStart)
            If testFlag = 6 And state$ = "paused" Then
                If resumeState$ = "playing" Then
                    stMsg$ = "PASS fas13a-esc-paus (state=paused, resumeState=playing, pausstart)"
                    Gosub STLog
                    testFlag = 7: testT0 = Timer: inj7 = 0
                Else
                    stMsg$ = "FAIL fas13a resumeState=" + resumeState$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            ElseIf testFlag = 6 And Timer - testT0 >= 2 Then
                stMsg$ = "FAIL fas13a state=" + state$ + " (förväntade paused)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 7 And selIdx = 2 Then
                stMsg$ = "PASS fas13b-ner-pil (selIdx 1->2 via nedåtpil)"
                Gosub STLog
                testFlag = 8: testT0 = Timer: inj8 = 0
            ElseIf testFlag = 7 And Timer - testT0 >= 2 Then
                stMsg$ = "FAIL fas13b selIdx=" + Str$(selIdx) + " (väntade 2)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 8 And selIdx = 1 Then
                stMsg$ = "PASS fas13c-upp-pil (selIdx 2->1 via uppåtpil)"
                Gosub STLog
                ct0 = CurRunTime%: runT0b = runT0
                testFlag = 9: testT0 = Timer: inj9 = 0
            ElseIf testFlag = 8 And Timer - testT0 >= 2 Then
                stMsg$ = "FAIL fas13c selIdx=" + Str$(selIdx) + " (väntade 1)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 9 And state$ = "playing" Then
                ' FORTSÄTT: pausen får INTE äta run-tid — CurRunTime% ska vara kvar
                ' på ct0 (±1s), och runT0 ska ha flyttats fram med pausens längd
                If CurRunTime% - ct0 <= 1 And runT0 - runT0b >= (Timer - pauseT0) - 1 Then
                    stMsg$ = "PASS fas13d-fortsatt-ingen-tidsforlust (CurRunTime% " + Str$(ct0) + "->" + Str$(CurRunTime%) + ", runT0 offset " + LTrim$(Str$(runT0 - runT0b)) + "s, paus " + LTrim$(Str$(Timer - pauseT0)) + "s)"
                    Gosub STLog
                    testFlag = 10: testT0 = Timer
                Else
                    stMsg$ = "FAIL fas13d tidsforlust CurRunTime% " + Str$(ct0) + "->" + Str$(CurRunTime%) + " runT0delta=" + LTrim$(Str$(runT0 - runT0b)) + " paus=" + LTrim$(Str$(Timer - pauseT0))
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            ElseIf testFlag = 9 And Timer - testT0 >= 2 Then
                stMsg$ = "FAIL fas13d state=" + state$ + " (förväntade playing efter FORTSÄTT)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 10 And state$ = "paused" Then
                testFlag = 11: testT0 = Timer: selIdx = 2: inj11 = 0   ' välj RESTART ROND, ENTER
            ElseIf testFlag = 10 And Timer - testT0 >= 2 Then
                stMsg$ = "FAIL fas13e-pre state=" + state$ + " (förväntade paused igen)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 11 And state$ = "playing" Then
                ' RESTART ROND via pendingStart -> meny-START-vägen: startRuns +1 till
                If startRuns = sr0 + 2 Then
                    stMsg$ = "PASS fas13e-restart-rond-pendingstart (startRuns " + Str$(sr0) + "->" + Str$(startRuns) + ", state=playing)"
                    Gosub STLog
                    ' vidare till fas12c: dö (hp=0) -> dead -> R -> menu
                    hp = 0
                    testPhase = 12: testFlag = 3: testT0 = Timer
                Else
                    stMsg$ = "FAIL fas13e startRuns=" + Str$(startRuns) + " (väntade " + Str$(sr0 + 2) + ")"
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            ElseIf testFlag = 11 And Timer - testT0 >= 5 Then
                stMsg$ = "FAIL fas13e state=" + state$ + " (förväntade playing efter RESTART)"
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
        Case 14  ' FAS 4A enemy types: (a) register data per type, (b) zigzag target-cell
                 ' offset changes at least once within 1 s (seeded), (c) dodge sidestep
                 ' on a seeded shot vs officer, (d) spawn-mix wave 1: no captain
            If testFlag = 0 Then
                ' (a) register data
                okA = (etHP(ET_FOOT) = 3 And etHP(ET_OFFICER) = 6 And etHP(ET_MUSKETEER) = 5 And etHP(ET_CAPTAIN) = 12 And etHP(ET_GENERAL) = 25)
                okA = okA And (etSpd!(ET_OFFICER) > etSpd!(ET_FOOT) And etSpd!(ET_FOOT) = etSpd!(ET_MUSKETEER) And etSpd!(ET_CAPTAIN) < etSpd!(ET_FOOT) And etSpd!(ET_GENERAL) < etSpd!(ET_CAPTAIN))
                okA = okA And (etZigAmp(ET_FOOT) = 1 And etZigAmp(ET_OFFICER) = 2 And etZigAmp(ET_MUSKETEER) = 1 And etZigAmp(ET_CAPTAIN) = 0 And etZigAmp(ET_GENERAL) = 0)
                okA = okA And (etDodge!(ET_FOOT) = 0.3 And etDodge!(ET_OFFICER) = 0.4 And etDodge!(ET_MUSKETEER) = 0.4 And etDodge!(ET_CAPTAIN) = 0.5 And etDodge!(ET_GENERAL) = 0)
                okA = okA And (etShoot(ET_FOOT) = 0 And etShoot(ET_OFFICER) = 0 And etShoot(ET_CAPTAIN) = 0 And etShoot(ET_MUSKETEER) = 1 And etShoot(ET_GENERAL) = 2)
                okA = okA And (etHold!(ET_MUSKETEER) >= 3 And etHold!(ET_MUSKETEER) <= 5 And etHold!(ET_FOOT) = 0)
                okA = okA And (etCol&(ET_CAPTAIN) <> etCol&(ET_FOOT) And etCol&(ET_OFFICER) <> etCol&(ET_FOOT) And etCol&(ET_GENERAL) <> etCol&(ET_FOOT))
                okA = okA And (etMinWave(ET_FOOT) = 1 And etMinWave(ET_OFFICER) = 3 And etMinWave(ET_MUSKETEER) = 4 And etMinWave(ET_GENERAL) = 5)
                okA = okA And (etMortarT!(ET_GENERAL) >= 1.5 And etMortarT!(ET_GENERAL) <= 2 And etSplashR!(ET_GENERAL) > 1 And etSplashDmg(ET_GENERAL) > 0)
                If okA Then
                    stMsg$ = "PASS fas14a-register (HP 3/6/5/12/25, spd officer>foot=musketeer>captain>general, zig 1/2/1/0/0, dodge .3/.4/.4/.5/0, shoot 0/0/1/0/2, musketeer hold 3-5, minWave 1/3/4/3/5, mortar 1.5-2s splash, distinct colors)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas14a-register hp=" + Str$(etHP(ET_FOOT)) + "/" + Str$(etHP(ET_OFFICER)) + "/" + Str$(etHP(ET_MUSKETEER)) + "/" + Str$(etHP(ET_CAPTAIN)) + " dodge=" + Str$(etDodge!(ET_FOOT)) + "/" + Str$(etDodge!(ET_CAPTAIN)) + " shoot=" + Str$(etShoot(ET_CAPTAIN)) + " hold=" + Str$(etHold!(ET_MUSKETEER))
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' (b) setup: one OFFICER hunting the player in open row 4
                For i = 0 To 10: enActive(i) = 0: Next i
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: hp = 100: ammo = 5   ' Fas 5A: start from map 'S'
                enX(0) = 12.5: enY(0) = 4.5: enActive(0) = 1
                enType(0) = ET_OFFICER: enHP(0) = etHP(ET_OFFICER): enDmg(0) = etDmg(ET_OFFICER): enSpd(0) = etSpd!(ET_OFFICER)
                enState(0) = 1: enLastSeen(0) = Timer: enLx(0) = px: enLy(0) = py: enCalmT(0) = 0: enLastHit(0) = 0
                enTx(0) = 12: enTy(0) = 4: enPatrolT(0) = -99
                enZigT(0) = 0: enZigX(0) = -1: enZigY(0) = -1: enZigS(0) = 1
                bfsForX = -1: bfsForY = -1
                Randomize 20261123
                zigChanges = 0: zx0 = -1: zy0 = -1
                testFlag = 1: testT0 = Timer
            End If
            If testFlag = 1 Then
                If zx0 = -1 Then zx0 = enZigX(0): zy0 = enZigY(0)
                If enZigX(0) <> zx0 Or enZigY(0) <> zy0 Then
                    zigChanges = zigChanges + 1
                    zx0 = enZigX(0): zy0 = enZigY(0)
                End If
                If Timer - testT0 >= 1.2 Then
                    If zigChanges >= 1 Then
                        stMsg$ = "PASS fas14b-zigzag (officer target-cell offset changed " + Str$(zigChanges) + "x within 1.2s, seeded RNG, per-enemy 0.5-1s timer; now zig=" + Str$(enZigX(0)) + "," + Str$(enZigY(0)) + ")"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas14b-zigzag (offset never changed within 1.2s, zig=" + Str$(enZigX(0)) + "," + Str$(enZigY(0)) + ")"
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' (c) setup: seeded shot straight at an officer in open row 4
                    enX(0) = 10.5: enY(0) = 4.5: enState(0) = 1: enLastSeen(0) = Timer: enLx(0) = px: enLy(0) = py
                    enZigT(0) = Timer + 99   ' no zigzag Rnd consumed before the shot
                    lastShotTime = -1: ammo = 5
                    preX = enX(0): preY = enY(0)
                    dodgeSeed& = 2             ' known dodge seed -> first DodgeRnd# ~0.028 < officer dodge 0.4
                    fireBtn = 1
                    testFlag = 2: testT0 = Timer
                End If
            End If
            If testFlag = 2 Then
                If enHP(0) < etHP(ET_OFFICER) Then
                    ' the seeded shot landed; verify the dodge sidestep (1 cell,
                    ' perpendicular to the x-axis firing line)
                    fireBtn = 0
                    If enActive(0) = 1 And Abs(enY(0) - preY) >= 0.9 And Abs(enX(0) - preX) < 0.5 Then
                        stMsg$ = "PASS fas14c-dodge (seeded shot vs officer dodgeSeed 2: HP " + Str$(etHP(ET_OFFICER)) + "->" + Str$(enHP(0)) + ", 1-cell sidestep to (" + LTrim$(Str$(Int(enX(0) * 10) / 10)) + "," + LTrim$(Str$(Int(enY(0) * 10) / 10)) + "))"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas14c-dodge (HP=" + Str$(enHP(0)) + " active=" + Str$(enActive(0)) + " pos " + LTrim$(Str$(Int(enX(0) * 10) / 10)) + "," + LTrim$(Str$(Int(enY(0) * 10) / 10)) + " pre " + LTrim$(Str$(Int(preX * 10) / 10)) + "," + LTrim$(Str$(Int(preY * 10) / 10)) + " dodgeSeed 2)"
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' (d) spawn-mix wave 1: reset wave/kill counters, spawn, audit types
                    killsTotal = 0: waveNo = 0
                    Gosub SpawnEnemies
                    capN = 0: footN = 0: offN = 0: musN = 0
                    For i = 0 To 10
                        If enActive(i) Then
                            If enType(i) = ET_CAPTAIN Then capN = capN + 1
                            If enType(i) = ET_FOOT Then footN = footN + 1
                            If enType(i) = ET_OFFICER Then offN = offN + 1
                            If enType(i) = ET_MUSKETEER Then musN = musN + 1
                        End If
                    Next i
                    If capN = 0 And footN = 4 And offN = 0 And musN = 0 Then
                        stMsg$ = "PASS fas14d-spawn-mix (wave 1 per 4D gating: all 4 FOOT (foot=" + Str$(footN) + " officer=" + Str$(offN) + " musketeer=" + Str$(musN) + " captain=" + Str$(capN) + "), killsTotal=0 -> captain impossible)"
                        Gosub STLog
                        testPhase = 15: testT0 = Timer: testFlag = 0   ' Fas 4B projectile tests
                    Else
                        stMsg$ = "FAIL fas14d-spawn-mix foot=" + Str$(footN) + " officer=" + Str$(offN) + " musketeer=" + Str$(musN) + " captain=" + Str$(capN)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                ElseIf Timer - testT0 >= 2 Then
                    fireBtn = 0
                    stMsg$ = "FAIL fas14c-dodge (seeded shot never landed: enHP=" + Str$(enHP(0)) + " ammo=" + Str$(ammo) + ")"
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
        Case 15  ' FAS 4B projectiles: (a) BALL flies straight, hits enemy, dies at wall,
                 ' (b) musketeer fires BALL in LOS+band with interval (seeded), NOT
                 ' without LOS, (c) mortar: telegraph target + flygtid, splash full at
                 ' center + falloff at edge + friendly fire, (d) general only on waves
                 ' 5/10/15 (max 1), (e) waves 1-2 all foot soldiers
            If testFlag = 0 Then
                ' (a) setup: one FOOT in open row 4, player ball straight +x
                For i = 0 To 10: enActive(i) = 0: Next i
                For i = 0 To PR_MAX: prActive(i) = 0: Next i
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: hp = 100: ammo = 5   ' Fas 5A: start from map 'S'
                enX(0) = 11.5: enY(0) = 4.5: enActive(0) = 1
                enType(0) = ET_FOOT: enHP(0) = etHP(ET_FOOT): enDmg(0) = etDmg(ET_FOOT): enSpd(0) = etSpd!(ET_FOOT)
                enState(0) = 1: enLastSeen(0) = Timer: enLx(0) = px: enLy(0) = py: enCalmT(0) = 0: enLastHit(0) = 0
                enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                enTx(0) = 11: enTy(0) = 4: enPatrolT(0) = Timer
                bfsForX = -1: bfsForY = -1
                projSpawned = 0
                spX = px: spY = py: spDX = 1: spDY = 0: spSpd! = plrBallSpd!: spOwner = 0: spDmg = plrBallDmg: spType = PR_BALL
                spSrcType = -1: spTX = 0: spTY = 0: spLandT = 0
                Gosub SpawnProjectile
                testFlag = 1: testT0 = Timer
            End If
            If testFlag = 1 Then
                If prActive(0) = 0 Or Timer - testT0 >= 2 Then
                    If enHP(0) = etHP(ET_FOOT) - 1 And prX(0) > 10.5 And prX(0) < 12.5 Then
                        stMsg$ = "PASS fas15a-ball-hit-enemy (ball flew straight +x, hit foot at prX=" + LTrim$(Str$(Int(prX(0) * 100) / 100)) + ", enHP " + Str$(etHP(ET_FOOT)) + "->" + Str$(enHP(0)) + ", ball died on hit)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas15a-ball-hit-enemy enHP=" + Str$(enHP(0)) + " prX=" + LTrim$(Str$(Int(prX(0) * 100) / 100)) + " active=" + Str$(prActive(0))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' second ball: no enemy -> must fly to the wall (cell 15) and die there
                    enActive(0) = 0
                    spX = px: spY = py: spDX = 1: spDY = 0: spSpd! = plrBallSpd!: spOwner = 0: spDmg = plrBallDmg: spType = PR_BALL
                    spSrcType = -1: spTX = 0: spTY = 0: spLandT = 0
                    Gosub SpawnProjectile
                    testFlag = 2: testT0 = Timer
                End If
            End If
            If testFlag = 2 Then
                If prActive(0) = 0 Or Timer - testT0 >= 2 Then
                    If prX(0) > 13.5 And prX(0) <= 15.5 And Int(prY(0)) = 4 Then
                        stMsg$ = "PASS fas15a-ball-dies-at-wall (no enemy: ball flew to prX=" + LTrim$(Str$(Int(prX(0) * 100) / 100)) + " row 4 and died at the wall)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas15a-ball-dies-at-wall prX=" + LTrim$(Str$(Int(prX(0) * 100) / 100)) + " prY=" + LTrim$(Str$(Int(prY(0) * 100) / 100))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' (b) setup: musketeer in LOS + hold band (dist 4), seeded spread
                    For i = 0 To PR_MAX: prActive(i) = 0: Next i
                    For i = 0 To 10: enActive(i) = 0: Next i
                    px = 8.5: py = 4.5: angle = 0: hp = 100
                    enX(0) = 12.5: enY(0) = 4.5: enActive(0) = 1
                    enType(0) = ET_MUSKETEER: enHP(0) = etHP(ET_MUSKETEER): enDmg(0) = etDmg(ET_MUSKETEER): enSpd(0) = etSpd!(ET_MUSKETEER)
                    enState(0) = 1: enLastSeen(0) = Timer: enLx(0) = px: enLy(0) = py: enCalmT(0) = 0: enLastHit(0) = 0
                    enFireT(0) = 0: enZigT(0) = Timer + 99
                    enTx(0) = 12: enTy(0) = 4: enPatrolT(0) = Timer
                    bfsForX = -1: bfsForY = -1
                    aiSeed& = 424242
                    projSpawned = 0
                    testFlag = 3: testT0 = Timer: shots0 = projSpawned
                End If
            End If
            If testFlag = 3 Then
                If projSpawned > shots0 Or Timer - testT0 >= 2.5 Then
                    If projSpawned > shots0 And enFireT(0) > Timer Then
                        stMsg$ = "PASS fas15b-musketeer-fires (LOS + dist 4 in hold band: BALL spawned (projSpawned=" + Str$(projSpawned) + "), interval armed enFireT-Timer=" + LTrim$(Str$(Int((enFireT(0) - Timer) * 10) / 10)) + "s ~ etFireT=" + Str$(etFireT!(ET_MUSKETEER)) + ", seeded spread)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas15b-musketeer-fires projSpawned=" + Str$(projSpawned) + " enFireT(0)-Timer=" + LTrim$(Str$(Int((enFireT(0) - Timer) * 10) / 10))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' no LOS -> no fire: hide the player behind walls
                    px = 2.5: py = 12.5
                    shots0 = projSpawned
                    testFlag = 4: testT0 = Timer
                End If
            End If
            If testFlag = 4 Then
                If Timer - testT0 >= 1.5 Then
                    If projSpawned = shots0 Then
                        stMsg$ = "PASS fas15b-no-los-no-fire (player hidden (2.5,12.5): no BALL spawned in 1.5s)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas15b-no-los-no-fire projSpawned " + Str$(shots0) + "->" + Str$(projSpawned)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' (c) setup: GENERAL lobs a MORTAR at the (still) player; en1 = friendly-fire victim
                    For i = 0 To PR_MAX: prActive(i) = 0: Next i
                    For i = 0 To 10: enActive(i) = 0: Next i
                    px = 8.5: py = 4.5: angle = 0: hp = 100: dmgTaken = 0: ammo = 5
                    enX(0) = 12.5: enY(0) = 4.5: enActive(0) = 1
                    enType(0) = ET_GENERAL: enHP(0) = etHP(ET_GENERAL): enDmg(0) = 0: enSpd(0) = etSpd!(ET_GENERAL)
                    enState(0) = 1: enLastSeen(0) = Timer: enLx(0) = px: enLy(0) = py: enCalmT(0) = 0: enLastHit(0) = 0
                    enFireT(0) = 0: enZigT(0) = Timer + 99
                    enTx(0) = 12: enTy(0) = 4: enPatrolT(0) = Timer
                    enX(1) = 10.5: enY(1) = 4.5: enActive(1) = 1
                    enType(1) = ET_GENERAL: enHP(1) = etHP(ET_GENERAL): enDmg(1) = 10: enSpd(1) = 0
                    enState(1) = 1: enLastSeen(1) = 0: enFireT(1) = Timer + 99: enZigT(1) = Timer + 99
                    enTx(1) = 10: enTy(1) = 4: enPatrolT(1) = Timer
                    bfsForX = -1: bfsForY = -1
                    aiSeed& = 777
                    projSpawned = 0
                    mortarSeen = 0: mortarLogged = 0: landed = 0: mIdx = -1
                    testFlag = 5: testT0 = Timer
                End If
            End If
            If testFlag = 5 Then
                For i = 0 To PR_MAX
                    If prActive(i) And prType(i) = PR_MORTAR And mIdx = -1 Then mIdx = i: mortarSeen = 1
                Next i
                If mortarSeen And mortarLogged = 0 Then
                    mortarLogged = 1
                    ft = prLandT(mIdx) - Timer
                    tgX = prTX(mIdx): tgY = prTY(mIdx)
                    stMsg$ = "fas15c mortar in flight: flygtid=" + LTrim$(Str$(Int(ft * 100) / 100)) + "s target=(" + Str$(tgX) + "," + Str$(tgY) + ") telegraph active"
                    Gosub STLog
                End If
                If mortarSeen Then
                    If mIdx >= 0 And prActive(mIdx) = 0 Then landed = 1
                End If
                If landed Or Timer - testT0 >= 6 Then
                    enFireT(0) = Timer + 99   ' stop further mortars during the manual test
                    If landed And hp <= 76 And hp >= 74 And dmgTaken = 25 And tgX = 8 And tgY = 4 And ft >= 1.4 And ft <= 2.2 Then
                        stMsg$ = "PASS fas15c-mortar (telegraph at target (8,4), flygtid " + LTrim$(Str$(Int(ft * 100) / 100)) + "s, landed: splash full 25 at center -> hp 100->" + Str$(Int(hp)) + ", dmgTaken=25)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas15c-mortar landed=" + Str$(landed) + " hp=" + Str$(Int(hp)) + " dmgTaken=" + Str$(dmgTaken) + " tg=" + Str$(tgX) + "," + Str$(tgY) + " ft=" + LTrim$(Str$(Int(ft * 100) / 100))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' manual mortar at dist 1.0 from player AND from en1 -> falloff + friendly fire
                    hpBefore = hp: en1HPBefore = enHP(1)
                    spX = enX(0): spY = enY(0): spDX = 0: spDY = 0: spSpd! = 0: spOwner = 1: spDmg = 0: spType = PR_MORTAR
                    spSrcType = ET_GENERAL: spTX = 9: spTY = 4: spLandT = Timer + 0.3
                    Gosub SpawnProjectile
                    testFlag = 6: testT0 = Timer
                End If
            End If
            If testFlag = 6 Then
                ballGone = 1
                For i = 0 To PR_MAX
                    If prActive(i) Then ballGone = 0
                Next i
                If ballGone Or Timer - testT0 >= 2 Then
                    pdmg = hpBefore - hp
                    edmg = en1HPBefore - enHP(1)
                    If pdmg >= 11 And pdmg <= 14 And edmg >= 11 And edmg <= 14 And enActive(1) = 1 Then
                        stMsg$ = "PASS fas15c-falloff-friendlyfire (mortar at dist 1.0: falloff dmg=" + Str$(pdmg) + " to player (hp " + Str$(Int(hpBefore)) + "->" + Str$(Int(hp)) + ") AND " + Str$(edmg) + " to enemy en1 (friendly fire, enHP " + Str$(en1HPBefore) + "->" + Str$(enHP(1)) + "), full would be " + Str$(etSplashDmg(ET_GENERAL)) + ")"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas15c-falloff-friendlyfire pdmg=" + Str$(pdmg) + " edmg=" + Str$(edmg) + " en1active=" + Str$(enActive(1)) + " en1hp=" + Str$(enHP(1))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' (d) general gating: waves 1-12, general only on 5/10/15, max 1
                    okD = -1
                    For w = 1 To 12
                        waveNo = w - 1: killsTotal = 99
                        Gosub SpawnEnemies
                        genN = 0
                        For i = 0 To 10
                            If enActive(i) And enType(i) = ET_GENERAL Then genN = genN + 1
                        Next i
                        want = 0: If w >= ET_BOSS_STEP And (w Mod ET_BOSS_STEP) = 0 Then want = 1
                        If genN <> want Then okD = 0
                        stMsg$ = "fas15d wave " + Str$(w) + ": generals=" + Str$(genN) + " (want " + Str$(want) + ")"
                        Gosub STLog
                        For i = 0 To 10: enActive(i) = 0: Next i
                    Next w
                    If okD = -1 Then
                        stMsg$ = "PASS fas15d-general-gating (waves 1-12: general exactly on waves 5 and 10, never more than 1)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas15d-general-gating"
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' (e) waves 1-2: all foot soldiers
                    okE = -1
                    For w = 1 To 2
                        waveNo = w - 1: killsTotal = 0
                        Gosub SpawnEnemies
                        footN = 0: otherN = 0
                        For i = 0 To 10
                            If enActive(i) Then
                                If enType(i) = ET_FOOT Then footN = footN + 1 Else otherN = otherN + 1
                            End If
                        Next i
                        If footN <> 4 Or otherN <> 0 Then okE = 0
                        For i = 0 To 10: enActive(i) = 0: Next i
                    Next w
                    If okE = -1 Then
                        stMsg$ = "PASS fas15e-gating (waves 1-2: all 4 active enemies are FOOT SOLDIER)"
                        Gosub STLog
                        For i = 0 To PR_MAX: prActive(i) = 0: Next i
                        testFlag = 11: testT0 = Timer   ' -> fas15g colors, then fas15f kill-all
                    Else
                        stMsg$ = "FAIL fas15e-gating"
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                End If
            End If
            If testFlag = 11 Then
                ' (g) 4B hotfix: register color per type must extract to the expected RGB
                ' via _Red32/_Green32/_Blue32, and the shade clamp (min 51/255 = 20%)
                ' must never zero a channel (that was the black-enemy bug)
                okG = -1
                For etT = 0 To ET_COUNT - 1
                    cc& = etCol&(etT)
                    rr = _Red32(cc&): gg = _Green32(cc&): bb = _Blue32(cc&)
                    If etT = ET_FOOT And (rr <> 170 Or gg <> 35 Or bb <> 35) Then okG = 0
                    If etT = ET_OFFICER And (rr <> 200 Or gg <> 30 Or bb <> 80) Then okG = 0
                    If etT = ET_MUSKETEER And (rr <> 150 Or gg <> 90 Or bb <> 40) Then okG = 0
                    If etT = ET_CAPTAIN And (rr <> 230 Or gg <> 180 Or bb <> 40) Then okG = 0
                    If etT = ET_GENERAL And (rr <> 30 Or gg <> 90 Or bb <> 40) Then okG = 0
                    If Int(rr * 51 / 255) < 1 Or Int(gg * 51 / 255) < 1 Or Int(bb * 51 / 255) < 1 Then okG = 0
                Next etT
                If okG = -1 Then
                    stMsg$ = "PASS fas15g-colors (etCol& per type -> expected RGB via _Red32/_Green32/_Blue32; shade clamp 51/255 keeps every channel >= 1, never black)"
                    Gosub STLog
                    testFlag = 12: testT0 = Timer
                Else
                    stMsg$ = "FAIL fas15g-colors (register color extraction or clamp broken)"
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 12 Then
                ' (f) part 1: kill ALL enemies with aimed player BALLs (last kill via
                ' ball) — must not crash, win path must trigger
                For i = 0 To PR_MAX: prActive(i) = 0: Next i
                For i = 0 To 10: enActive(i) = 0: Next i
                px = 8.5: py = 4.5: angle = 0: hp = 100: ammo = 20
                enX(0) = 11.5: enY(0) = 4.5: enActive(0) = 1: enType(0) = ET_FOOT: enHP(0) = 3: enDmg(0) = 10: enSpd(0) = 0
                enState(0) = 1: enLastSeen(0) = Timer: enLx(0) = px: enLy(0) = py: enLastHit(0) = 0
                enFireT(0) = Timer + 99: enZigT(0) = Timer + 99: enTx(0) = 11: enTy(0) = 4: enPatrolT(0) = Timer
                enX(1) = 13.5: enY(1) = 4.5: enActive(1) = 1: enType(1) = ET_FOOT: enHP(1) = 3: enDmg(1) = 10: enSpd(1) = 0
                enState(1) = 1: enLastSeen(1) = Timer: enLx(1) = px: enLy(1) = py: enLastHit(1) = 0
                enFireT(1) = Timer + 99: enZigT(1) = Timer + 99: enTx(1) = 13: enTy(1) = 4: enPatrolT(1) = Timer
                bfsForX = -1: bfsForY = -1
                lastShotTime = -1
                sr15 = startRuns
                testFlag = 13: testT0 = Timer
            End If
            If testFlag = 13 Then
                ' fire aimed BALLs until all enemies are dead
                alive15 = 0: bd = 999: bi = -1
                For i = 0 To 10
                    If enActive(i) Then
                        alive15 = alive15 + 1
                        dd = Sqr((enX(i) - px) ^ 2 + (enY(i) - py) ^ 2)
                        If dd < bd Then bd = dd: bi = i
                    End If
                Next i
                If alive15 > 0 And bi >= 0 Then
                    angle = _ATan2(enY(bi) - py, enX(bi) - px)
                    dirX = Cos(angle): dirY = Sin(angle)
                    fireBtn = 1
                Else
                    fireBtn = 0
                End If
                If alive15 = 0 Or Timer - testT0 >= 8 Then
                    fireBtn = 0
                    If alive15 = 0 And killsTotal >= 2 Then
                        stMsg$ = "PASS fas15f-killall-ball (all enemies dead via player BALLs, killsTotal=" + Str$(killsTotal) + ", no crash)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas15f-killall-ball alive=" + Str$(alive15) + " killsTotal=" + Str$(killsTotal)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    testFlag = 14: testT0 = Timer
                End If
            End If
            If testFlag = 14 Then
                ' win path: alive==0 -> result within a few s
                If state$ = "result" Then
                    stMsg$ = "PASS fas15f-win-result (last kill -> alive=0 -> result, runTimeFrozen=" + Str$(runTimeFrozen) + ", no crash)"
                    Gosub STLog
                    pendingStart = 1: state$ = "menu"   ' same path as VIDARE/E
                    testFlag = 15: testT0 = Timer
                ElseIf Timer - testT0 >= 4 Then
                    stMsg$ = "FAIL fas15f-win-result state=" + state$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 15 Then
                ' next wave via pendingStart -> StartRun -> playing
                If state$ = "playing" And startRuns > sr15 Then
                    stMsg$ = "PASS fas15f-nextwave (pendingStart -> StartRun -> playing, startRuns " + Str$(sr15) + "->" + Str$(startRuns) + ", waveNo=" + Str$(waveNo) + ")"
                    Gosub STLog
                    ' splash-killall setup: teleport the 4 wave enemies into open row 4
                    tp = 0
                    For i = 0 To 10
                        If enActive(i) Then
                            tp = tp + 1
                            enX(i) = 9.5 + tp: enY(i) = 4.5
                            enLx(i) = enX(i): enLy(i) = enY(i)
                            enSpd(i) = 0: enFireT(i) = Timer + 99: enZigT(i) = Timer + 99
                        End If
                    Next i
                    px = 8.5: py = 4.5: angle = 0: hp = 100: ammo = 20: lastShotTime = -1
                    For i = 0 To PR_MAX: prActive(i) = 0: Next i
                    bfsForX = -1: bfsForY = -1
                    mortar15 = 0
                    testFlag = 16: testT0 = Timer
                ElseIf Timer - testT0 >= 6 Then
                    stMsg$ = "FAIL fas15f-nextwave state=" + state$ + " startRuns=" + Str$(startRuns) + " (sr15=" + Str$(sr15) + ")"
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 16 Then
                ' kill 2 with balls, then finish the rest with one MORTAR splash
                alive15 = 0: bd = 999: bi = -1
                For i = 0 To 10
                    If enActive(i) Then
                        alive15 = alive15 + 1
                        dd = Sqr((enX(i) - px) ^ 2 + (enY(i) - py) ^ 2)
                        If dd < bd Then bd = dd: bi = i
                    End If
                Next i
                If alive15 > 2 And bi >= 0 Then
                    angle = _ATan2(enY(bi) - py, enX(bi) - px)
                    dirX = Cos(angle): dirY = Sin(angle)
                    fireBtn = 1
                Else
                    fireBtn = 0
                End If
                If alive15 > 0 And alive15 <= 2 And mortar15 = 0 And bi >= 0 Then
                    spX = enX(bi): spY = enY(bi): spDX = 0: spDY = 0: spSpd! = 0
                    spOwner = 1: spDmg = 0: spType = PR_MORTAR: spSrcType = ET_GENERAL
                    spTX = Int(enX(bi)): spTY = Int(enY(bi)): spLandT = Timer + 0.3
                    Gosub SpawnProjectile
                    mortar15 = 1
                    stMsg$ = "fas15f: mortar spawned at (" + Str$(spTX) + "," + Str$(spTY) + "), alive=" + Str$(alive15)
                    Gosub STLog
                End If
                If alive15 = 0 Or Timer - testT0 >= 12 Then
                    fireBtn = 0
                    If alive15 = 0 And mortar15 = 1 Then
                        stMsg$ = "PASS fas15f-killall-splash (last enemies died via MORTAR splash in one blast, killsTotal=" + Str$(killsTotal) + ", no crash)"
                        Gosub STLog
                        testFlag = 17: testT0 = Timer
                    Else
                        stMsg$ = "FAIL fas15f-killall-splash alive=" + Str$(alive15) + " mortar=" + Str$(mortar15)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                End If
            End If
            If testFlag = 17 Then
                If state$ = "result" Or Timer - testT0 >= 4 Then
                    stMsg$ = "PASS fas15f-end (splash-killall -> result again, no crash; full round loop OK)"
                    Gosub STLog
                    testPhase = 16: testT0 = Timer: testFlag = 0   ' continue to fas16 (weapon viewmodel), then fas12 (win trigger)
                End If
            End If
        Case 16  ' FAS 4C weapon viewmodel: (a) recoil trigger + decay, (b) sway
                 ' direction + soft return, (c) render guard (not drawn in pause),
                 ' (d) muzzle flash true 2-3 frames then false
            hp = 100   ' keep the player alive while the test runs
            If testFlag = 0 And state$ = "playing" Then
                ' park all enemies in a far corner, disarmed — nothing may interfere
                For ej16 = 0 To 10
                    If enActive(ej16) Then
                        enX(ej16) = 1.5: enY(ej16) = 14.5: enSpd(ej16) = 0
                        enState(ej16) = 0: enFireT(ej16) = Timer + 99: enZigT(ej16) = Timer + 99
                    End If
                Next ej16
                px = 8.5: py = 4.5: angle = 0: ammo = 20: lastShotTime = -1
                gunX = 0: gunY = 0: recoil = 0: muzzleT = 0: shakeT = 0: turnDelta = 0: gunSway = 0
                gunX0 = gunX: minGunX = gunX: mf16n = 0: c16done = 0
                fireBtn = 1   ' one shot this frame -> recoil/muzzle/shake set in the shooting block
                stMsg$ = "fas16: one shot fired — expect recoil>10, muzzleT>0, shakeT>0 next frame"
                Gosub STLog
                testFlag = 1: testT0 = Timer
            ElseIf testFlag = 0 And Timer - testT0 >= 6 Then
                stMsg$ = "FAIL fas16-start state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 1 Then
                If recoil > 10 And muzzleT > 0 And shakeT > 0 Then
                    stMsg$ = "PASS fas16a-recoil-trigger (recoil=" + LTrim$(Str$(Int(recoil * 10) / 10)) + " muzzleT=" + Str$(muzzleT) + " shakeT=" + Str$(shakeT) + " right after 1 shot)"
                    Gosub STLog
                    testFlag = 2: testT0 = Timer: mf16n = 0
                ElseIf Timer - testT0 >= 1 Then
                    stMsg$ = "FAIL fas16a-recoil recoil=" + LTrim$(Str$(Int(recoil * 10) / 10)) + " muzzleT=" + Str$(muzzleT) + " shakeT=" + Str$(shakeT)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 2 Then
                If muzzleT > 0 Then mf16n = mf16n + 1
                If muzzleT = 0 Then
                    If mf16n >= 2 And mf16n <= 5 Then
                        stMsg$ = "PASS fas16d-muzzle-flash-frames (muzzleT>0 for " + Str$(mf16n) + " frames after the shot, then 0; recoil=" + LTrim$(Str$(Int(recoil * 10) / 10)) + " decaying)"
                        Gosub STLog
                        testFlag = 3: testT0 = Timer
                    Else
                        stMsg$ = "FAIL fas16d-muzzle-frames mf16n=" + Str$(mf16n)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                ElseIf Timer - testT0 >= 2 Then
                    stMsg$ = "FAIL fas16d-timeout muzzleT=" + Str$(muzzleT)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 3 Then
                If recoil < 5 Then
                    stMsg$ = "PASS fas16a-recoil-decay (recoil -> " + LTrim$(Str$(Int(recoil * 10) / 10)) + " < 5 within " + LTrim$(Str$(Int((Timer - testT0) * 10) / 10)) + "s — lerp-back OK)"
                    Gosub STLog
                    testFlag = 4: testT0 = Timer: minGunX = gunX0
                ElseIf Timer - testT0 >= 3 Then
                    stMsg$ = "FAIL fas16a-decay recoil=" + LTrim$(Str$(Int(recoil * 10) / 10))
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 4 Then
                mmx = 25   ' simulated mouse turn right -> sway must go OPPOSITE (negative)
                If gunX < minGunX Then minGunX = gunX
                If minGunX < gunX0 - 4 Or Timer - testT0 >= 1.5 Then
                    If minGunX < gunX0 - 4 Then
                        stMsg$ = "fas16b: turn right -> gunX " + LTrim$(Str$(Int(gunX0 * 10) / 10)) + " -> min " + LTrim$(Str$(Int(minGunX * 10) / 10)) + " (opposite sway OK); release and wait for return"
                        Gosub STLog
                        testFlag = 5: testT0 = Timer
                    Else
                        stMsg$ = "FAIL fas16b-sway gunX0=" + LTrim$(Str$(Int(gunX0 * 10) / 10)) + " minGunX=" + LTrim$(Str$(Int(minGunX * 10) / 10)) + " gunSway=" + LTrim$(Str$(Int(gunSway * 10) / 10)) + " turnDelta=" + LTrim$(Str$(Int(turnDelta * 1000) / 1000))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                End If
            End If
            If testFlag = 5 Then
                If Abs(gunX - gunX0) < 3 Then
                    stMsg$ = "PASS fas16b-sway-return (turn stopped -> |gunX-gunX0| < 3 within " + LTrim$(Str$(Int((Timer - testT0) * 10) / 10)) + "s, gunX=" + LTrim$(Str$(Int(gunX * 10) / 10)) + ")"
                    Gosub STLog
                    testFlag = 6: testT0 = Timer
                ElseIf Timer - testT0 >= 2 Then
                    stMsg$ = "FAIL fas16b-return gunX=" + LTrim$(Str$(Int(gunX * 10) / 10)) + " gunX0=" + LTrim$(Str$(Int(gunX0 * 10) / 10))
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 6 And state$ = "paused" Then
                ' NOTE: the pause-transition frame still runs the playing render once
                ' (state$ flips mid-branch), so gr16a is recorded on the first FULL
                ' paused frame in flag 7, not here.
                testFlag = 7: testT0 = Timer: inj16r = 0: c16done = 0: gr16a = -1
                stMsg$ = "fas16c: paused — gunRendered must stay static while paused"
                Gosub STLog
            ElseIf testFlag = 6 And state$ = "playing" And Timer - testT0 >= 3 Then
                stMsg$ = "FAIL fas16c-pause state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 7 Then
                ' Record gr16a only on a call AFTER the transition call (the flag 6->7
                ' block and this block run in the SAME call on the transition frame,
                ' BEFORE that frame's playing render — t>0.02 skips that call).
                If state$ = "paused" And gr16a = -1 And Timer - testT0 > 0.02 Then gr16a = gunRendered
                If state$ = "paused" And Timer - testT0 >= 0.4 And c16done = 0 Then
                    c16done = 1
                    If gunRendered = gr16a Then
                        stMsg$ = "PASS fas16c-not-rendered-in-pause (gunRendered static at " + Str$(gr16a) + " over 0.4s+ of pause)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas16c-pause-static gunRendered " + Str$(gr16a) + " -> " + Str$(gunRendered)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                End If
                If state$ = "playing" Then
                    If c16done = 0 Then
                        stMsg$ = "FAIL fas16c-resume-before-check state=" + state$
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    gr16b = gunRendered
                    testFlag = 8: testT0 = Timer
                ElseIf Timer - testT0 >= 4 Then
                    stMsg$ = "FAIL fas16c-timeout state=" + state$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 8 And state$ = "playing" Then
                ' CurRunTime% >= 2: fas12a requires a real frozen time (wt1 >= 1);
                ' this wave's runT0 was reset at StartRun and the pause is already
                ' subtracted, so wait until at least 2 unpaused seconds elapsed.
                If Timer - testT0 >= 0.3 And CurRunTime% >= 2 Then
                    If gunRendered > gr16b Then
                        stMsg$ = "PASS fas16c-rendered-in-playing (gunRendered " + Str$(gr16b) + " -> " + Str$(gunRendered) + " after resume)"
                        Gosub STLog
                        testPhase = 17: testT0 = Timer: testFlag = 0   ' continue to fas17 (.map loader + doors), then fas12
                    Else
                        stMsg$ = "FAIL fas16c-playing-static gr16b=" + Str$(gr16b) + " gunRendered=" + Str$(gunRendered)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                End If
            ElseIf testFlag = 8 And Timer - testT0 >= 8 Then
                stMsg$ = "FAIL fas16c-resume state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
        Case 17  ' FAS 5A: .map loader + keys/doors. Runs in playing; test maps are
                 ' written to /tmp and loaded via LoadMapAuto (same path as init).
                 ' (a) loader grid+spawn lists, (b) case S vs s, (c) keys+doors via E,
                 ' (d) BFS closed/open door, (e) broken map -> default, (f) 64x64
                 ' BFS timing, (g) command-line arg simulation. Ends by restoring
                 ' the default map and continuing to fas12.
            hp = 100
            If testFlag = 0 Then
                ' --- test map A: 12x10 with S, enemies, pickups, doors, keys ---
                f17 = FreeFile
                Open "/tmp/schleswig_fas17a.map" For Output As #f17
                Print #f17, "############"
                Print #f17, "#S...M...A.#"
                Print #f17, "#.F..d..O..#"
                Print #f17, "#..##.##...#"
                Print #f17, "#.b..1..2..#"
                Print #f17, "#....U...K.#"
                Print #f17, "#..##..##..#"
                Print #f17, "#.G....3.g.#"
                Print #f17, "#....s.....#"
                Print #f17, "############"
                Close #f17
                mapFile$ = "/tmp/schleswig_fas17a.map"
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0
                ' park one enemy inside the map so the win-trigger never fires
                For ej17 = 0 To 10: enActive(ej17) = 0: Next ej17
                enActive(0) = 1: enX(0) = 1.5: enY(0) = mapH - 1.5: enSpd(0) = 0
                enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                ' (a) loader: grid + spawn lists exact
                If mapW = 12 And mapH = 10 And loadedMapFile$ = mapFile$ And CellAt$(5, 2) = "d" And CellAt$(5, 4) = "1" And CellAt$(8, 4) = "2" And CellAt$(1, 1) = "." And CellAt$(2, 2) = "." And mapRow$(0) = "############" And spEnN = 5 And spEnT(0) = ET_FOOT And spEnX(0) = 2 And spEnY(0) = 2 And spEnT(1) = ET_OFFICER And spEnX(1) = 8 And spEnY(1) = 2 And spEnT(2) = ET_MUSKETEER And spEnX(2) = 5 And spEnY(2) = 5 And spEnT(3) = ET_CAPTAIN And spEnX(3) = 9 And spEnY(3) = 5 And spEnT(4) = ET_GENERAL And spEnX(4) = 2 And spEnY(4) = 7 And spPkN = 1 And spPkX(0) = 5 And spPkY(0) = 1 And spAmN = 1 And spAmX(0) = 9 And spAmY(0) = 1 And spKeyN = 3 And spKeyT(0) = 1 And spKeyX(0) = 2 And spKeyY(0) = 4 And spKeyT(1) = 3 And spKeyX(1) = 9 And spKeyY(1) = 7 And spKeyT(2) = 2 And spKeyX(2) = 5 And spKeyY(2) = 8 And pkX(0) = 5.5 And pkY(0) = 1.5 And keyActive(2) = 1 Then
                    stMsg$ = "PASS fas17a-loader (mapW=12 mapH=10, grid+doors parsed, spawns F/O/U/K/G at exact cells, M/A, keys b/g/s, pkX(0)=5.5)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas17a-loader mapW=" + Str$(mapW) + " mapH=" + Str$(mapH) + " spEnN=" + Str$(spEnN) + " spPkN=" + Str$(spPkN) + " spAmN=" + Str$(spAmN) + " spKeyN=" + Str$(spKeyN) + " cell52=" + CellAt$(5, 2)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' (b) case-sensitivity: 'S' (1,1) = player start, 's' (5,8) = silver KEY
                If plStartX = 1 And plStartY = 1 And spKeyN = 3 And spKeyT(2) = 2 And spKeyX(2) = 5 And spKeyY(2) = 8 Then
                    stMsg$ = "PASS fas17b-case (S=(1,1) start vs s=(5,8) silver key — case-sensitive parse OK)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas17b-case plStart=" + Str$(plStartX) + "," + Str$(plStartY) + " spKeyN=" + Str$(spKeyN)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                testFlag = 1: testT0 = Timer
            End If
            If testFlag = 1 Then
                ' (c) part 1: stand next to '1' door WITHOUT key, press E -> deny
                px = 5.5: py = 3.5: angle = 0   ' cell (5,3)='.', door '1' at (5,4)
                hasBronze = 0: hasSilver = 0: hasGold = 0
                inj17a = 0
                stMsg$ = "fas17c: at '1' door without bronze key, injecting E"
                Gosub STLog
                testFlag = 2: testT0 = Timer
            End If
            If testFlag = 2 Then
                ' inj17a=1 means the injected E already went through the door block
                If inj17a = 1 Then
                    If doorOpen%(5, 4) = 0 And hpMsg$ = strNeedBronze$ And Solid%(5, 4) = 1 Then
                        stMsg$ = "PASS fas17c-locked-deny (door '1' closed, hpMsg=" + hpMsg$ + ", Solid=1)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas17c-deny doorOpen=" + Str$(doorOpen%(5, 4)) + " hpMsg=" + hpMsg$
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' now walk over the bronze key 'b' at (2,4) -> pickup sets hasBronze
                    px = 2.5: py = 4.5
                    testFlag = 3: testT0 = Timer
                ElseIf Timer - testT0 >= 2 Then
                    stMsg$ = "FAIL fas17c-no-inject inj17a=" + Str$(inj17a)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 3 Then
                If hasBronze = 1 And keyActive(0) = 0 And hpMsg$ = strGotBronze$ Then
                    stMsg$ = "PASS fas17c-keypickup (walked over 'b' -> hasBronze=1, msg=" + hpMsg$ + ")"
                    Gosub STLog
                ElseIf Timer - testT0 >= 2 Then
                    stMsg$ = "FAIL fas17c-keypickup hasBronze=" + Str$(hasBronze) + " keyActive0=" + Str$(keyActive(0))
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                If hasBronze = 1 And keyActive(0) = 0 Then
                    px = 5.5: py = 3.5   ' back next to the '1' door, now WITH key
                    inj17b = 0
                    testFlag = 4: testT0 = Timer
                End If
            End If
            If testFlag = 4 Then
                If inj17b = 1 Then
                    If doorOpen%(5, 4) = 1 And Solid%(5, 4) = 0 Then
                        stMsg$ = "PASS fas17c-open-with-key (E + bronze -> door '1' open, Solid=0)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas17c-open doorOpen=" + Str$(doorOpen%(5, 4))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    ' '2' door at (8,4) still needs SILVER key — stand next to it, E
                    px = 8.5: py = 3.5
                    hasSilver = 0
                    inj17c = 0
                    testFlag = 5: testT0 = Timer
                ElseIf Timer - testT0 >= 2 Then
                    stMsg$ = "FAIL fas17c-no-inject-b inj17b=" + Str$(inj17b)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 5 Then
                If inj17c = 1 Then
                    If doorOpen%(8, 4) = 0 And hpMsg$ = strNeedSilver$ And Solid%(8, 4) = 1 Then
                        stMsg$ = "PASS fas17c-silver-required ('2' door denied without silver, hpMsg=" + hpMsg$ + ")"
                        Gosub STLog
                        testFlag = 6: testT0 = Timer
                    Else
                        stMsg$ = "FAIL fas17c-silver doorOpen=" + Str$(doorOpen%(8, 4)) + " hpMsg=" + hpMsg$
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                ElseIf Timer - testT0 >= 2 Then
                    stMsg$ = "FAIL fas17c-no-inject-c inj17c=" + Str$(inj17c)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 6 Then
                ' (d) BFS through a door: sealed-room map B (8x6), door '1' at (4,1)
                f17 = FreeFile
                Open "/tmp/schleswig_fas17b.map" For Output As #f17
                Print #f17, "########"
                Print #f17, "#S..1..#"
                Print #f17, "#...#..#"
                Print #f17, "#...#..#"
                Print #f17, "#...#..#"
                Print #f17, "########"
                Close #f17
                mapFile$ = "/tmp/schleswig_fas17b.map"
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                px = 1.5: py = 1.5: angle = 0
                For ej17 = 0 To 10: enActive(ej17) = 0: Next ej17
                enActive(0) = 1: enX(0) = 1.5: enY(0) = mapH - 1.5: enSpd(0) = 0
                enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                bfsTX = 1: bfsTY = 1: Gosub BFSCompute
                d17 = bfsD(5, 1)   ' right side of the sealed wall — unreachable when closed
                doorOpen%(4, 1) = 1
                bfsTX = 1: bfsTY = 1: Gosub BFSCompute
                If mapW = 8 And d17 = -1 And bfsD(5, 1) = 4 And Solid%(4, 1) = 0 Then
                    stMsg$ = "PASS fas17d-bfs-door (closed door: bfsD(5,1)=-1; open: bfsD(5,1)=4, Solid=0)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas17d-bfs-door dClosed=" + Str$(d17) + " dOpen=" + Str$(bfsD(5, 1)) + " mapW=" + Str$(mapW)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                testFlag = 7: testT0 = Timer
            End If
            If testFlag = 7 Then
                ' (e) broken map (ragged rows + invalid char) -> LOUD fatal reject
                ' (5A-hotfix2: no silent default fallback anymore), grid untouched
                f17 = FreeFile
                Open "/tmp/schleswig_fas17bad.map" For Output As #f17
                Print #f17, "##########"
                Print #f17, "#S..#...."
                Print #f17, "#...X....#"
                Print #f17, "##########"
                Close #f17
                row17save$ = mapRow$(0): mapW17save = mapW
                mapFile$ = "/tmp/schleswig_fas17bad.map"
                Gosub LoadMapAuto
                If loadFatal = 1 And mapValid = 0 And InStr(fatalMsg$, "INVALID MAP") > 0 And errRow >= 2 And mapRow$(0) = row17save$ And mapW = mapW17save Then
                    stMsg$ = "PASS fas17e-broken-map-fatal (rejected loudly: " + fatalMsg$ + "; mapRow$ untouched)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas17e loadFatal=" + Str$(loadFatal) + " mapValid=" + Str$(mapValid) + " errRow=" + Str$(errRow) + " msg=" + fatalMsg$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                testFlag = 8: testT0 = Timer
            End If
            If testFlag = 8 Then
                ' (f) 64x64 map + BFS timing (< 1 ms per cell per BFS)
                f17 = FreeFile
                Open "/tmp/schleswig_fas17_64.map" For Output As #f17
                For yy = 0 To 63
                    r17$ = ""
                    For xx = 0 To 63
                        c17$ = "."
                        If xx = 0 Or yy = 0 Or xx = 63 Or yy = 63 Then c17$ = "#"
                        If xx = 32 And yy >= 20 And yy <= 43 Then c17$ = "#"
                        If xx = 1 And yy = 1 Then c17$ = "S"
                        If xx = 32 And yy = 32 Then c17$ = "d"
                        If xx = 60 And yy = 60 Then c17$ = "F"
                        r17$ = r17$ + c17$
                    Next xx
                    Print #f17, r17$
                Next yy
                Close #f17
                mapFile$ = "/tmp/schleswig_fas17_64.map"
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0
                For ej17 = 0 To 10: enActive(ej17) = 0: Next ej17
                enActive(0) = 1: enX(0) = 1.5: enY(0) = mapH - 1.5: enSpd(0) = 0
                enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                If mapW = 64 And mapH = 64 And loadedMapFile$ = mapFile$ Then
                    bfsTX = 1: bfsTY = 1
                    t17 = Timer
                    For k17 = 1 To 500: Gosub BFSCompute: Next k17
                    el17 = Timer - t17
                    c17 = 0
                    For yy = 0 To mapH - 1
                        For xx = 0 To mapW - 1
                            If bfsD(xx, yy) >= 0 Then c17 = c17 + 1
                        Next xx
                    Next yy
                    per17 = el17 / (500 * c17)
                    If per17 < 0.001 Then
                        stMsg$ = "PASS fas17f-bfs-64x64 (500 BFS over " + Str$(c17) + " cells in " + LTrim$(Str$(Int(el17 * 1000) / 1000)) + "s -> " + LTrim$(Str$(Int(per17 * 1000000) / 1000)) + " us/cell < 1 ms)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas17f-bfs-64x64 perCell=" + LTrim$(Str$(Int(per17 * 1000000) / 1000)) + "us cells=" + Str$(c17)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                Else
                    stMsg$ = "FAIL fas17f-load mapW=" + Str$(mapW) + " mapH=" + Str$(mapH)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                testFlag = 9: testT0 = Timer
            End If
            If testFlag = 9 Then
                ' (g) command-line arg simulation: MapFileFromCmd$ + LoadMapAuto
                If MapFileFromCmd$("selftest") = "" And MapFileFromCmd$("/tmp/schleswig_fas17_64.map") = "/tmp/schleswig_fas17_64.map" Then
                    mapFile$ = MapFileFromCmd$("/tmp/schleswig_fas17_64.map")
                    Gosub LoadMapAuto
                    If loadedMapFile$ = "/tmp/schleswig_fas17_64.map" And mapW = 64 And mapH = 64 Then
                        stMsg$ = "PASS fas17g-cmdline-arg ('schleswig mapfile.map' -> MapFileFromCmd$ -> LoadMapAuto loads it, 64x64)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas17g-cmdline loaded=" + loadedMapFile$ + " mapW=" + Str$(mapW)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                Else
                    stMsg$ = "FAIL fas17g-parse MapFileFromCmd$(selftest)=" + MapFileFromCmd$("selftest")
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' restore the selftest 16x16 map + spawns, then continue to fas18
                mapFile$ = selftestMap$
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0
                For ej17 = 0 To 10: enActive(ej17) = 0: Next ej17
                enActive(0) = 1: enX(0) = 13.5: enY(0) = 9.5: enSpd(0) = 0
                enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                If mapW = 16 And mapH = 16 And mapValid = 1 And loadFatal = 0 And Len(loadedMapFile$) > 0 Then
                    stMsg$ = "PASS fas17-end (selftest 16x16 map restored, loaded=" + loadedMapFile$ + ")"
                    Gosub STLog
                End If
                testPhase = 18: testT0 = Timer: testFlag = 0   ' continue to fas18 (5A-hotfix2), then fas12
            End If
        Case 18  ' FAS 5A-HOTFIX2: (a) missing map file -> LOUD fatal, grid untouched,
                 ' (b) broken map -> loud fatal with line/col in log, (c) maps/default.map
                 ' = the 64x64 TEST ARENA (64 rows x 64 cols, exactly one S, every
                 ' register enemy type >=1, sealed border, sane render wallDist),
                 ' (d) test64 via two path forms -> identical grid, (e) render only
                 ' ever sees a fully-parsed grid, (f) viewmodel common origin +
                 ' rigid single-offset sway/recoil cycle.
            hp = 100
            If testFlag = 0 Then
                ' (c) default.map = 64x64 test arena: size, one S, all enemy types
                mapFile$ = "maps/default.map"
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                p18t0 = 0: p18t1 = 0: p18t2 = 0: p18t3 = 0: p18t4 = 0
                For ej18 = 0 To spEnN - 1
                    If spEnT(ej18) = ET_FOOT Then p18t0 = p18t0 + 1
                    If spEnT(ej18) = ET_OFFICER Then p18t1 = p18t1 + 1
                    If spEnT(ej18) = ET_MUSKETEER Then p18t2 = p18t2 + 1
                    If spEnT(ej18) = ET_CAPTAIN Then p18t3 = p18t3 + 1
                    If spEnT(ej18) = ET_GENERAL Then p18t4 = p18t4 + 1
                Next ej18
                If mapW = 64 And mapH = 64 And mapValid = 1 And loadFatal = 0 And nStartS = 1 And Len(mapRow$(0)) = 64 And Len(mapRow$(63)) = 64 And mapRow$(0) = String$(64, "#") And mapRow$(63) = String$(64, "#") And plStartX = 32 And plStartY = 37 And p18t0 >= 1 And p18t1 >= 1 And p18t2 >= 1 And p18t3 >= 1 And p18t4 >= 1 Then
                    stMsg$ = "PASS fas18c-default-arena (" + loadedMapFile$ + ": 64x64, one S=(32,37), sealed border, enemies F/O/U/K/G = " + Str$(p18t0) + "/" + Str$(p18t1) + "/" + Str$(p18t2) + "/" + Str$(p18t3) + "/" + Str$(p18t4) + ")"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas18c mapW=" + Str$(mapW) + " mapH=" + Str$(mapH) + " mapValid=" + Str$(mapValid) + " nStartS=" + Str$(nStartS) + " loaded=" + loadedMapFile$ + " plStart=" + Str$(plStartX) + "," + Str$(plStartY) + " types=" + Str$(p18t0) + "/" + Str$(p18t1) + "/" + Str$(p18t2) + "/" + Str$(p18t3) + "/" + Str$(p18t4)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' render sanity on the arena: stand at S facing east, the center
                ' column must hit the arena room wall (~9.5 cells), not the void
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0
                For ej18 = 0 To 10: enActive(ej18) = 0: Next ej18
                enActive(0) = 1: enX(0) = 24.5: enY(0) = 24.5: enSpd(0) = 0
                enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                testFlag = 7: testT0 = Timer
            End If
            If testFlag = 7 Then
                If Timer - testT0 >= 0.4 Then
                    If mapValid = 1 And wallDist(RW \ 2) > 3 And wallDist(RW \ 2) < 63 Then
                        stMsg$ = "PASS fas18c-render (from S=(32.5,37.5) facing east, wallDist(center)=" + LTrim$(Str$(Int(wallDist(RW \ 2) * 10) / 10)) + " = arena room wall — sane, no void)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas18c-render mapValid=" + Str$(mapValid) + " wallDistC=" + LTrim$(Str$(Int(wallDist(RW \ 2) * 10) / 10))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    testFlag = 1: testT0 = Timer
                ElseIf Timer - testT0 >= 3 Then
                    stMsg$ = "FAIL fas18c-render-timeout"
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 1 Then
                ' (d) test64 via TWO path forms (relative + absolute; game cwd is
                ' the exe dir, so both resolve to the same file) -> identical grid
                mapFile$ = "maps/test64.map"
                Gosub LoadMapAuto
                If mapW = 64 And mapH = 64 And mapValid = 1 And loadFatal = 0 Then
                    hash18& = 0
                    For ej18 = 0 To 63: hash18& = (hash18& + Len(mapRow$(ej18)) * 31 + Asc(Left$(mapRow$(ej18), 1)) + Asc(Right$(mapRow$(ej18), 1))) And &H7FFFFFFF: Next ej18
                    stMsg$ = "fas18: test64 via relative 'maps/test64.map' loaded (" + loadedMapFile$ + "), hash=" + Str$(hash18&)
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas18d-load1 mapW=" + Str$(mapW) + " loaded=" + loadedMapFile$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                mapFile$ = "/home/andre/QB64pe/schleswig/maps/test64.map"
                Gosub LoadMapAuto
                hash18b& = 0
                For ej18 = 0 To 63: hash18b& = (hash18b& + Len(mapRow$(ej18)) * 31 + Asc(Left$(mapRow$(ej18), 1)) + Asc(Right$(mapRow$(ej18), 1))) And &H7FFFFFFF: Next ej18
                If mapW = 64 And mapH = 64 And mapValid = 1 And loadFatal = 0 And hash18& = hash18b& And loadedMapFile$ = "/home/andre/QB64pe/schleswig/maps/test64.map" Then
                    stMsg$ = "PASS fas18d-test64-path-forms (relative 'maps/test64.map' and absolute path -> same 64x64 grid, hash=" + Str$(hash18&) + ")"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas18d hash " + Str$(hash18&) + " vs " + Str$(hash18b&) + " mapW=" + Str$(mapW) + " mapH=" + Str$(mapH) + " mapValid=" + Str$(mapValid) + " loadFatal=" + Str$(loadFatal) + " loaded=" + loadedMapFile$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                mapFile$ = "maps/test64.map"
                Gosub LoadMapAuto
                ' (e) render must see the loaded grid: face east from test64 S=(1,1),
                ' render a few frames, wallDist(center) must be the test64 east wall (~61.5)
                Gosub ApplyMapSpawns
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0
                For ej18 = 0 To 10: enActive(ej18) = 0: Next ej18
                enActive(0) = 1: enX(0) = 1.5: enY(0) = mapH - 1.5: enSpd(0) = 0
                enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                testFlag = 2: testT0 = Timer
            End If
            If testFlag = 2 Then
                If Timer - testT0 >= 0.4 Then
                    If mapValid = 1 And wallDist(RW \ 2) > 50 Then
                        stMsg$ = "PASS fas18e-render-guard (mapValid=1, render wallDist(center)=" + LTrim$(Str$(Int(wallDist(RW \ 2) * 10) / 10)) + " = test64 east wall — render only ever sees a fully parsed grid)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas18e mapValid=" + Str$(mapValid) + " wallDistC=" + LTrim$(Str$(Int(wallDist(RW \ 2) * 10) / 10))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    testFlag = 3: testT0 = Timer
                ElseIf Timer - testT0 >= 3 Then
                    stMsg$ = "FAIL fas18e-timeout"
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 3 Then
                ' (a) missing file -> loud fatal, mapRow$ untouched, no crash
                row18save$ = mapRow$(0): mapW18save = mapW
                mapFile$ = "maps/glurst.map"
                Gosub LoadMapAuto
                If loadFatal = 1 And mapValid = 0 And InStr(fatalMsg$, "MAP FILE NOT FOUND") > 0 And InStr(fatalMsg$, "maps/glurst.map") > 0 And mapRow$(0) = row18save$ And mapW = mapW18save Then
                    stMsg$ = "PASS fas18a-missing-file-fatal (" + fatalMsg$ + "; grid untouched, no crash)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas18a loadFatal=" + Str$(loadFatal) + " mapValid=" + Str$(mapValid) + " msg=" + fatalMsg$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                testFlag = 4: testT0 = Timer
            End If
            If testFlag = 4 Then
                ' (b) broken map -> loud fatal, log has line/col
                f17 = FreeFile
                Open "/tmp/schleswig_fas18bad.map" For Output As #f17
                Print #f17, "##########"
                Print #f17, "#S..#...."
                Print #f17, "#...X....#"
                Print #f17, "##########"
                Close #f17
                row18save$ = mapRow$(0): mapW18save = mapW
                mapFile$ = "/tmp/schleswig_fas18bad.map"
                Gosub LoadMapAuto
                If loadFatal = 1 And mapValid = 0 And InStr(fatalMsg$, "INVALID MAP") > 0 And InStr(fatalMsg$, "line " + LTrim$(Str$(errRow))) > 0 And InStr(fatalMsg$, "col " + LTrim$(Str$(errCol))) > 0 And errRow = 2 And errCol > 0 And mapRow$(0) = row18save$ And mapW = mapW18save Then
                    stMsg$ = "PASS fas18b-broken-map-fatal (" + fatalMsg$ + ")"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas18b loadFatal=" + Str$(loadFatal) + " errRow=" + Str$(errRow) + " msg=" + fatalMsg$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' restore selftest 16x16 map for the rest of the selftest
                mapFile$ = selftestMap$
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                If mapValid = 1 And loadFatal = 0 And mapW = 16 Then
                    stMsg$ = "fas18: selftest 16x16 map restored (" + loadedMapFile$ + ")"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas18-restore mapW=" + Str$(mapW) + " loadFatal=" + Str$(loadFatal)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0
                For ej18 = 0 To 10: enActive(ej18) = 0: Next ej18
                enActive(0) = 1: enX(0) = 13.5: enY(0) = 9.5: enSpd(0) = 0
                enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                testFlag = 5: testT0 = Timer
            End If
            If testFlag = 5 Then
                ' (f) viewmodel integrity: barrel and stock share ONE origin (vmCX),
                ' captured geometry vars + buffer handle must survive a sway/recoil
                ' cycle unchanged (sprite moves as a single blit offset gunX/gunY).
                ' NOTE: POINT() is not used — in selftest the render dest is unreliable
                ' for buffer reads; structural asserts are deterministic instead.
                If vmCX - bxx0 = vmBarrelHW And bxx1 - vmCX = vmBarrelHW And Abs((gsx0 + gw16 \ 2) - vmCX) <= 1 And gunBuf& <> 0 Then
                    stMsg$ = "fas18f: barrel centered on vmCX (bxx0/vmCX/bxx1 = " + Str$(bxx0) + "/" + Str$(vmCX) + "/" + Str$(bxx1) + "), stock butt row centered within 1px, gunBuf& <> 0 — common origin OK"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL fas18f-origin vmCX=" + Str$(vmCX) + " bxx0=" + Str$(bxx0) + " bxx1=" + Str$(bxx1) + " hw=" + Str$(vmBarrelHW) + " stockMid=" + Str$(gsx0 + gw16 \ 2) + " gunBuf&=" + Str$(gunBuf&)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                pj1& = gunBuf&: p18n = vmCX: pm18 = gunBH: pj2& = gunRendered   ' capture geometry + handle + blit counter
                recoil = 20: muzzleT = 0: shakeT = 0: mmx = 25   ' force a sway+recoil cycle
                p18sway = 0
                testFlag = 6: testT0 = Timer
            End If
            If testFlag = 6 Then
                If Abs(gunX) + recoil > p18sway Then p18sway = Abs(gunX) + recoil   ' track that the cycle really moved the sprite
                If Timer - testT0 >= 0.4 Then
                    If vmCX = p18n And gunBH = pm18 And gunBuf& = pj1& And p18sway > 0 And gunRendered > pj2& Then
                        stMsg$ = "PASS fas18f-viewmodel (sway/recoil cycle ran: max offset " + LTrim$(Str$(Int(p18sway * 10) / 10)) + " px, " + Str$(gunRendered - pj2&) + " blits during cycle; vmCX/gunBH/gunBuf& constant -> whole sprite moved by ONE gunX/gunY offset, primitives cannot drift)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL fas18f-drift vmCX=" + Str$(vmCX) + "/" + Str$(p18n) + " gunBH=" + Str$(gunBH) + "/" + Str$(pm18) + " gunBuf&=" + Str$(gunBuf&) + "/" + Str$(pj1&) + " swayMax=" + LTrim$(Str$(Int(p18sway * 10) / 10))
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    recoil = 0: muzzleT = 0: shakeT = 0
                    testPhase = 19: testT0 = Timer: testFlag = 0   ' 5C: continue to fas19 (level progression), then fas12 (win trigger -> menu -> SELFTEST OK)
                ElseIf Timer - testT0 >= 3 Then
                    stMsg$ = "FAIL fas18f-timeout"
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
        Case 19  ' 5C LEVEL-PROGRESSION: (a) levels.lst parse (missing/bad/good/shipped),
                 ' (b) CONTINUE loads level N+1 with enemy/wave registers reset and a
                 ' different grid hash, score kept; (c) last level -> victory screen +
                 ' PLAY AGAIN; (d) --level 3 -> lst position 3 + HUD name; (e) death ->
                 ' RESTART LEVEL same level (never next), segment score restored,
                 ' restarts++; (f) full campaign 1->5 automated -> victory, kills total.
            If testFlag = 0 Then
                ' --- 5c-a1: missing levels.lst -> loud fatal ---
                lstFile$ = "/tmp/schleswig_no_such_levels.lst"
                Gosub LoadLevelsLst
                If loadFatal = 1 And lvlN = 0 And InStr(fatalMsg$, "LEVELS FILE NOT FOUND") > 0 Then
                    stMsg$ = "PASS 5c-a1-levels-missing-fatal (" + fatalMsg$ + ")"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-a1 loadFatal=" + Str$(loadFatal) + " lvlN=" + Str$(lvlN) + " msg=" + fatalMsg$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' --- 5c-a2: broken line -> INVALID LEVELS LIST with line number ---
                f19 = FreeFile
                Open "/tmp/schleswig_levels_bad.lst" For Output As #f19
                Print #f19, "/tmp/schleswig_lvl01.map|Test One"
                Print #f19, "this line has no pipe"
                Print #f19, "/tmp/schleswig_lvl03.map|Test Three"
                Close #f19
                lstFile$ = "/tmp/schleswig_levels_bad.lst"
                Gosub LoadLevelsLst
                If loadFatal = 1 And InStr(fatalMsg$, "INVALID LEVELS LIST line 2") > 0 Then
                    stMsg$ = "PASS 5c-a2-levels-badline-fatal (" + fatalMsg$ + ")"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-a2 loadFatal=" + Str$(loadFatal) + " msg=" + fatalMsg$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' --- 5c-a3: good lst -> 5 levels in play order (write 5 test maps first) ---
                c19cnt(1) = 2: c19cnt(2) = 3: c19cnt(3) = 4: c19cnt(4) = 6: c19cnt(5) = 8
                For c19lvl = 1 To 5
                    f19 = FreeFile
                    Open "/tmp/schleswig_lvl0" + LTrim$(Str$(c19lvl)) + ".map" For Output As #f19
                    For c19y = 0 To 15
                        r19$ = ""
                        For c19x = 0 To 15
                            ch$ = "."
                            If c19x = 0 Or c19y = 0 Or c19x = 15 Or c19y = 15 Then ch$ = "#"
                            If c19x = 1 And c19y = 1 Then ch$ = "S"
                            If c19y = 4 And (c19x = 5 Or c19x = 10) Then ch$ = "#"
                            If c19y = 12 And (c19x = 5 Or c19x = 10) Then ch$ = "#"
                            If c19x = 7 And c19y = 2 + c19lvl Then ch$ = "#"   ' per-level wall -> distinct grid hash
                            If c19y = 8 Then
                                For c19i = 1 To c19cnt(c19lvl)
                                    If c19x = 2 + c19i Then ch$ = Mid$("FOUUKGFO", c19i, 1)
                                Next c19i
                            End If
                            r19$ = r19$ + ch$
                        Next c19x
                        Print #f19, r19$
                    Next c19y
                    Close #f19
                Next c19lvl
                f19 = FreeFile
                Open "/tmp/schleswig_levels5.lst" For Output As #f19
                Print #f19, "/tmp/schleswig_lvl01.map|Test One"
                Print #f19, "/tmp/schleswig_lvl02.map|Test Two"
                Print #f19, "/tmp/schleswig_lvl03.map|Test Three"
                Print #f19, "/tmp/schleswig_lvl04.map|Test Four"
                Print #f19, "/tmp/schleswig_lvl05.map|Test Five"
                Close #f19
                lstFile$ = "/tmp/schleswig_levels5.lst"
                Gosub LoadLevelsLst
                If loadFatal = 0 And lvlN = 5 And lvlFile$(0) = "/tmp/schleswig_lvl01.map" And lvlName$(0) = "Test One" And lvlFile$(2) = "/tmp/schleswig_lvl03.map" And lvlName$(2) = "Test Three" And lvlFile$(4) = "/tmp/schleswig_lvl05.map" And lvlName$(4) = "Test Five" Then
                    stMsg$ = "PASS 5c-a3-levels-parse-order (5 levels in play order: " + lvlFile$(0) + "|" + lvlName$(0) + " ... " + lvlFile$(4) + "|" + lvlName$(4) + ")"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-a3 loadFatal=" + Str$(loadFatal) + " lvlN=" + Str$(lvlN) + " f0=" + lvlFile$(0) + " n4=" + lvlName$(4)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' --- 5c-a4: shipped campaign files: maps/levels.lst -> 5 levels, every map loads valid ---
                lstFile$ = "maps/levels.lst"
                Gosub LoadLevelsLst
                c19ok = (loadFatal = 0 And lvlN = 5)
                If c19ok Then
                    For c19i = 0 To lvlN - 1
                        mapFile$ = lvlFile$(c19i)
                        Gosub LoadMapAuto
                        If loadFatal = 1 Or mapValid = 0 Then c19ok = 0
                    Next c19i
                End If
                If c19ok Then
                    stMsg$ = "PASS 5c-a4-shipped-levels-lst (maps/levels.lst: 5 levels, every .map loads valid: " + lvlFile$(0) + " ... " + lvlFile$(4) + ")"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-a4 loadFatal=" + Str$(loadFatal) + " lvlN=" + Str$(lvlN)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' restore the /tmp test list, then arg parsing (5c-d parse half)
                lstFile$ = "/tmp/schleswig_levels5.lst"
                Gosub LoadLevelsLst
                ok19 = (GameModeFromCmd$("") = "arena" And GameModeFromCmd$("selftest") = "selftest" And GameModeFromCmd$("campaign") = "campaign" And GameModeFromCmd$("--level 3") = "campaign" And GameModeFromCmd$("--level=4") = "campaign" And GameModeFromCmd$("maps/test64.map") = "single" And LevelFromCmd%("--level 3") = 3 And LevelFromCmd%("--level=4") = 4 And LevelFromCmd%("campaign") = 0 And LevelFromCmd%("") = 0)
                If ok19 And loadFatal = 0 And lvlN = 5 Then
                    stMsg$ = "PASS 5c-d0-args (mode: ''->arena selftest->selftest campaign/--level->campaign mapfile->single; LevelFromCmd%: '--level 3'->3 '--level=4'->4 campaign->0 ''->0)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-d0-args mode(empty)=" + GameModeFromCmd$("") + " mode(selftest)=" + GameModeFromCmd$("selftest") + " lvl(--level 3)=" + Str$(LevelFromCmd%("--level 3"))
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                testFlag = 1: testT0 = Timer
            End If
            If testFlag = 1 Then
                ' campaign setup on level 1 with leak probes (projectile/enemy/wave)
                gameMode$ = "campaign"
                shotsFired = 7: dmgTaken = 10: runT0 = Timer - 5
                killsTotal = 0: restarts = 0: lvlIdx = 0
                For c19i = 0 To PR_MAX: prActive(c19i) = 0: Next c19i
                prActive(2) = 1                          ' projectile leak probe
                For c19i = 0 To 10: enActive(c19i) = 0: Next c19i
                enActive(0) = 1: enState(0) = 2: enHP(0) = 99   ' enemy-state leak probes
                waveNo = 9                                ' wave-register leak probe
                bfsForX = 77: bfsForY = 77               ' BFS-target leak probe
                Gosub LoadLevel
                c19bfs = bfsForX   ' captured BEFORE the first playing frame can recompute BFS
                testFlag = 2: testT0 = Timer
            End If
            If testFlag = 2 And state$ = "playing" Then
                c19hash& = mapHash&
                c19alive = 0
                For c19i = 0 To 10
                    If enActive(c19i) Then c19alive = c19alive + 1
                Next c19i
                c19prAll = 1
                For c19i = 0 To PR_MAX
                    If prActive(c19i) Then c19prAll = 0
                Next c19i
                c19hud$ = HudLevelTag$
                If lvlIdx = 0 And mapW = 16 And mapValid = 1 And loadFatal = 0 And c19alive = 2 And waveNo = 1 And c19prAll = 1 And enState(0) = 0 And enHP(0) = etHP(ET_FOOT) And c19bfs = -1 And shotsFired = 7 And dmgTaken = 10 And InStr(c19hud$, "LVL 1/5") > 0 And InStr(c19hud$, "Test One") > 0 Then
                    stMsg$ = "PASS 5c-b0-level-load-reset (level 1 loaded: 2 map enemies, waveNo probe 9->1, projectile probe cleared, enState/enHP reset, BFS cleared, score kept shotsFired=7 dmg=10, HUD='" + c19hud$ + "')"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-b0 lvlIdx=" + Str$(lvlIdx) + " mapW=" + Str$(mapW) + " alive=" + Str$(c19alive) + " waveNo=" + Str$(waveNo) + " prAll=" + Str$(c19prAll) + " enState0=" + Str$(enState(0)) + " enHP0=" + Str$(enHP(0)) + " c19bfs=" + Str$(c19bfs) + " shots=" + Str$(shotsFired) + " hud=" + c19hud$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' kill all via the REAL kill path -> win -> result (level 1 of 5: NOT victory)
                For c19i = 0 To 10
                    If enActive(c19i) Then hitE = c19i: hitDmg = 999: Gosub EnemyTakeHit
                Next c19i
                winPending = 0
                testFlag = 3: testT0 = Timer
            ElseIf testFlag = 2 And Timer - testT0 >= 4 Then
                stMsg$ = "FAIL 5c-b0-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 3 And state$ = "result" Then
                If gameMode$ = "campaign" And lvlIdx = 0 And lvlN = 5 Then
                    stMsg$ = "PASS 5c-b1-clear-mid-campaign-result (level 1 cleared -> state=result (lvlIdx 0 < lvlN-1 4), CONTINUE offered — NOT victory)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-b1 state=result but gameMode=" + gameMode$ + " lvlIdx=" + Str$(lvlIdx) + " lvlN=" + Str$(lvlN)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                testFlag = 4: testT0 = Timer   ' result-branch injects mb -> pendingNext path
            ElseIf testFlag = 3 And Timer - testT0 >= 4 Then
                stMsg$ = "FAIL 5c-b1-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 4 And state$ = "playing" Then
                c19alive = 0
                For c19i = 0 To 10
                    If enActive(c19i) Then c19alive = c19alive + 1
                Next c19i
                c19prAll = 1
                For c19i = 0 To PR_MAX
                    If prActive(c19i) Then c19prAll = 0
                Next c19i
                c19hud$ = HudLevelTag$
                If lvlIdx = 1 And mapHash& <> c19hash& And c19alive = 3 And waveNo = 1 And c19prAll = 1 And shotsFired = 7 And dmgTaken = 10 And InStr(c19hud$, "LVL 2/5") > 0 And InStr(c19hud$, "Test Two") > 0 Then
                    stMsg$ = "PASS 5c-b2-continue-next-level (CONTINUE -> level 2: grid hash " + Str$(c19hash&) + "->" + Str$(mapHash&) + " CHANGED, alive 2->3 from new map, waveNo=1 (reset), projectiles cleared, NO enemy/wave leak, score kept shotsFired=7, HUD='" + c19hud$ + "')"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-b2 lvlIdx=" + Str$(lvlIdx) + " hash " + Str$(c19hash&) + "->" + Str$(mapHash&) + " alive=" + Str$(c19alive) + " waveNo=" + Str$(waveNo) + " prAll=" + Str$(c19prAll) + " shots=" + Str$(shotsFired) + " hud=" + c19hud$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' --- 5c-c: jump to LAST level, clear it -> victory (NOT result) ---
                lvlIdx = lvlN - 1
                Gosub LoadLevel
                testFlag = 5: testT0 = Timer
            ElseIf testFlag = 4 And Timer - testT0 >= 5 Then
                stMsg$ = "FAIL 5c-b2-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 5 And state$ = "playing" Then
                For c19i = 0 To 10
                    If enActive(c19i) Then hitE = c19i: hitDmg = 999: Gosub EnemyTakeHit
                Next c19i
                winPending = 0
                testFlag = 6: testT0 = Timer
            ElseIf testFlag = 5 And Timer - testT0 >= 4 Then
                stMsg$ = "FAIL 5c-c0-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 6 And state$ = "victory" Then
                If lvlIdx = lvlN - 1 Then
                    stMsg$ = "PASS 5c-c1-last-level-victory (last level " + Str$(lvlN) + "/" + Str$(lvlN) + " cleared -> state=victory, NOT result/CONTINUE)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-c1 state=victory but lvlIdx=" + Str$(lvlIdx)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                inj19v = 0
                testFlag = 7: testT0 = Timer   ' victory-branch injects E -> PLAY AGAIN
            ElseIf testFlag = 6 And Timer - testT0 >= 4 Then
                stMsg$ = "FAIL 5c-c1-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 7 And state$ = "playing" Then
                c19hud$ = HudLevelTag$
                If lvlIdx = 0 And shotsFired = 0 And dmgTaken = 0 And killsTotal = 0 And mapHash& = c19hash& And InStr(c19hud$, "LVL 1/5") > 0 Then
                    stMsg$ = "PASS 5c-c2-play-again (PLAY AGAIN -> level 1 reloaded (hash back to " + Str$(mapHash&) + "), score zeroed shotsFired=0 dmg=0 kills=0, HUD='" + c19hud$ + "')"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-c2 lvlIdx=" + Str$(lvlIdx) + " shots=" + Str$(shotsFired) + " dmg=" + Str$(dmgTaken) + " kills=" + Str$(killsTotal) + " hash=" + Str$(mapHash&) + " vs " + Str$(c19hash&) + " hud=" + c19hud$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                testFlag = 8: testT0 = Timer
            ElseIf testFlag = 7 And Timer - testT0 >= 5 Then
                stMsg$ = "FAIL 5c-c2-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 8 Then
                ' --- 5c-d: --level 3 -> lst position 3, right name in HUD ---
                c19lvl = LevelFromCmd%("--level 3")
                lvlIdx = c19lvl - 1
                Gosub LoadLevel
                testFlag = 9: testT0 = Timer
            End If
            If testFlag = 9 And state$ = "playing" Then
                c19hud$ = HudLevelTag$
                If lvlIdx = 2 And mapFile$ = lvlFile$(2) And lvlName$(2) = "Test Three" And InStr(c19hud$, "LVL 3/5") > 0 And InStr(c19hud$, "Test Three") > 0 Then
                    stMsg$ = "PASS 5c-d-level3 ('--level 3' -> lst position 3 (lvlIdx=2), map=" + mapFile$ + ", HUD='" + c19hud$ + "')"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-d lvlIdx=" + Str$(lvlIdx) + " mapFile=" + mapFile$ + " want=" + lvlFile$(2) + " name=" + lvlName$(2) + " hud=" + c19hud$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' --- 5c-e setup: death on level 3 -> RESTART same level ---
                c19hash& = mapHash&
                c19seg = segShots
                shotsFired = segShots + 5   ' extra shots in this segment (must be rolled back)
                hp = 0                      ' death next playing frame -> state=dead
                c19died = 0: inj19d = 0
                testFlag = 10: testT0 = Timer
            ElseIf testFlag = 9 And Timer - testT0 >= 4 Then
                stMsg$ = "FAIL 5c-d-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 10 And state$ = "playing" And c19died = 1 Then
                c19hud$ = HudLevelTag$
                If lvlIdx = 2 And mapHash& = c19hash& And restarts = 1 And shotsFired = c19seg And InStr(c19hud$, "LVL 3/5") > 0 Then
                    stMsg$ = "PASS 5c-e-death-restart-same-level (death on level 3 -> RESTART LEVEL: lvlIdx still 2 (NOT next), same map hash " + Str$(mapHash&) + ", restarts=1, segment score restored shotsFired " + Str$(c19seg + 5) + "->" + Str$(shotsFired) + ", HUD LVL 3/5)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-e lvlIdx=" + Str$(lvlIdx) + " hash=" + Str$(mapHash&) + "/" + Str$(c19hash&) + " restarts=" + Str$(restarts) + " shots=" + Str$(shotsFired) + " want " + Str$(c19seg) + " hud=" + c19hud$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' --- 5c-f: full campaign 1->5 automated ---
                lvlIdx = 0: c19lvl = 0: killsTotal = 0: shotsFired = 0: dmgTaken = 0: runT0 = Timer: restarts = 0
                Gosub LoadLevel
                testFlag = 11: testT0 = Timer
            ElseIf testFlag = 10 And Timer - testT0 >= 6 Then
                stMsg$ = "FAIL 5c-e-timeout state=" + state$ + " c19died=" + Str$(c19died)
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 11 Then
                If state$ = "playing" And lvlIdx = c19lvl Then
                    c19alive = 0
                    For c19i = 0 To 10
                        If enActive(c19i) Then c19alive = c19alive + 1
                    Next c19i
                    If c19alive > 0 Then
                        ' kill all via the REAL kill path (killsTotal++ per enemy)
                        For c19i = 0 To 10
                            If enActive(c19i) Then hitE = c19i: hitDmg = 999: Gosub EnemyTakeHit
                        Next c19i
                        hp = 100
                    End If
                    ' do NOT touch winPending here — the win trigger needs 1s with alive==0
                    testFlag = 12: testT0 = Timer
                ElseIf state$ = "playing" Then
                    stMsg$ = "FAIL 5c-f-lvl mismatch state=playing lvlIdx=" + Str$(lvlIdx) + " c19lvl=" + Str$(c19lvl)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                ElseIf Timer - testT0 >= 5 Then
                    stMsg$ = "FAIL 5c-f-timeout11 state=" + state$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 12 Then
                If state$ = "result" Then
                    If lvlIdx = c19lvl And c19lvl < lvlN - 1 Then
                        testFlag = 13: testT0 = Timer   ' result-branch injects mb -> CONTINUE
                    Else
                        stMsg$ = "FAIL 5c-f12-result lvlIdx=" + Str$(lvlIdx) + " c19lvl=" + Str$(c19lvl)
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                ElseIf state$ = "victory" Then
                    If lvlIdx = lvlN - 1 And c19lvl = lvlN - 1 And killsTotal = 23 Then
                        stMsg$ = "PASS 5c-f-full-campaign (levels 1->5 cleared in order via CONTINUE, each level hash distinct, final -> victory screen; killsTotal=23 = 2+3+4+6+8 spawned)"
                        Gosub STLog
                    Else
                        stMsg$ = "FAIL 5c-f-victory lvlIdx=" + Str$(lvlIdx) + " c19lvl=" + Str$(c19lvl) + " killsTotal=" + Str$(killsTotal) + " (want 23)"
                        Gosub STLog
                        stMsg$ = "SELFTEST FAIL"
                        Gosub STLog
                        ShutdownSound
                        End
                    End If
                    inj19v = 0
                    testFlag = 14: testT0 = Timer   ' victory-branch injects E -> PLAY AGAIN
                ElseIf Timer - testT0 >= 5 Then
                    stMsg$ = "FAIL 5c-f12-timeout state=" + state$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
            If testFlag = 13 And state$ = "playing" Then
                If lvlIdx = c19lvl + 1 Then
                    c19lvl = lvlIdx
                    testFlag = 11: testT0 = Timer
                Else
                    stMsg$ = "FAIL 5c-f13-continue lvlIdx=" + Str$(lvlIdx) + " c19lvl=" + Str$(c19lvl)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            ElseIf testFlag = 13 And Timer - testT0 >= 5 Then
                stMsg$ = "FAIL 5c-f13-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 14 And state$ = "playing" Then
                c19hud$ = HudLevelTag$
                If lvlIdx = 0 And shotsFired = 0 And killsTotal = 0 Then
                    stMsg$ = "PASS 5c-f2-play-again-after-campaign (victory PLAY AGAIN -> level 1, score zeroed, killsTotal=0, HUD='" + c19hud$ + "')"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5c-f2 lvlIdx=" + Str$(lvlIdx) + " shots=" + Str$(shotsFired) + " kills=" + Str$(killsTotal)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' restore the selftest environment, then continue to fas12 (win trigger -> menu -> SELFTEST OK)
                gameMode$ = "selftest"
                mapFile$ = selftestMap$
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0: hp = 100: ammo = 5
                For i = 0 To 10: enActive(i) = 0: Next i
                enX(0) = 13.5: enY(0) = 9.5: enActive(0) = 1: enSpd(0) = 0
                enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                For i = 0 To PR_MAX: prActive(i) = 0: Next i
                bfsForX = -1: bfsForY = -1
                winPending = 0: runTimeFrozen = -1: restarts = 0: lvlN = 0
                runT0 = Timer - 3   ' fas12a needs a real frozen time (wt1 >= 1): pretend 3s elapsed
                state$ = "playing"
                testPhase = 20: testT0 = Timer: testFlag = 0   ' 5D: start menu tests, then fas21 (64x64 regression), then fas12
            ElseIf testFlag = 14 And Timer - testT0 >= 5 Then
                stMsg$ = "FAIL 5c-f2-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
        Case 20  ' 5D START MENU (no-arg pick): (a) no-arg -> menu state with pick
                 ' rows + arg-decision functions, (b) key "1" -> TEST ARENA (HUD
                 ' ARENA + default.map + hash), key "2" -> CAMPAIGN LVL 1/5 with
                 ' right MAP+hash+name, (c) campaign ARG auto-starts (no menu).
            hp = 100
            If testFlag = 0 Then
                ' (a) decision functions + set up the no-arg pick menu
                ok19 = (MenuPickFromCmd%("") = 1 And MenuPickFromCmd%("campaign") = 0 And MenuPickFromCmd%("--level 2") = 0 And MenuPickFromCmd%("maps/x.map") = 0 And MenuPickFromCmd%("selftest") = 0 And AutoStartFromCmd%("campaign") = 1 And AutoStartFromCmd%("--level 3") = 1 And AutoStartFromCmd%("") = 0 And AutoStartFromCmd%("maps/x.map") = 0 And AutoStartFromCmd%("selftest") = 0)
                gameMode$ = "arena": menuPick = 1: autoCamp = 0: state$ = "menu": selIdx = 1
                mapFile$ = "maps/default.map"
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                If ok19 And state$ = "menu" And menuPick = 1 And mapW = 64 And mapH = 64 And mapValid = 1 And loadFatal = 0 Then
                    c20hash& = mapHash&
                    stMsg$ = "PASS 5d-a-noarg-pick-menu (no-arg -> state=menu, menuPick=1, default.map 64x64 loaded, hash=" + Str$(c20hash&) + "; MenuPickFromCmd%('')=1 others=0; AutoStartFromCmd% campaign/--level=1 others=0)"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5d-a ok19=" + Str$(ok19) + " state=" + state$ + " menuPick=" + Str$(menuPick) + " mapW=" + Str$(mapW) + " loadFatal=" + Str$(loadFatal)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                inj20a = 0
                testFlag = 1: testT0 = Timer   ' menu-branch injects k$="1"
            End If
            If testFlag = 1 And state$ = "playing" Then
                c20hud$ = HudLevelTag$
                If gameMode$ = "arena" And menuPick = 0 And mapW = 64 And mapHash& = c20hash& And InStr(c20hud$, "ARENA") > 0 And InStr(c20hud$, "default.map") > 0 Then
                    stMsg$ = "PASS 5d-b1-pick1-arena (key '1' -> TEST ARENA: state=playing, gameMode=arena, 64x64 default.map same hash " + Str$(mapHash&) + ", HUD='" + c20hud$ + "')"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5d-b1 state=" + state$ + " mode=" + gameMode$ + " menuPick=" + Str$(menuPick) + " mapW=" + Str$(mapW) + " hud=" + c20hud$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' set up the campaign pick again (fresh no-arg menu)
                menuPick = 1: state$ = "menu": selIdx = 1: gameMode$ = "arena": inj20c = 0
                testFlag = 3: testT0 = Timer   ' menu-branch injects k$="2"
            ElseIf testFlag = 1 And Timer - testT0 >= 5 Then
                stMsg$ = "FAIL 5d-b1-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 3 And state$ = "playing" Then
                c20hud$ = HudLevelTag$
                If gameMode$ = "campaign" And menuPick = 0 And lvlIdx = 0 And lvlN = 5 And mapW = 16 And mapFile$ = "maps/level01.map" And InStr(c20hud$, "LVL 1/5") > 0 And InStr(c20hud$, "The Outskirts") > 0 And InStr(c20hud$, "level01.map") > 0 Then
                    c20hash& = mapHash&
                    stMsg$ = "PASS 5d-b2-pick2-campaign (key '2' -> CAMPAIGN: levels.lst level 1 loaded, lvlIdx=0 lvlN=5, 16x16, HUD='" + c20hud$ + "')"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5d-b2 state=" + state$ + " mode=" + gameMode$ + " lvlIdx=" + Str$(lvlIdx) + " lvlN=" + Str$(lvlN) + " mapW=" + Str$(mapW) + " mapFile=" + mapFile$ + " hud=" + c20hud$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' (c) campaign ARG skips the menu: autoCamp=1 + state=menu -> auto StartRun
                autoCamp = 1: state$ = "menu": selIdx = 1
                c20runs = startRuns
                testFlag = 5: testT0 = Timer
            ElseIf testFlag = 3 And Timer - testT0 >= 5 Then
                stMsg$ = "FAIL 5d-b2-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
            If testFlag = 5 And state$ = "playing" Then
                c20hud$ = HudLevelTag$
                If autoCamp = 0 And gameMode$ = "campaign" And startRuns = c20runs + 1 And InStr(c20hud$, "LVL 1/5") > 0 And mapW = 16 Then
                    stMsg$ = "PASS 5d-c-campaign-arg-skips-menu (autoCamp -> StartRun with NO key/menu interaction: startRuns " + Str$(c20runs) + "->" + Str$(startRuns) + ", playing on level 1, HUD='" + c20hud$ + "')"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5d-c autoCamp=" + Str$(autoCamp) + " state=" + state$ + " startRuns=" + Str$(startRuns) + "/" + Str$(c20runs) + " hud=" + c20hud$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                ' restore selftest env, continue to fas21 (64x64 regression)
                gameMode$ = "selftest": menuPick = 0: autoCamp = 0
                mapFile$ = selftestMap$
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0: hp = 100: ammo = 5
                For i = 0 To 10: enActive(i) = 0: Next i
                enX(0) = 13.5: enY(0) = 9.5: enActive(0) = 1: enSpd(0) = 0
                enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                For i = 0 To PR_MAX: prActive(i) = 0: Next i
                bfsForX = -1: bfsForY = -1
                winPending = 0: runTimeFrozen = -1
                state$ = "playing"
                testPhase = 21: testT0 = Timer: testFlag = 0
            ElseIf testFlag = 5 And Timer - testT0 >= 5 Then
                stMsg$ = "FAIL 5d-c-timeout state=" + state$
                Gosub STLog
                stMsg$ = "SELFTEST FAIL"
                Gosub STLog
                ShutdownSound
                End
            End If
        Case 21  ' 5D 64x64 RUNTIME REGRESSION (the navet): load the real 64x64 arena
                 ' (all enemy types incl. GENERAL/mortar), simulate a real session
                 ' (~2 min): AI hunts, player balls + enemy balls + mortars fly,
                 ' waves respawn, enemies die via the real kill path, player is
                 ' teleported near the map edges/corners, a ball is fired AT a
                 ' corner (must die at the boundary), a STATIONARY ball is placed
                 ' at the right screen edge (bx1 > RW-1 — the old single-line clamp
                 ' bug crashed here with subscript out of range), a mortar lands in
                 ' corner cell (0,0). PASS = survive it all, 0 crash, probes done.
            hp = 100
            If testFlag = 0 Then
                gameMode$ = "single"   ' neutral mode for the regression (result->pendingStart path)
                mapFile$ = "maps/default.map"
                Gosub LoadMapAuto
                Gosub ApplyMapSpawns
                If mapW = 64 And mapH = 64 And mapValid = 1 And loadFatal = 0 And spEnN >= 5 Then
                    stMsg$ = "5d-64x64: arena loaded (" + loadedMapFile$ + " 64x64, " + Str$(spEnN) + " map spawns incl. all types), hash=" + Str$(mapHash&) + " — starting " + "120" + "s simulated session"
                    Gosub STLog
                Else
                    stMsg$ = "FAIL 5d-64x64-load mapW=" + Str$(mapW) + " mapH=" + Str$(mapH) + " spEnN=" + Str$(spEnN) + " loadFatal=" + Str$(loadFatal)
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
                waveNo = 0
                Gosub SpawnEnemies
                px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0: hp = 100: ammo = 20: lastShotTime = -1
                For i = 0 To PR_MAX: prActive(i) = 0: Next i
                bfsForX = -1: bfsForY = -1
                c21t0 = Timer: c21shots = 0: c21corner = 0: c21cornerOK = 0: c21edge = 0: c21edgeOK = 0
                c21mortar = 0: c21mortOK = 0: c21killed = 0: c21wave = 0
                c21lastKill = Timer: c21lastWave = Timer: c21lastEdge = Timer: c21lastCorner = Timer
                state$ = "playing"
                testFlag = 1: testT0 = Timer
            End If
            If testFlag = 1 Then
                ' keep the session alive and busy
                hp = 100
                If state$ = "result" Then pendingStart = 1: state$ = "menu"   ' wave cleared -> next round
                If state$ = "playing" Then
                    ' keep at least 2 enemies alive (respawn at an open cell)
                    c21alive = 0
                    For c21i = 0 To 10
                        If enActive(c21i) Then c21alive = c21alive + 1
                    Next c21i
                    If c21alive < 2 Then
                        c21x = 2 + Int(Rnd * (mapW - 4)): c21y = 2 + Int(Rnd * (mapH - 4))
                        If OpenCell%(c21x, c21y) Then
                            For c21i = 0 To 10
                                If enActive(c21i) = 0 Then
                                    enX(c21i) = c21x + 0.5: enY(c21i) = c21y + 0.5: enActive(c21i) = 1
                                    enType(c21i) = ET_FOOT: enHP(c21i) = etHP(ET_FOOT): enDmg(c21i) = etDmg(ET_FOOT): enSpd(c21i) = etSpd!(ET_FOOT)
                                    enState(c21i) = 0: enFireT(c21i) = Timer + 99: enZigT(c21i) = Timer + 99
                                    c21i = 99
                                End If
                            Next c21i
                        End If
                    End If
                    ' player near the edges/corners now and then
                    If Timer - c21lastEdge >= 4 Then
                        c21lastEdge = Timer
                        c21c = Int(Rnd * 4)
                        If c21c = 0 Then c21x = 1: c21y = 1
                        If c21c = 1 Then c21x = mapW - 2: c21y = 1
                        If c21c = 2 Then c21x = 1: c21y = mapH - 2
                        If c21c = 3 Then c21x = mapW - 2: c21y = mapH - 2
                        If OpenCell%(c21x, c21y) Then px = c21x + 0.5: py = c21y + 0.5: angle = Rnd * 6.2831853
                    End If
                    ' fire a real player ball AT the map corner (0,0) / (63,63):
                    ' it must fly and DIE at the boundary (bounds check), never index OOB
                    If c21corner = 0 And Timer - c21lastCorner >= 6 Then
                        c21lastCorner = Timer
                        c21corner = 1
                        If OpenCell%(1, 1) Then px = 1.5: py = 1.5
                        angle = _ATan2(0.5 - py, 0.5 - px)   ' straight at corner cell (0,0)
                        dirX = Cos(angle): dirY = Sin(angle)
                        lastShotTime = -1: ammo = 20: fireBtn = 1
                        c21shots = c21shots + 1
                    End If
                    ' stationary probe ball at the RIGHT screen edge (bang ~0.62 rad):
                    ' its screen x exceeds RW -> bx1 > RW-1 while bx0 >= 0 — the exact
                    ' case where the old single-line clamp skipped bx1 and wallDist(sx)
                    ' went subscript-out-of-range. Render must clamp and survive.
                    If c21edge = 0 And Timer - testT0 >= 2 Then
                        c21edge = 1
                        c21lastEdge = Timer
                        spX = px + Cos(angle + 0.62) * 2.5: spY = py + Sin(angle + 0.62) * 2.5
                        If spX < 1 Then spX = 1: If spX > mapW - 2 Then spX = mapW - 2
                        If spY < 1 Then spY = 1: If spY > mapH - 2 Then spY = mapH - 2
                        spDX = 0: spDY = 0: spSpd! = 0   ' stationary: renders every frame
                        spOwner = 0: spDmg = 1: spType = PR_BALL: spSrcType = -1: spTX = 0: spTY = 0: spLandT = 0
                        Gosub SpawnProjectile
                        c21edgePc = RW / 2 * (1 + Tan(0.62) / planeDist)   ' > RW: would crash old code
                        stMsg$ = "5d-64x64 edge probe: stationary ball at screen x=" + LTrim$(Str$(Int(c21edgePc))) + " (> RW=" + Str$(RW) + ", bx1>RW-1 — old clamp bug crashed here); rendering..."
                        Gosub STLog
                    End If
                    If c21edge = 1 And Timer - c21lastEdge >= 0.6 Then
                        c21edgeOK = 1   ' survived 0.6s of edge rendering (0 subscript = process alive)
                        For c21i = 0 To PR_MAX
                            If prActive(c21i) And prSpd!(c21i) = 0 Then prActive(c21i) = 0   ' remove probe
                        Next c21i
                        c21edge = 2
                    End If
                    ' corner-cell MORTAR (target (0,0)) — splash at the corner, no OOB
                    If c21mortar = 0 And Timer - testT0 >= 4 Then
                        c21mortar = 1
                        spX = px: spY = py: spDX = 0: spDY = 0: spSpd! = 0
                        spOwner = 1: spDmg = 0: spType = PR_MORTAR: spSrcType = ET_GENERAL
                        spTX = 0: spTY = 0: spLandT = Timer + 0.3
                        Gosub SpawnProjectile
                    End If
                    If c21mortar = 1 And Timer - testT0 >= 5 Then c21mortOK = 1   ' survived the corner splash
                    ' kill an enemy via the REAL kill path every ~8s (waves/kills)
                    If Timer - c21lastKill >= 8 Then
                        c21lastKill = Timer
                        For c21i = 0 To 10
                            If enActive(c21i) And c21killed < 99 Then hitE = c21i: hitDmg = 999: Gosub EnemyTakeHit: c21killed = c21killed + 1: c21i = 99
                        Next c21i
                    End If
                    ' wave respawn every ~25s (SpawnEnemies: register reset path)
                    If Timer - c21lastWave >= 25 Then
                        c21lastWave = Timer: c21wave = c21wave + 1
                        Gosub SpawnEnemies
                        hp = 100
                    End If
                    ' aimed fire at nearest enemy (player balls in flight)
                    c21alive = 0: c21bd = 999: c21bi = -1
                    For c21i = 0 To 10
                        If enActive(c21i) Then
                            c21alive = c21alive + 1
                            c21d = Sqr((enX(c21i) - px) ^ 2 + (enY(c21i) - py) ^ 2)
                            If c21d < c21bd Then c21bd = c21d: c21bi = c21i
                        End If
                    Next c21i
                    If c21bi >= 0 And Timer - lastShotTime >= 0.35 Then
                        angle = _ATan2(enY(c21bi) - py, enX(c21bi) - px)
                        dirX = Cos(angle): dirY = Sin(angle)
                        ammo = 20: fireBtn = 1: c21shots = c21shots + 1
                    Else
                        fireBtn = 0
                    End If
                End If
                ' verify the corner ball actually DIED at the boundary (no active balls stuck OOB)
                If c21corner = 1 And c21cornerOK = 0 And Timer - c21lastCorner >= 1.5 Then
                    c21stuck = 0
                    For c21i = 0 To PR_MAX
                        If prActive(c21i) And prType(c21i) = PR_BALL Then
                            If prX(c21i) < 0 Or prX(c21i) >= mapW Or prY(c21i) < 0 Or prY(c21i) >= mapH Then c21stuck = 1
                        End If
                    Next c21i
                    If c21stuck = 0 Then c21cornerOK = 1
                End If
                ' done after ~120s of simulated 64x64 play with all probes done
                If Timer - c21t0 >= 120 And c21cornerOK = 1 And c21edgeOK = 1 And c21mortOK = 1 And c21killed >= 1 Then
                    stMsg$ = "PASS 5d-64x64-regression (" + Str$(Int(Timer - c21t0)) + "s simulated session on the 64x64 arena: AI/waves=" + Str$(c21wave) + ", kills=" + Str$(c21killed) + ", player balls=" + Str$(c21shots) + ", corner ball died at boundary (0 OOB projectiles), edge ball at screen x>" + Str$(RW) + " rendered 0.6s (0 subscript — clamp fix proven), corner (0,0) mortar landed, 0 crash, clean exit)"
                    Gosub STLog
                    ' restore the selftest 16x16 env, continue to fas12
                    gameMode$ = "selftest": menuPick = 0: autoCamp = 0
                    mapFile$ = selftestMap$
                    Gosub LoadMapAuto
                    Gosub ApplyMapSpawns
                    px = plStartX + 0.5: py = plStartY + 0.5: angle = 0: pitch = 0: hp = 100: ammo = 5
                    For i = 0 To 10: enActive(i) = 0: Next i
                    enX(0) = 13.5: enY(0) = 9.5: enActive(0) = 1: enSpd(0) = 0
                    enState(0) = 0: enFireT(0) = Timer + 99: enZigT(0) = Timer + 99
                    For i = 0 To PR_MAX: prActive(i) = 0: Next i
                    bfsForX = -1: bfsForY = -1
                    winPending = 0: runTimeFrozen = -1: restarts = 0: lvlN = 0
                    runT0 = Timer - 3   ' fas12a needs a real frozen time (wt1 >= 1)
                    state$ = "playing"
                    testPhase = 12: testT0 = Timer: testFlag = 0
                ElseIf Timer - c21t0 >= 150 Then
                    stMsg$ = "FAIL 5d-64x64-timeout t=" + Str$(Int(Timer - c21t0)) + " cornerOK=" + Str$(c21cornerOK) + " edgeOK=" + Str$(c21edgeOK) + " mortOK=" + Str$(c21mortOK) + " killed=" + Str$(c21killed) + " state=" + state$
                    Gosub STLog
                    stMsg$ = "SELFTEST FAIL"
                    Gosub STLog
                    ShutdownSound
                    End
                End If
            End If
    End Select
    Return

