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

Dim mapRow$(15)
For i = 0 To 15
    Read mapRow$(i)
Next i
Data "################"
Data "#..............#"
Data "#..##......##..#"
Data "#..##......##..#"
Data "#..............#"
Data "#.....####.....#"
Data "#.....#..#.....#"
Data "#.....#..#.....#"
Data "#..#..####..#..#"
Data "#..#........#..#"
Data "#..#.####.#.#..#"
Data "#....#..#...#..#"
Data "#..............#"
Data "#......##......#"
Data "#..............#"
Data "################"

Dim pal&(255)
For i = 0 To 255
    pal&(i) = _RGB32(i, i, i)
Next i

' RW/RH satta ovan från fönstrets dimension (var tidigare Const 960/540)

px = 8.5
py = 4.5
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
Const strBuild$ = "4ab7814"

' ===== SPELTEXT (centraliserad enligt GPLv3-PREP 2026-11-23) =================
' All användarvisad text samlas här. Svenska nu -- vid release 1.0+ översätts
' denna sektion till engelska (och LICENSE/README läggs till). Selftestets
' loggsträngar (stMsg$) är diagnostik och ligger kvar vid selftest-koden.
Const strAppName$ = "Schleswig"                    ' fönstertitel (_Title)
Const strTitle$ = "SCHLESWIG"                      ' stor titel på titelskärmen
Const strStartBtn$ = "START GAME"                  ' menyknapp
Const strQuitBtn$ = "QUIT GAME"                    ' menyknapp 2 (samma meny, samma bredd)
Const strDead$ = "DU DÖ"                           ' dödsskärm, stor text
Const strRestart$ = "Tryck R för att starta om"    ' dödsskärm, rad 2
Const strHudHp$ = "HP:"                            ' HUD-etikett
Const strHudAmmo$ = "AMMO:"                        ' HUD-etikett
Const strFps$ = "FPS:"                             ' debug-rad + fönstertitel
Const strDmgDebug$ = "-5 HP"                       ' debug-knapp G
Const strMedkit$ = "+25 HP"                        ' medkit-pickup
Const strAmmoPick$ = "+5 AMMO"                     ' ammo-pickup (FIX 3: +5, cap 20)
Const strScore$ = "SCORE:"                         ' dödsskärm/HUD: score-rad
Const strBest$ = "BÄSTA:"                          ' dödsskärm/resultat: bästa score
Const strNewRec$ = "NY REKORD!"                    ' dödsskärm/resultat: vid nytt rekord
Const strWin$ = "KARTAN KLAR"                      ' resultatskärm: titel
Const strTime$ = "TID:"                            ' resultatskärm: mm:ss
Const strShots$ = "SKOTT:"                         ' resultatskärm
Const strDmg$ = "SKADA:"                           ' resultatskärm
Const strEscMenu$ = "ESC = PAUS"                       ' resultat-skärm, nederst (ESC -> paus)
Const strClickCont$ = "CLICK TO CONTINUE"              ' result: fortsätt med klick/SPACE/ENTER (snabb blink)
Const strPaused$ = "PAUSAD"                            ' pausmeny: titel
Const strResume$ = "FORTSÄTT"                          ' pausmeny: knapp 1
Const strRestartRound$ = "RESTART ROND"                ' pausmeny: knapp 2
Const strQuitPause$ = "AVSLUTA SPELET"                 ' pausmeny: knapp 3
Const strNextMap$ = "VIDARE"                           ' resultatmeny: knapp 1 (ny runda)
Const strMainMenu$ = "HUVUDMENY"                       ' resultatmeny: knapp 2
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
pkX(0) = 1.5: pkY(0) = 1.5: pkActive(0) = 1
pkX(1) = 7.5: pkY(1) = 1.5: pkActive(1) = 1
pkX(2) = 14.5: pkY(2) = 1.5: pkActive(2) = 1
pkX(3) = 5.5: pkY(3) = 7.5: pkActive(3) = 1
pkX(4) = 6.5: pkY(4) = 14.5: pkActive(4) = 1

