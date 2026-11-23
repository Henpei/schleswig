' ============================================================================
' SCHLESWIG v0.1.0  -- raycaster-FPS i QB64-PE (Linux/Wayland)
' ============================================================================
' VAD: Wolfenstein/Doom-liknande raycaster (DDA) med titelmeny, mouselook (yaw),
'      pitch via y-shearing, HP, medkit/ammo-pickups, skjutning + HP-regen (Fas 2),
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
RW = _Width(display&)
RH = _Height(display&)
' aspektjusterad projektion: vertikal FOV konstant (0.66 vid 16:9), horisonten
' breddas automatiskt på bredare format (21:9/32:9). Vid 1920x1080 blir båda = 0.66.
planeDist = 0.66 * (16 / 9) / (RW / RH)
fovCut = 0.66 * (RW / RH) / (16 / 9)
buf& = _NewImage(RW, RH, 32)
' Fas 2.5: meny-knapp + ljud + fade-overgang (knappgeometri relativ RW/RH)
btnW = Int(RW * 360 / 1920): btnH = Int(RH * 60 / 1080)
btnX0 = (RW - btnW) \ 2: btnY0 = RH \ 2 + Int(RH * 40 / 1080)
btnX1 = btnX0 + btnW: btnY1 = btnY0 + btnH
hover = 0: prevHover = 0
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
moveStep = 0.01
turnStep = 0.04
mouseSens = 0.002
Const pitchSens = 2
' Version (semver-light): MINOR = stor fas, PATCH = fix, 1.0.0 = fullständig spelarkrets.
' Placering: git-tagg (v0.1.0) + denna rad + titelskärm-hörn + _Title.
Const ver$ = "v0.1.0"

' ===== SPELTEXT (centraliserad enligt GPLv3-PREP 2026-11-23) =================
' All användarvisad text samlas här. Svenska nu -- vid release 1.0+ översätts
' denna sektion till engelska (och LICENSE/README läggs till). Selftestets
' loggsträngar (stMsg$) är diagnostik och ligger kvar vid selftest-koden.
Const strAppName$ = "Schleswig"                    ' fönstertitel (_Title)
Const strTitle$ = "SCHLESWIG"                      ' stor titel på titelskärmen
Const strStartBtn$ = "START GAME"                  ' menyknapp
Const strOrSpace$ = "(eller SPACE)"               ' rad under menyknappen
Const strDead$ = "DU DÖ"                           ' dödsskärm, stor text
Const strRestart$ = "Tryck R för att starta om"    ' dödsskärm, rad 2
Const strHudHp$ = "HP:"                            ' HUD-etikett
Const strHudAmmo$ = "AMMO:"                        ' HUD-etikett
Const strFps$ = "FPS:"                             ' debug-rad + fönstertitel
Const strDmgDebug$ = "-5 HP"                       ' debug-knapp G
Const strMedkit$ = "+25 HP"                        ' medkit-pickup
Const strAmmoPick$ = "+10 AMMO"                    ' ammo-pickup
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

' Fas 2: ammo + skjutning + HP-regen (samma array-pool-mönster som medkit)
DIM amX(10), amY(10), amActive(10)
ammo = 20
lastShotTime = -1        ' cooldown 0.3 s mellan skott
tracerTime = -1          ' tracer-flash synlig 2-3 frames
flashTime = -1           ' träff-flash
flashDist = 99
lastDamageTime = Timer   ' HP-regen börjar först 5 s efter senaste skada
amX(0) = 3.5: amY(0) = 4.5: amActive(0) = 1
amX(1) = 12.5: amY(1) = 4.5: amActive(1) = 1
amX(2) = 6.5: amY(2) = 9.5: amActive(2) = 1

