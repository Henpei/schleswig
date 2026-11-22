' ============================================================================
' RAYCASTER  -- raycaster-demo / FPS i QB64-PE (Linux/Wayland)
' ============================================================================
' VAD: Wolfenstein/Doom-liknande raycaster (DDA) med titelmeny, mouselook (yaw),
'      pitch via y-shearing, HP, medkit/ammo-pickups, skjutning + HP-regen (Fas 2),
'      klickbar START GAME-knapp med hover-tick/klick-ljud och fade-overgang (Fas 2.5),
'      dodsskarm + full reset vid R/SPACE (Fas 2.6).
'
' KÖRINSTRUKTIONER:
'   ./Raycaster
'   SPACE = starta spelet (från titelmenyn), ESC = avsluta (fungerar i båda lägen)
'   WASD = gå/strafe, musen = titta runt. Muslåset (pointer lock) aktiveras
'   FÖRST när state = "playing" -- i menyn är pekaren synlig.
'
' Byggd med qb64pe från grenen wayland-backend. Byggdatum: 2026-11-22
' ============================================================================
'
' Raycaster i QB64 (Linux) - 1920x1080, WASD + mouselook, FPS-matare, ingen LIMIT
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
        ttx = (RW - Len("RAYCASTER") * 8) \ 2
        tty = RH \ 2 - 40
        Color _RGB32(120, 60, 0)
        _PrintString (ttx + 3, tty + 3), "RAYCASTER"
        _PrintString (ttx - 2, tty), "RAYCASTER"
        Color _RGB32(255, 200, 0)
        _PrintString (ttx, tty), "RAYCASTER"
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
        tx = btnX0 + (btnW - Len("START GAME") * 8) \ 2
        ty = btnY0 + (btnH - 16) \ 2
        Color _RGB32(0, 0, 0)
        _PrintString (tx + 2, ty + 2), "START GAME"   ' skugga -> fet stil
        Color btnText&
        _PrintString (tx, ty), "START GAME"
        Color _RGB32(150, 150, 150)
        _PrintString ((RW - Len("(eller SPACE)") * 8) \ 2, btnY1 + 16), "(eller SPACE)"
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
        If k$ = "r" Or k$ = "R" Or k$ = " " Or _KeyDown(Asc("R")) Or _KeyDown(32) Then
            ' reset ALLT -> tillbaka till menyn
            hp = 100: ammo = 20
            px = 8.5: py = 4.5: angle = 0: pitch = 0
            For i = 0 To 10
                If i <= 4 Then pkActive(i) = 1 Else pkActive(i) = 0
                If i <= 2 Then amActive(i) = 1 Else amActive(i) = 0
            Next i
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
            dtx = (RW - Len("DU DÖ") * 8) \ 2
            dty = RH \ 2 - 40
            Color _RGB32(120, 0, 0)
            _PrintString (dtx + 3, dty + 3), "DU DÖ"
            _PrintString (dtx - 2, dty), "DU DÖ"
            Color _RGB32(220, 0, 0)
            _PrintString (dtx, dty), "DU DÖ"
            Color _RGB32(200, 200, 200)
            _PrintString ((RW - Len("Tryck R för att starta om") * 8) \ 2, RH \ 2 + 40), "Tryck R för att starta om"
        End If
        _Display
    Else

    If k$ = Chr$(27) Or _KeyDown(27) Then End
    ' debug-knapp: G = -5 HP (min 0), bara i playing-läge
    If k$ = "g" Or k$ = "G" Or _KeyDown(Asc("G")) Then
        hp = hp - 5
        If hp < 0 Then hp = 0
        hpMsg$ = "-5 HP"
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
                hpMsg$ = "+25 HP"
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
                hpMsg$ = "+10 AMMO"
                hpMsgTime = Timer
            End If
        End If
    Next i

    ' ======== SKJUTNING: vänster musknapp, cooldown 0.3 s ========
    If _MouseButton(1) And Timer - lastShotTime >= 0.3 Then
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
                             ' döljs av väggen i just den kolumnen
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
                        If pdist < wallDist(sx) Then Line (sx, pbase - ph)-(sx, pbase), _RGB32(200, 30, 30)
                    Next sx
                    ' pcx kan hamna utanför skärmen när |pang| närmar sig
                    ' synfältet (0.66 rad) -> clampa innan wallDist-index,
                    ' annars "subscript out of range" (wallDist är 0..RW-1).
                    cx = Int(pcx)
                    If cx < 0 Then cx = 0
                    If cx > RW - 1 Then cx = RW - 1
                    If x0 <= x1 Then
                        If pdist < wallDist(cx) Then
                            Line (cx, pbase - ph)-(cx, pbase), _RGB32(255, 255, 255)
                            Line (x0, pbase - ph / 2)-(x1, pbase - ph / 2), _RGB32(255, 255, 255)
                        End If
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
                    pcx = RW / 2 * (1 + Tan(pang) / planeDist)
                    pw = RW / pdist * 0.25
                    ph = RH / pdist * 0.25
                    pbase = midY + RH / (2 * pdist) + pitch
                    x0 = Int(pcx - pw / 2): x1 = Int(pcx + pw / 2)
                    If x0 < 0 Then x0 = 0
                    If x1 > RW - 1 Then x1 = RW - 1
                    For sx = x0 To x1
                        If pdist < wallDist(sx) Then Line (sx, pbase - ph)-(sx, pbase), _RGB32(230, 200, 0)
                    Next sx
                End If
            End If
        End If
    Next i

    ' ======== HUD: debug-rad, HP-bar, ammo, transient meddelande ======

    _Dest display&
    _PutImage (0, 0)-(RW - 1, RH - 1), buf&
    Color _RGB32(255, 255, 0)
    _PrintString (0, 0), "FPS:" + Str$(fpsShow) + " mmx:" + Str$(mmx) + " mmy:" + Str$(mmy) + " ang:" + Str$(Int(angle * 57.2958)) + " x:" + LTrim$(Str$(px)) + " y:" + LTrim$(Str$(py)) + " pitch:" + Str$(Int(pitch))

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
    _PrintString (hpX1 + 8, hudY + 4), "HP:" + Str$(Int(hp))
    ' ammo-ruta relativt HP-boxens bredd/högerkant (gul kant = ammo-pickups)
    amX0 = hpX1 + Int(RW * 104 / 1920): amW = Int(RW * 100 / 1920): amX1 = amX0 + amW
    Line (amX0, hudY)-(amX1, hudY + 20), _RGB32(40, 40, 40), BF
    Line (amX0, hudY)-(amX1, hudY + 20), _RGB32(230, 200, 0), B
    Line (amX0 + 1, hudY + 1)-(amX1 - 1, hudY + 19), _RGB32(230, 200, 0), B
    Color _RGB32(230, 200, 0)
    _PrintString (amX1 + 8, hudY + 4), "AMMO:" + Str$(ammo)
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
    If curTime - lastTime >= 1 Then
        fpsShow = Int(frames / (curTime - lastTime))
        _Title "Raycaster - FPS: " + LTrim$(Str$(fpsShow))
        frames = 0
        lastTime = curTime
    End If
LOOP