' Fas 2: ammo + skjutning (ingen HP-regen; samma array-pool-mönster som medkit)
Const maxAmmo = 20         ' ammo-cap — samma konstant används av HUD-streckantalet
DIM amX(10), amY(10), amActive(10)
ammo = 5
lastShotTime = -1        ' cooldown 0.3 s mellan skott
tracerTime = -1          ' tracer-flash synlig 2-3 frames
flashTime = -1           ' träff-flash
flashDist = 99
amX(0) = 3.5: amY(0) = 4.5: amActive(0) = 1
amX(1) = 12.5: amY(1) = 4.5: amActive(1) = 1
amX(2) = 6.5: amY(2) = 9.5: amActive(2) = 1

' Fas 3/3.1: fiende-pool (samma array-pool-mönster som pickups): pos, aktiv flagga,
' hp (3 träffar), skada, hastighet + AI-tillstånd. Startlägen i SpawnEnemies.
' enState: 0=PATROLL, 1=JAKT, 2=ANFALL. bfsD = BFS-avståndskarta (flödesfält).
DIM enX(10), enY(10), enActive(10), enHP(10), enDmg(10), enSpd(10), enLastHit(10)
DIM enState(10), enSeen(10), enTx(10), enTy(10), enPatrolT(10), enLastSeen(10)
DIM enLx(10), enLy(10), enCalmT(10), bfsD(15, 15), qx(255), qy(255)
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
Const SND_COUNT = 8
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
testPhase = 0: testT0 = Timer: stMsg$ = "": testDbg = 0: testHb = Timer: testFlag = 0
Gosub InitSounds   ' Fas 4: ljud-register + raw-pipe (säker även headless)
' Highscore: nollställ counters, ladda bästa score från lokal fil (.schleswig_scores.txt)
shotsFired = 0: dmgTaken = 0: runT0 = Timer: score = 0: newRecord = 0: bestScore = 0
winPending = 0: winT0 = 0: runTimeFrozen = -1: escCool = -99
lockEngaged = 0: lockEngages = 0: lockDestroys = 0   ' låset engageras vid FÖRSTA fade-slutet (StartRun-vägen), INTE vid init
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
    state$ = "playing"          ' hoppa över menyn direkt
    LogMouse "HIDE_DISABLE selftest-init"
    stMsg$ = "pre-lock-init: lockEngaged=" + Str$(lockEngaged) + " engages=" + Str$(lockEngages) + " (lås sker vid första fade-slut, ej vid init)": Gosub STLog
    lockHint = 1
    runT0 = Timer: shotsFired = 0: dmgTaken = 0: winPending = 0: runTimeFrozen = -1   ' highscore-counters i selftest
    Gosub SpawnEnemies
    ' Fas 3.1-scenario: EN fiende i PATROLL utan LOS till spelaren (10.5,6.5)->(8.5,4.5)
    For i = 1 To 10: enActive(i) = 0: Next i
    px = 8.5: py = 4.5: angle = 0: hp = 100: ammo = 5
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

    ' ======== STATE-MACHINE: menu <-> playing (SPACE startar, ESC avslutar) ========
    If selftest And (state$ = "menu" Or state$ = "result" Or state$ = "paused") Then Gosub SelftestDrive   ' fas12/13 kör även utanför playing
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
        ' FIX 2: ESC i menu avslutar fortfarande, men inte precis efter ESC från
        ' result-skärmen (held ESC skulle annars bledda in i meny-grenen)
        If state$ = "menu" And (k$ = Chr$(27) Or _KeyDown(27)) And Timer - escCool > 0.3 Then Gosub QuitGame
        While _MouseInput: WEND   ' töm muskön så inget läcker till playing
        mx = _MouseX: my = _MouseY
        ' TANGENT-nav (alltid aktiv, även efter låset): W/S eller upp/ner-pil
        ' flyttar markering, ENTER väljer, SPACE=START (osynlig genväg).
        If state$ = "menu" And (k$ = "w" Or k$ = "W" Or k$ = Chr$(0) + "H" Or _KeyDown(18432)) Then selIdx = selIdx - 1: If selIdx < 1 Then selIdx = 2
        If state$ = "menu" And (k$ = "s" Or k$ = "S" Or k$ = Chr$(0) + "P" Or _KeyDown(20480)) Then selIdx = selIdx + 1: If selIdx > 2 Then selIdx = 1
        If state$ = "menu" And k$ = " " Then
            Gosub StartRun   ' SPACE = osynlig genväg för START
            SOUND 300, 2: SOUND 150, 3        ' klick/plopp
        End If
        If state$ = "menu" And k$ = Chr$(13) Then   ' ENTER väljer markerad knapp
            If selIdx = 1 Then
                Gosub StartRun
                SOUND 300, 2: SOUND 150, 3
            Else
                Gosub QuitGame   ' QUIT GAME = samma exit som meny-ESC
            End If
        End If
        ' knapp-geometri: GEMENSAM bredd för hela huvudmenyn = längsta labeln
        ' (START GAME / QUIT GAME) + 2*padX — båda knappar lika brede
        padX = Int(btnFontSize * 0.9): If padX < 12 Then padX = 12
        BtnTextW strStartBtn$, w1: BtnTextW strQuitBtn$, w2
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
            If _MouseButton(1) And hover = 1 Then
                Gosub StartRun
                SOUND 300, 2: SOUND 150, 3
            End If
            If _MouseButton(1) And hover = 2 Then Gosub QuitGame
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
        ' två knappar via samma DrawButton-widget: START GAME + QUIT GAME (samma
        ' bredd); markerad rad är amber (selIdx). INGEN pekare ritas i menyn.
        DrawButton btnX0, btnY0, btnX1, btnY1, strStartBtn$, (selIdx = 1)
        DrawButton quitX0, quitY0, quitX1, quitY1, strQuitBtn$, (selIdx = 2)
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
            px = 8.5: py = 4.5: angle = 0: pitch = 0
            Gosub SpawnEnemies
            testPhase = 9: testT0 = Timer: testFlag = 0
        End If
        ' selftest fas12c: dödsskärm -> R -> meny (enda vägen till menyn nu)
        If selftest And testPhase = 12 And testFlag = 3 And state$ = "dead" Then k$ = "r"
        If k$ = "r" Or k$ = "R" Or k$ = " " Or _KeyDown(Asc("R")) Or _KeyDown(32) Then
            ' reset ALLT -> tillbaka till menyn
            hp = 100: ammo = 5
            px = 8.5: py = 4.5: angle = 0: pitch = 0
            For i = 0 To 10
                If i <= 4 Then pkActive(i) = 1 Else pkActive(i) = 0
                If i <= 2 Then amActive(i) = 1 Else amActive(i) = 0
            Next i
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
            Color _RGB32(200, 200, 200)
            _PrintString ((RW - Len(strRestart$) * 8) \ 2, RH \ 2 + 40), strRestart$
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
        ' CLICK TO CONTINUE. Valfritt musklick (låst mus funkar osynligt) eller
        ' SPACE/ENTER -> pendingStart (nästa runda via meny-START-vägen).
        ' ESC -> paus (resumeState=result). INGEN pekare ritas här.
        resPanelHalf = Int(RH * 240 / 1080)   ' panel rymmer statistik + textrader
        resEscY = RH \ 2 + Int(RH * 70 / 1080)
        mb = 0
        While _MouseInput: WEND   ' töm muskön
        If _MouseButton(1) Then mb = 1
        ' selftest fas12: simulera klick (testFlag=2 -> fortsätt till nästa runda)
        If selftest And testPhase = 12 And testFlag = 2 Then mb = 1
        If (k$ = Chr$(27) Or _KeyDown(27)) And Timer - escCool > 0.3 Then
            ' ESC i result -> PAUS (resumeState=result; FORTSÄTT återgår hit)
            resumeState$ = "result"
            pauseT0 = Timer
            escCool = Timer
            selIdx = 1
            _KeyClear
            state$ = "paused"
        ElseIf (mb Or k$ = " " Or k$ = Chr$(13)) And state$ = "result" Then
            ' FORTSÄTT till nästa runda: BARA pendingStart=1 + state=menu (samma
            ' frame) — meny-grenen går samma START-väg (StartRun -> fadeout ->
            ' playing). Ingen egen övergångskod här.
            pendingStart = 1
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
        If k$ = Chr$(13) Then pauAct = selIdx                     ' ENTER väljer
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
    Else

    ' ESC i playing -> PAUS (inte längre End; avsluta sker via pausmenyn)
    If k$ = Chr$(27) Or _KeyDown(27) Or (selftest And testPhase = 13 And (testFlag = 6 Or testFlag = 10)) Then
        resumeState$ = "playing"
        pauseT0 = Timer
        escCool = Timer
        selIdx = 1
        _KeyClear
        state$ = "paused"
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
    If turnL Then angle = angle - turnStep * speed
    If turnR Then angle = angle + turnStep * speed

    dirX = Cos(angle)
    dirY = Sin(angle)
    ox = px: oy = py   ' före rörelse, för fotstegs-ackumulatorn

    If mvF Then
        nx = px + dirX * moveStep * speed
        ny = py + dirY * moveStep * speed
        If Mid$(mapRow$(Int(py)), Int(nx + Sgn(nx - px) * 0.2) + 1, 1) <> "#" Then px = nx
        If Mid$(mapRow$(Int(ny + Sgn(ny - py) * 0.2)), Int(px) + 1, 1) <> "#" Then py = ny
    End If
    If mvB Then
        nx = px - dirX * moveStep * speed
        ny = py - dirY * moveStep * speed
        If Mid$(mapRow$(Int(py)), Int(nx + Sgn(nx - px) * 0.2) + 1, 1) <> "#" Then px = nx
        If Mid$(mapRow$(Int(ny + Sgn(ny - py) * 0.2)), Int(px) + 1, 1) <> "#" Then py = ny
    End If
    If mvL Then
        nx = px + dirY * moveStep * 0.6 * speed
        ny = py - dirX * moveStep * 0.6 * speed
        If Mid$(mapRow$(Int(py)), Int(nx + Sgn(nx - px) * 0.2) + 1, 1) <> "#" Then px = nx
        If Mid$(mapRow$(Int(ny + Sgn(ny - py) * 0.2)), Int(px) + 1, 1) <> "#" Then py = ny
    End If
    If mvR Then
        nx = px - dirY * moveStep * 0.6 * speed
        ny = py + dirX * moveStep * 0.6 * speed
        If Mid$(mapRow$(Int(py)), Int(nx + Sgn(nx - px) * 0.2) + 1, 1) <> "#" Then px = nx
        If Mid$(mapRow$(Int(ny + Sgn(ny - py) * 0.2)), Int(px) + 1, 1) <> "#" Then py = ny
    End If

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
                            If cx2 >= 0 And cx2 <= 15 And cy2 >= 0 And cy2 <= 15 Then
                                If Mid$(mapRow$(cy2), cx2 + 1, 1) <> "#" Then
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
                        If Mid$(mapRow$(Int(enY(i))), Int(nex + Sgn(nex - enX(i)) * 0.2) + 1, 1) <> "#" Then enX(i) = nex
                        If Mid$(mapRow$(Int(ney + Sgn(ney - enY(i)) * 0.2)), Int(enX(i)) + 1, 1) <> "#" Then enY(i) = ney
                    End If
                Case 1   ' JAKT: följ BFS-fältet nedströms (4-riktning, inga diagonaler)
                    bcx = Int(enX(i)): bcy = Int(enY(i))
                    If bfsForX >= 0 And bcx >= 0 And bcx <= 15 And bcy >= 0 And bcy <= 15 And bfsD(bcx, bcy) > 0 Then
                        best = bfsD(bcx, bcy): bnx = -1: bny = -1
                        If bcx + 1 <= 15 Then If Mid$(mapRow$(bcy), bcx + 2, 1) <> "#" Then If bfsD(bcx + 1, bcy) >= 0 And bfsD(bcx + 1, bcy) < best Then best = bfsD(bcx + 1, bcy): bnx = bcx + 1: bny = bcy
                        If bcx - 1 >= 0 Then If Mid$(mapRow$(bcy), bcx, 1) <> "#" Then If bfsD(bcx - 1, bcy) >= 0 And bfsD(bcx - 1, bcy) < best Then best = bfsD(bcx - 1, bcy): bnx = bcx - 1: bny = bcy
                        If bcy + 1 <= 15 Then If Mid$(mapRow$(bcy + 1), bcx + 1, 1) <> "#" Then If bfsD(bcx, bcy + 1) >= 0 And bfsD(bcx, bcy + 1) < best Then best = bfsD(bcx, bcy + 1): bnx = bcx: bny = bcy + 1
                        If bcy - 1 >= 0 Then If Mid$(mapRow$(bcy - 1), bcx + 1, 1) <> "#" Then If bfsD(bcx, bcy - 1) >= 0 And bfsD(bcx, bcy - 1) < best Then best = bfsD(bcx, bcy - 1): bnx = bcx: bny = bcy - 1
                        If bnx >= 0 Then
                            gdx = bnx + 0.5 - enX(i)
                            gdy = bny + 0.5 - enY(i)
                            gdist = Sqr(gdx * gdx + gdy * gdy)
                            If gdist > 0.02 Then
                                nex = enX(i) + gdx / gdist * enSpd(i) * dt
                                ney = enY(i) + gdy / gdist * enSpd(i) * dt
                                ' väggkollision behålls även i JAKT (samma 0.2-marginal)
                                If Mid$(mapRow$(Int(enY(i))), Int(nex + Sgn(nex - enX(i)) * 0.2) + 1, 1) <> "#" Then enX(i) = nex
                                If Mid$(mapRow$(Int(ney + Sgn(ney - enY(i)) * 0.2)), Int(enX(i)) + 1, 1) <> "#" Then enY(i) = ney
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
                            If Mid$(mapRow$(Int(enY(i))), Int(nex + Sgn(nex - enX(i)) * 0.2) + 1, 1) <> "#" Then enX(i) = nex
                            If Mid$(mapRow$(Int(ney + Sgn(ney - enY(i)) * 0.2)), Int(enX(i)) + 1, 1) <> "#" Then enY(i) = ney
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
            Loop Until Mid$(mapRow$(mapY), mapX + 1, 1) = "#"
            If sdx < sdy Then hitDist = sdx - ddx Else hitDist = sdy - ddy
            If hitDist < 0.2 Then hitDist = 0.2
            flashDist = hitDist
            ' Fas 3: fiende-träff — närmaste aktiva fienden inom vinkeltolerans
            ' (halv bredd 0.35 tiles sedd från spelaren) OCH närmare än vägg-träffen
            ' tar 1 skada; hp=0 -> fienden dör (enActive=0)
            bestE = -1
            bestD = hitDist
            For i = 0 To 10
                If enActive(i) Then
                    fdx = enX(i) - px
                    fdy = enY(i) - py
                    fdist = Sqr(fdx * fdx + fdy * fdy)
                    If fdist > 0.05 And fdist < bestD Then
                        fang = _ATan2(fdy, fdx) - angle
                        While fang > 3.14159265: fang = fang - 6.2831853: Wend
                        While fang < -3.14159265: fang = fang + 6.2831853: Wend
                        If Abs(fang) <= Atn(0.35 / fdist) Then
                            bestE = i
                            bestD = fdist
                        End If
                    End If
                End If
            Next i
            If bestE >= 0 Then
                enHP(bestE) = enHP(bestE) - 1
                flashDist = bestD
                If enHP(bestE) <= 0 Then
                    enActive(bestE) = 0
                    hpMsg$ = "FIENDE DÖD"
                    PlaySound SND_ENDIE
                    ' TID-FYS vid EXAKT sista killen: räkna levande NU (efter denna
                    ' död-registrering); om 0 -> frys run-tiden här, första gången.
                    ' Rundstart/spawn-gap kan ALDRIG nudda detta (ingen kill här).
                    aliveNow = 0
                    For j = 0 To 10
                        If enActive(j) Then aliveNow = aliveNow + 1
                    Next j
                    If aliveNow = 0 Then Gosub FreezeAtLastKill
                Else
                    hpMsg$ = "TRÄFF"
                    PlaySound SND_HIT
                End If
                hpMsgTime = Timer
            End If
            flashTime = Timer
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
            state$ = "result"
            LogMouse "LIVSTIDSLAS win->result (ingen unlock, virtuell pekare)"
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
            If Mid$(mapRow$(mapY), mapX + 1, 1) = "#" Then hit = 1
        Loop Until hit = 1
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
        Line (x, ys)-(x, ye), pal&(Int(shade))
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
                    ew = RW / edist * 0.6      ' bredd i px
                    eh = RH / edist * 0.9      ' höjd i px (står på golvet)
                    ebase = midY + RH / (2 * edist) + pitch   ' golvlinje vid edist
                    ey0 = ebase - eh
                    ey1 = ebase
                    If ey0 < 0 Then ey0 = 0
                    If ey1 > RH - 1 Then ey1 = RH - 1
                    ex0 = Int(ecx - ew / 2): ex1 = Int(ecx + ew / 2)
                    If ex0 < 0 Then ex0 = 0
                    If ex1 > RW - 1 Then ex1 = RW - 1
                    ' avståndsskuggning som väggarna, skalad till kroppsfärgen
                    eshade = 255 - edist * 15
                    If eshade < 40 Then eshade = 40
                    ebody& = _RGB32(Int(170 * eshade / 255), Int(35 * eshade / 255), Int(35 * eshade / 255))
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
    _PutImage (0, 0)-(RW - 1, RH - 1), buf&
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
' SpawnEnemies: startlägen för fiende-poolen (öppna rutor på kartan).
' Anropas vid init och vid full reset (R i dead-läget).
SpawnEnemies:
    For i = 0 To 10
        enActive(i) = 0
        enHP(i) = 3          ' 3 träffar tar död på en fiende
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
    Next i
    bfsForX = -1: bfsForY = -1
    ' Spawn-balans (2026-11-23): en0/en3 flyttade bort från startspawn (8.5,4.5) -
    ' tidigare hade en0 (13.5,4.5) fri LOS i rad 4 (dist 5) och en3 (5.5,1.5) fri LOS
    ' via (6,2)(7,3)(8,4) (dist 4.2) -> JAKT direkt vid spelstart. Nu bakom vägg OCH
    ' dist >= 6 (LOS-tröskeln): en0 nere höger (LOS bruten av vägg 12,8, dist 7.1),
    ' en3 övre vänster hörnet (LOS bruten av vägg 4,2, dist 6.7). en1/en2 oförändrade.
    enX(0) = 13.5: enY(0) = 9.5:  enActive(0) = 1: enSpd(0) = 0.5
    enLx(0) = enX(0): enLy(0) = enY(0): enTx(0) = 13: enTy(0) = 9
    enX(1) = 10.5: enY(1) = 9.5:  enActive(1) = 1: enSpd(1) = 0.4
    enLx(1) = enX(1): enLy(1) = enY(1): enTx(1) = 10: enTy(1) = 9
    enX(2) = 2.5:  enY(2) = 12.5: enActive(2) = 1: enSpd(2) = 0.35
    enLx(2) = enX(2): enLy(2) = enY(2): enTx(2) = 2: enTy(2) = 12
    enX(3) = 2.5:  enY(3) = 1.5:  enActive(3) = 1: enSpd(3) = 0.55
    enLx(3) = enX(3): enLy(3) = enY(3): enTx(3) = 2: enTy(3) = 1
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
    px = 8.5: py = 4.5: angle = 0: pitch = 0
    For i = 0 To 10
        If i <= 4 Then pkActive(i) = 1 Else pkActive(i) = 0
        If i <= 2 Then amActive(i) = 1 Else amActive(i) = 0
    Next i
    Gosub SpawnEnemies
    hpMsg$ = "": hpMsgTime = 0
    lastShotTime = -1: tracerTime = -1: flashTime = -1: flashDist = 99
    deathTime = 0: hover = 0: prevHover = 0: winPending = 0: runTimeFrozen = -1   ' VIDARE: reset tid 0 (ej fryst)
    runT0 = Timer: shotsFired = 0: dmgTaken = 0
    ' SKYDD mot fastnad rörelse efter övergång (t.ex. VIDARE): nollställ ALLE
    ' rörelse-flaggor INNAN state=fadeout och töm tangentbords-buffertarna
    ' (INKEY$/_KEYHIT) så inga key-repeats från föregående skärm överlever.
    mvF = 0: mvB = 0: mvL = 0: mvR = 0: turnL = 0: turnR = 0: fireBtn = 0
    _KeyClear
    state$ = "fadeout"
    fadeT0 = Timer
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
    For lguard = 1 To 64
        If lsdx < lsdy Then
            lsdx = lsdx + lddx: lmx = lmx + lstepX
        Else
            lsdy = lsdy + lddy: lmy = lmy + lstepY
        End If
        If lmx < 0 Or lmx > 15 Or lmy < 0 Or lmy > 15 Then Exit For
        If Mid$(mapRow$(lmy), lmx + 1, 1) = "#" Then losOK = 0: Exit For
        If lmx = ltx And lmy = lty Then Exit For
    Next lguard
    Return

