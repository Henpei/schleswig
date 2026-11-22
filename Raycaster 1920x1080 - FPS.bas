' ============================================================================
' RAYCASTER 1920x1080 - FPS  -- raycaster-demo / FPS i QB64-PE (Linux/Wayland)
' ============================================================================
' VAD: Wolfenstein/Doom-liknande raycaster (DDA) med titelmeny, mouselook (yaw),
'      pitch via y-shearing, HP, medkit/ammo-pickups, skjutning + HP-regen (Fas 2).
'
' KÖRINSTRUKTIONER:
'   ./Raycaster 1920x1080 - FPS
'   SPACE = starta spelet (från titelmenyn), ESC = avsluta (fungerar i båda lägen)
'   WASD = gå/strafe, musen = titta runt. Muslåset (pointer lock) aktiveras
'   FÖRST när state = "playing" -- i menyn är pekaren synlig.
'
' Byggd med qb64pe från grenen wayland-backend. Byggdatum: 2026-11-22
' ============================================================================
'
' Raycaster i QB64 (Linux) - 1920x1080, WASD + mouselook, FPS-matare, ingen LIMIT
' ======== INITIERING: fönster, GL, karta, variabler, pickups ========
display& = _NewImage(1920, 1080, 32)
Screen display&
_FullScreen
buf& = _NewImage(960, 540, 32)
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

Const RW = 960
Const RH = 540

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
    If state$ = "menu" Then
        If k$ = Chr$(27) Or _KeyDown(27) Then End
        If k$ = " " Then
            state$ = "playing"
            _MOUSEHIDE _DISABLE
        End If
        _Dest display&
        Line (0, 0)-(1919, 1079), _RGB32(8, 8, 24), BF
        Line (100, 350)-(1819, 729), _RGB32(255, 200, 0), B
        Color _RGB32(255, 200, 0)
        _PrintString (884, 500), "RAYCASTER 1920x1080"
        Color _RGB32(200, 200, 200)
        _PrintString (916, 570), "Tryck SPACE"
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

    ' ======== RENDERING: DDA-väggloop (fyller även wallDist för sprites) ========
    _Dest buf&
    midY = RH \ 2
    Line (0, 0)-(RW - 1, midY - 1 + pitch), ceilingCol&, BF
    Line (0, midY + pitch)-(RW - 1, RH - 1), floorCol&, BF

    planeX = -dirY * 0.66
    planeY = dirX * 0.66

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
                If Abs(pang) < 0.66 Then
                    ' projektionsformeln: vägg-loopen har cameraX = 2*x/RW-1 och
                    ' plan = 0.66*dir, dvs tan(pang) = 0.66*cameraX. Omvänt blir
                    ' skärmkolumnen pcx = RW/2*(1 + Tan(pang)/0.66), där pang är
                    ' vinkeln till pickupen relativt spelarens riktning.
                    pcx = RW / 2 * (1 + Tan(pang) / 0.66)
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
                If Abs(pang) < 0.66 Then
                    pcx = RW / 2 * (1 + Tan(pang) / 0.66)
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
    _PutImage (0, 0)-(1919, 1079), buf&
    Color _RGB32(255, 255, 0)
    _PrintString (8, 8), "FPS:" + Str$(fpsShow) + " mmx:" + Str$(mmx) + " mmy:" + Str$(mmy) + " ang:" + Str$(Int(angle * 57.2958)) + " x:" + LTrim$(Str$(px)) + " y:" + LTrim$(Str$(py)) + " pitch:" + Str$(Int(pitch))

    ' HP-ruta nertill: bar-längd + siffra (tydligt även utan färgseende)
    Line (8, 1052)-(216, 1072), _RGB32(40, 40, 40), BF
    Line (8, 1052)-(216, 1072), _RGB32(255, 255, 255), B
    Line (9, 1053)-(215, 1071), _RGB32(255, 255, 255), B
    If hp > 50 Then
        barCol& = _RGB32(0, 200, 0)
    ElseIf hp >= 25 Then
        barCol& = _RGB32(220, 200, 0)
    Else
        barCol& = _RGB32(220, 0, 0)
    End If
    If hp > 0 Then Line (10, 1054)-(10 + hp * 2, 1070), barCol&, BF
    Color _RGB32(255, 255, 255)
    _PrintString (224, 1056), "HP:" + Str$(Int(hp))
    ' ammo-ruta bredvid HP-boxen (gul kant = ammo-pickups)
    Line (320, 1052)-(420, 1072), _RGB32(40, 40, 40), BF
    Line (320, 1052)-(420, 1072), _RGB32(230, 200, 0), B
    Line (321, 1053)-(419, 1071), _RGB32(230, 200, 0), B
    Color _RGB32(230, 200, 0)
    _PrintString (428, 1056), "AMMO:" + Str$(ammo)
    If Timer - hpMsgTime < 2 Then
        Color _RGB32(0, 255, 0)
        _PrintString (560, 1056), hpMsg$
    End If
    ' tracer-flash (vitt streck från skärm-mitt) + träff-flash, 2-3 frames
    If Timer - tracerTime < 0.05 Then Line (960, 540)-(960, 390), _RGB32(255, 255, 255)
    If Timer - flashTime < 0.05 Then
        fs = 300 / flashDist
        If fs < 4 Then fs = 4
        If fs > 60 Then fs = 60
        Line (960 - fs, 540 + pitch * 2 - fs)-(960 + fs, 540 + pitch * 2 + fs), _RGB32(255, 220, 80), BF
    End If
    _Display

    End If

    frames = frames + 1
    If curTime - lastTime >= 1 Then
        fpsShow = Int(frames / (curTime - lastTime))
        _Title "Raycaster 1920x1080 - FPS: " + LTrim$(Str$(fpsShow))
        frames = 0
        lastTime = curTime
    End If
LOOP