' Fas 3/3.1: fiende-pool (samma array-pool-mönster som pickups): pos, aktiv flagga,
' hp (3 träffar), skada, hastighet + AI-tillstånd. Startlägen i SpawnEnemies.
' enState: 0=PATROLL, 1=JAKT, 2=ANFALL. bfsD = BFS-avståndskarta (flödesfält).
DIM enX(10), enY(10), enActive(10), enHP(10), enDmg(10), enSpd(10), enLastHit(10)
DIM enState(10), enSeen(10), enTx(10), enTy(10), enPatrolT(10), enLastSeen(10)
DIM enLx(10), enLy(10), enCalmT(10), bfsD(15, 15), qx(255), qy(255)
' Fas 3 selftest/autoplay: ./schleswig/schleswig selftest -> scriptat scenario, loggas till fil
selftest = 0
cmdArg$ = LCase$(LTrim$(RTrim$(Command$)))   ' Obs: Trim$ finns inte i QB64-PE, bara LTrim$/RTrim$
If cmdArg$ = "selftest" Then selftest = 1
testPhase = 0: testT0 = Timer: stMsg$ = "": testDbg = 0: testHb = Timer: testFlag = 0
If selftest Then
    stF = FreeFile
    Open "/tmp/schleswig_selftest.log" For Output As #stF
    Close #stF
    state$ = "playing"          ' hoppa över menyn direkt
    _MOUSEHIDE _DISABLE
    Gosub SpawnEnemies
    ' Fas 3.1-scenario: EN fiende i PATROLL utan LOS till spelaren (10.5,6.5)->(8.5,4.5)
    For i = 1 To 10: enActive(i) = 0: Next i
    px = 8.5: py = 4.5: angle = 0: hp = 100: ammo = 20
    enX(0) = 10.5: enY(0) = 6.5: enActive(0) = 1
    enHP(0) = 3: enDmg(0) = 10: enSpd(0) = 2
    enState(0) = 0: enLastHit(0) = 0: enLastSeen(0) = 0: enCalmT(0) = 0
    enLx(0) = enX(0): enLy(0) = enY(0)
    enTx(0) = 10: enTy(0) = 5: enPatrolT(0) = Timer   ' deterministiskt patrullmål
    bfsForX = -1: bfsForY = -1
    stMsg$ = "selftest start: fas1 patrull (10.5,6.5)": Gosub STLog
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

    ' ======== STATE-MACHINE: menu <-> playing (SPACE startar, ESC avslutar) ========
    If state$ = "menu" Or state$ = "fadeout" Then
        If state$ = "menu" And (k$ = Chr$(27) Or _KeyDown(27)) Then End
        While _MouseInput: WEND   ' töm muskön så _MouseX/Y/_MouseButton blir färska här
        mx = _MouseX: my = _MouseY
        hover = 0
        If mx >= btnX0 And mx <= btnX1 And my >= btnY0 And my <= btnY1 Then hover = 1
        If hover <> prevHover Then
            prevHover = hover
            If hover = 1 Then SOUND 1500, 1   ' hover-tick
        End If
        If state$ = "menu" And k$ = " " Then
            state$ = "fadeout": fadeT0 = Timer
            SOUND 300, 2: SOUND 150, 3        ' klick/plopp
        End If
        If state$ = "menu" And hover = 1 Then
            If _MouseButton(1) Then
                state$ = "fadeout": fadeT0 = Timer
                SOUND 300, 2: SOUND 150, 3
            End If
        End If
        _Dest display&
        Line (0, 0)-(RW - 1, RH - 1), _RGB32(8, 8, 24), BF
        Line (RW \ 2 - 860, RH \ 2 - 190)-(RW \ 2 + 859, RH \ 2 + 189), _RGB32(255, 200, 0), B
        Color _RGB32(255, 200, 0)
        ttx = (RW - Len(strTitle$) * 8) \ 2
        tty = RH \ 2 - 40
        Color _RGB32(120, 60, 0)
        _PrintString (ttx + 3, tty + 3), strTitle$
        _PrintString (ttx - 2, tty), strTitle$
        Color _RGB32(255, 200, 0)
        _PrintString (ttx, tty), strTitle$
        ' START GAME-knapp: centrerad rektangel, hover = highlight
        If hover = 1 Then
            btnFill& = _RGB32(255, 200, 0)
            btnText& = _RGB32(20, 20, 20)
        Else
            btnFill& = _RGB32(30, 30, 70)
            btnText& = _RGB32(255, 255, 255)
        End If
        Line (btnX0, btnY0)-(btnX1, btnY1), btnFill&, BF
        Line (btnX0, btnY0)-(btnX1, btnY1), _RGB32(255, 255, 255), B
        tx = btnX0 + (btnW - Len(strStartBtn$) * 8) \ 2
        ty = btnY0 + (btnH - 16) \ 2
        Color _RGB32(0, 0, 0)
        _PrintString (tx + 2, ty + 2), strStartBtn$   ' skugga -> fet stil
        Color btnText&
        _PrintString (tx, ty), strStartBtn$
        Color _RGB32(150, 150, 150)
        _PrintString ((RW - Len(strOrSpace$) * 8) \ 2, btnY1 + 16), strOrSpace$
        ' versionshörn nere till höger på titelskärmen
        Color _RGB32(110, 110, 140)
        _PrintString (RW - Len(ver$) * 8 - 16, RH - 24), ver$
        ' fade-through-black: titel fade:ar ut (0.4 s), sedan spelet fade:ar in
        If state$ = "fadeout" Then
            fa = (Timer - fadeT0) / 0.4
            If fa > 1 Then fa = 1
            Line (0, 0)-(RW - 1, RH - 1), _RGBA32(0, 0, 0, Int(fa * 255)), BF
            If fa >= 1 Then
                state$ = "playing"
                _MOUSEHIDE _DISABLE
                fadeT0 = Timer
                fading = 2
            End If
        End If
        _Display
    ElseIf state$ = "dead" Then
        If k$ = Chr$(27) Or _KeyDown(27) Then End
        ' Fas 3.1 selftest: fas 8 = spelaren har dött av fiende -> fas 9 spawn-audit -> avsluta
        If selftest And testPhase = 8 Then
            stMsg$ = "PASS fas8-spelare-kan-do (hp=0, state=dead)": Gosub STLog
            ' fas 9: spawn-audit pa AKTA startlage (SpawnEnemies) innan vi avslutar
            state$ = "playing"
            hp = 100: ammo = 20
            px = 8.5: py = 4.5: angle = 0: pitch = 0
            Gosub SpawnEnemies
            testPhase = 9: testT0 = Timer: testFlag = 0
        End If
        If k$ = "r" Or k$ = "R" Or k$ = " " Or _KeyDown(Asc("R")) Or _KeyDown(32) Then
            ' reset ALLT -> tillbaka till menyn
            hp = 100: ammo = 20
            px = 8.5: py = 4.5: angle = 0: pitch = 0
            For i = 0 To 10
                If i <= 4 Then pkActive(i) = 1 Else pkActive(i) = 0
                If i <= 2 Then amActive(i) = 1 Else amActive(i) = 0
            Next i
            Gosub SpawnEnemies   ' Fas 3: fiender respawnas också vid full reset
            lastDamageTime = Timer
            hpMsg$ = "": hpMsgTime = 0
            lastShotTime = -1: tracerTime = -1: flashTime = -1: flashDist = 99
            fading = 0: deathTime = 0
            hover = 0: prevHover = 0
            state$ = "menu"
            _MOUSESHOW
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
        End If
        _Display
    Else

    If k$ = Chr$(27) Or _KeyDown(27) Then End
    ' debug-knapp: G = -5 HP (min 0), bara i playing-läge
    If k$ = "g" Or k$ = "G" Or _KeyDown(Asc("G")) Then
        hp = hp - 5
        If hp < 0 Then hp = 0
        hpMsg$ = strDmgDebug$
        hpMsgTime = Timer
        lastDamageTime = Timer   ' G räknas som skada: resetta regen-grace
    End If
    If k$ = Chr$(0) + "K" Or _KeyDown(19200) Then angle = angle - turnStep * speed
    If k$ = Chr$(0) + "M" Or _KeyDown(19712) Then angle = angle + turnStep * speed

    dirX = Cos(angle)
    dirY = Sin(angle)

    If k$ = "w" Or k$ = "W" Or _KeyDown(Asc("W")) Or _KeyDown(Asc("w")) Then
        nx = px + dirX * moveStep * speed
        ny = py + dirY * moveStep * speed
        If Mid$(mapRow$(Int(py)), Int(nx + Sgn(nx - px) * 0.2) + 1, 1) <> "#" Then px = nx
        If Mid$(mapRow$(Int(ny + Sgn(ny - py) * 0.2)), Int(px) + 1, 1) <> "#" Then py = ny
    End If
    If k$ = "s" Or k$ = "S" Or _KeyDown(Asc("S")) Or _KeyDown(Asc("s")) Then
        nx = px - dirX * moveStep * speed
        ny = py - dirY * moveStep * speed
        If Mid$(mapRow$(Int(py)), Int(nx + Sgn(nx - px) * 0.2) + 1, 1) <> "#" Then px = nx
        If Mid$(mapRow$(Int(ny + Sgn(ny - py) * 0.2)), Int(px) + 1, 1) <> "#" Then py = ny
    End If
    If k$ = "a" Or k$ = "A" Or _KeyDown(Asc("A")) Or _KeyDown(Asc("a")) Then
        nx = px + dirY * moveStep * 0.6 * speed
        ny = py - dirX * moveStep * 0.6 * speed
        If Mid$(mapRow$(Int(py)), Int(nx + Sgn(nx - px) * 0.2) + 1, 1) <> "#" Then px = nx
        If Mid$(mapRow$(Int(ny + Sgn(ny - py) * 0.2)), Int(px) + 1, 1) <> "#" Then py = ny
    End If
    If k$ = "d" Or k$ = "D" Or _KeyDown(Asc("D")) Or _KeyDown(Asc("d")) Then
        nx = px - dirY * moveStep * 0.6 * speed
        ny = py + dirX * moveStep * 0.6 * speed
        If Mid$(mapRow$(Int(py)), Int(nx + Sgn(nx - px) * 0.2) + 1, 1) <> "#" Then px = nx
        If Mid$(mapRow$(Int(ny + Sgn(ny - py) * 0.2)), Int(px) + 1, 1) <> "#" Then py = ny
    End If

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
            End If
        End If
    Next i

    ' ammo-pickups: avstånd < 0.5 tiles ger +10 ammo
    For i = 0 To 10
        If amActive(i) Then
            If Sqr((amX(i) - px) ^ 2 + (amY(i) - py) ^ 2) < 0.5 Then
                amActive(i) = 0
                ammo = ammo + 10
                hpMsg$ = strAmmoPick$
                hpMsgTime = Timer
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
                If edist >= 0.8 Then enState(i) = 1     ' fri sikt + inom 6 celler -> JAKT
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
            ' närstridsskada (oförändrad mekanik från Fas 3): dist<0.8, cooldown 0.7 s,
            ' lastDamageTime uppdateras -> HP-regen blockas (samma grace som Fas 2)
            If edist < 0.8 And Timer - enLastHit(i) >= 0.7 Then
                enLastHit(i) = Timer
                hp = hp - enDmg(i)
                lastDamageTime = Timer
                hpMsg$ = "-" + Str$(enDmg(i)) + " HP"
                hpMsgTime = Timer
            End If
        End If
    Next i

    ' ======== SKJUTNING: vänster musknapp (fireBtn), cooldown 0.3 s ========
    If fireBtn And Timer - lastShotTime >= 0.3 Then
        lastShotTime = Timer
        If ammo > 0 Then
            ammo = ammo - 1
            tracerTime = Timer
            pitch = pitch + 6   ' liten rekyl-puff
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
                Else
                    hpMsg$ = "TRÄFF"
                End If
                hpMsgTime = Timer
            End If
            flashTime = Timer
        Else
            hpMsg$ = "CLICK"
            hpMsgTime = Timer
        End If
    End If

    ' ======== HP-REGEN: +1 HP/s, först efter 5 s grace sedan senaste skada ========
    If Timer - lastDamageTime >= 5 Then
        hp = hp + dt
        If hp > 100 Then hp = 100
    End If

    ' ======== DÖD (Fas 2.6): hp<=0 i playing -> dead; ingen regen/resurrection efter detta ======
    If hp <= 0 Then
        hp = 0
        state$ = "dead"
        deathTime = Timer
        _MOUSESHOW   ' slapp pointer-lock vid död
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
            stMsg$ = "SELFTEST OK"
            Gosub STLog
        Else
            stMsg$ = "FAIL fas10-occlusion eyesOK=" + Str$(eyesOK) + " frontOK=" + Str$(frontOK) + " behindOK=" + Str$(behindOK) + " eyePix=" + Str$(eyePix&) + " frontPix=" + Str$(pkFrontPix&) + " frontPix2=" + Str$(pkFrontPix2&) + " behindPix=" + Str$(pkBehindPix&) + " apdistP=" + LTrim$(Str$(Int(apdistP * 100) / 100)) + " wallDist=" + LTrim$(Str$(Int(wallDist(apcx) * 100) / 100)) + " RW=" + Str$(RW) + " RH=" + Str$(RH) + " apcx=" + Str$(apcx)
            Gosub STLog
            stMsg$ = "SELFTEST FAIL"
            Gosub STLog
        End If
        End
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
        stMsg$ = "alive phase=" + Str$(testPhase) + " state=" + state$ + " hp=" + Str$(Int(hp)) + " en0=(" + LTrim$(Str$(Int(enX(0) * 10) / 10)) + "," + LTrim$(Str$(Int(enY(0) * 10) / 10)) + ") st=" + Str$(enState(0)) + " act=" + Str$(enActive(0))
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
            If testFlag = 0 Then
                testFlag = 1
                px = 2.5: py = 12.5
                stMsg$ = "fas4: spelaren gömmer sig (2.5,12.5), väntar på återgång PATROLL"
                Gosub STLog
            End If
            If enState(0) = 0 Then
                stMsg$ = "PASS fas4-forlorad-syn-atergang-PATROLL efter " + LTrim$(Str$(Int((Timer - testT0) * 10) / 10)) + "s"
                Gosub STLog
                ' förbered gamla Fas 3-kombattestet (fas5-8)
                px = 8.5: py = 4.5: angle = 0: hp = 100: ammo = 20
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
                    px = 8.5: py = 4.5: angle = 3.14159265 / 2: pitch = 0: hp = 100: ammo = 20
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
    End Select
    Return

