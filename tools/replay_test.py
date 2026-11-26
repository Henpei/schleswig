#!/usr/bin/env python3
"""6G real-app-path input test: runs the NORMAL binary (arg "replay <map>") headless
(SDL dummy drivers) and drives it through the REAL app flow menu -> StartRun ->
fade -> playing with a scripted key timeline (/tmp/schleswig_replay.scr, scheduled
on the game's monotonic replayClk& frame counter). The game polls KeyDown2% (the
SAME predicate real _KeyDown feeds) via keySim%, and InKey$ (k$) for menu taps.
Telemetry lands in /tmp/schleswig_replay.log; this script asserts there:
W/A/S/D move the player, releasing stops it within 1 frame (no sticky),
Shift+W sprints at spdMul 1.5 and drains stamina, releasing Shift drops to 1.

Usage: python3 tools/replay_test.py [path-to-schleswig-binary]
Exit 0 = all assertions PASS.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "schleswig")
SCR = "/tmp/schleswig_replay.scr"
LOG = "/tmp/schleswig_replay.log"
MAP = "/tmp/schleswig_replay_map.map"

# 32x32 arena: player S south-west, one melee FOOT far north-east behind a wall
# block (keeps the win-trigger from firing and the player safe during the test)
rows = ["#" * 32]
for y in range(1, 31):
    row = ["#"] + ["."] * 30 + ["#"]
    if 8 <= y <= 24:
        row[16] = "#"   # wall block, breaks LOS
    if y == 2:
        row[29] = "F"
    if y == 29:
        row[2] = "S"
    rows.append("".join(row))
rows.append("#" * 32)
with open(MAP, "w") as f:
    f.write("\n".join(rows) + "\n")

# frame-timeline: "pN" = N frames AFTER state first becomes "playing" (fade length
# varies with fps, so absolute frames are unreliable). tap "e" = START GAME in menu.
script = [
    (5, "e"),        # main menu: E = START GAME -> StartRun -> fade -> playing
    ("p60", "W+"), ("p120", "W-"),    # W: move, release -> must stop
    ("p160", "A+"), ("p210", "A-"),
    ("p240", "S+"), ("p290", "S-"),
    ("p320", "D+"), ("p370", "D-"),
    ("p400", "SH+"), ("p405", "W+"), ("p500", "SH-"), ("p560", "W-"),  # sprint window
]
with open(SCR, "w") as f:
    for fr, tok in script:
        f.write("%s %s\n" % (fr, tok))
if os.path.exists(LOG):
    os.remove(LOG)

env = dict(os.environ)
env["SDL_VIDEODRIVER"] = "dummy"
env["SDL_AUDIODRIVER"] = "dummy"
proc = subprocess.Popen([BIN, "replay", MAP], cwd=os.path.dirname(os.path.abspath(BIN)) or ".",
                        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

deadline = time.time() + 90
lines = []
first_playing = None
while time.time() < deadline:
    if os.path.exists(LOG):
        with open(LOG) as f:
            lines = f.read().splitlines()
        if first_playing is None:
            for l in lines:
                if "st=playing" in l:
                    first_playing = int(l.split()[0][3:])
                    break
        if first_playing is not None and lines:
            try:
                if int(lines[-1].split()[0][3:]) >= first_playing + 570:
                    break
            except Exception:
                pass
    if proc.poll() is not None:
        break
    time.sleep(0.3)
proc.terminate()
try:
    proc.wait(timeout=5)
except Exception:
    proc.kill()

P = first_playing if first_playing is not None else 0   # playing-start frame

def frames_between(a, b):
    out = []
    for l in lines:
        try:
            fr = int(l.split()[0][3:])
        except Exception:
            continue
        if a <= fr <= b:
            out.append(l)
    return out

def parse(l):
    d = {}
    for part in l.split():
        if "=" in part:
            k, v = part.split("=", 1)
            d[k] = v
    return d

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("  " + detail if detail else ""))
    if not cond:
        fails.append(name)

check("menu->playing reached", first_playing is not None)

w = [parse(l) for l in frames_between(P + 60, P + 122)]
if w:
    p0 = (float(w[0]["px"]), float(w[0]["py"]))
    p1 = (float(w[-1]["px"]), float(w[-1]["py"]))
    moved = ((p1[0]-p0[0])**2 + (p1[1]-p0[1])**2) ** 0.5
    check("W moves player (KeyDown2% real path)", moved > 0.05 and any(d["mv"][0] == "1" for d in w), "moved=%.3f" % moved)
else:
    check("W moves player (KeyDown2% real path)", False, "no telemetry")

wr = [parse(l) for l in frames_between(P + 121, P + 159)]
if wr:
    p0 = (float(wr[0]["px"]), float(wr[0]["py"]))
    drift = max(((float(d["px"])-p0[0])**2 + (float(d["py"])-p0[1])**2) ** 0.5 for d in wr)
    check("W release -> stops (no sticky)", drift < 0.02 and all(d["mv"][0] == "0" for d in wr), "drift=%.4f" % drift)
else:
    check("W release -> stops (no sticky)", False, "no telemetry")

for key, a, b in (("A", P + 160, P + 210), ("S", P + 240, P + 290), ("D", P + 320, P + 370)):
    seg = [parse(l) for l in frames_between(a, b+2)]
    if seg:
        p0 = (float(seg[0]["px"]), float(seg[0]["py"]))
        p1 = (float(seg[-1]["px"]), float(seg[-1]["py"]))
        m = ((p1[0]-p0[0])**2 + (p1[1]-p0[1])**2) ** 0.5
        check("%s moves player" % key, m > 0.03, "moved=%.3f" % m)
    else:
        check("%s moves player" % key, False, "no telemetry")

sp = [parse(l) for l in frames_between(P + 406, P + 500)]
if sp:
    spds = [float(d["spd"]) for d in sp]
    stams = [float(d["stam"]) for d in sp]
    check("Shift+W sprint spd=1.5", max(spds) == 1.5, "max spd=%s" % max(spds))
    check("sprint drains stamina", len(stams) > 2 and stams[-1] < stams[0], "stam %s -> %s" % (stams[0], stams[-1]))
else:
    check("Shift+W sprint spd=1.5", False, "no telemetry")
    check("sprint drains stamina", False, "no telemetry")

post = [parse(l) for l in frames_between(P + 501, P + 559)]
if post:
    check("Shift release -> spd back to 1", all(float(d["spd"]) == 1.0 for d in post), "spd=%s" % sorted(set(d["spd"] for d in post)))
else:
    check("Shift release -> spd back to 1", False, "no telemetry")

print()
if fails:
    print("REPLAY TEST FAIL:", fails)
    sys.exit(1)
print("REPLAY TEST OK — real app path (menu->playing) keyboard input verified")