' BFSCompute: avståndskarta bfsD(x,y) från målcell (bfsTX,bfsTY), BFS 4-riktning över
' öppna celler (kartan är 16x16, liten). Sätts bfsForX/bfsForY till målcellen.
BFSCompute:
    For yy = 0 To 15
        For xx = 0 To 15
            bfsD(xx, yy) = -1
        Next xx
    Next yy
    If bfsTX < 0 Or bfsTX > 15 Or bfsTY < 0 Or bfsTY > 15 Then bfsForX = -1: bfsForY = -1: Return
    If Mid$(mapRow$(bfsTY), bfsTX + 1, 1) = "#" Then bfsForX = -1: bfsForY = -1: Return
    qh = 0: qt = 0
    qx(0) = bfsTX: qy(0) = bfsTY: bfsD(bfsTX, bfsTY) = 0: qt = 1
    While qh < qt
        cx = qx(qh): cy = qy(qh): qh = qh + 1
        cd = bfsD(cx, cy) + 1
        If cx + 1 <= 15 Then If Mid$(mapRow$(cy), cx + 2, 1) <> "#" Then If bfsD(cx + 1, cy) = -1 Then bfsD(cx + 1, cy) = cd: qx(qt) = cx + 1: qy(qt) = cy: qt = qt + 1
        If cx - 1 >= 0 Then If Mid$(mapRow$(cy), cx, 1) <> "#" Then If bfsD(cx - 1, cy) = -1 Then bfsD(cx - 1, cy) = cd: qx(qt) = cx - 1: qy(qt) = cy: qt = qt + 1
        If cy + 1 <= 15 Then If Mid$(mapRow$(cy + 1), cx + 1, 1) <> "#" Then If bfsD(cx, cy + 1) = -1 Then bfsD(cx, cy + 1) = cd: qx(qt) = cx: qy(qt) = cy + 1: qt = qt + 1
        If cy - 1 >= 0 Then If Mid$(mapRow$(cy - 1), cx + 1, 1) <> "#" Then If bfsD(cx, cy - 1) = -1 Then bfsD(cx, cy - 1) = cd: qx(qt) = cx: qy(qt) = cy - 1: qt = qt + 1
    Wend
    bfsForX = bfsTX: bfsForY = bfsTY
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
                px = 8.5: py = 4.5: angle = 0: hp = 100: ammo = 5
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
                    ' fas 12: seger-trigger-test (kill-all -> result -> tangent -> omladdning)
                    testPhase = 12: testT0 = Timer: testFlag = 0
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
    End Select
    Return

