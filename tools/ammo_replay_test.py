#!/usr/bin/env python3
"""6G ammo real-flow proof: runs the NORMAL binary (arg "replay <fixture-map>")
headless (SDL dummy drivers) through the REAL app flow menu -> StartRun ->
fade -> playing, walks the player over one ammo pickup of EACH type
(A/B/C/D) and asserts from the game's own telemetry log
(/tmp/schleswig_replay.log, "ammo=n1,n2,n3,n4" per frame) that every pool
grows by the per-type pickup amount (6H amPickup 10/4/12/2, capped per type) exactly when the player
passes over the pickup cell.

Fixture map is generated in /tmp (the real maps/*.map are NOT touched).
Layout: S=(2,29), one melee F=(29,29) due east (so 6G FIX 5 start-facing gives
angle=0 = east), pickups A=(3,29) B=(4,29) C=(5,29) D=(6,29) on the same row;
holding W walks straight over all four.

Usage: python3 tools/ammo_replay_test.py [path-to-schleswig-binary]
Exit 0 = all four ammo types proven in real flow.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "schleswig")
SCR = "/tmp/schleswig_replay.scr"
LOG = "/tmp/schleswig_replay.log"
MAP = "/tmp/schleswig_ammo_map.map"

CAPS = {1: 40, 2: 16, 3: 48, 4: 12}         # 6H capAmmo per type (musket/blunder/MG/cannon; B 12->16, D 8->12)
PICKUP = {1: 10, 2: 4, 3: 12, 4: 2}         # 6H amPickup(AMMO_N) per type (was single Const +10)
CHARS = {1: "A", 2: "B", 3: "C", 4: "D"}     # map char per ammo type
WPNAME = {1: "MUSKET", 2: "BLUNDERBUSS", 3: "MACHINE MUSKET", 4: "MINI CANNON"}   # 6L: wpName$ per ammo-typ
PX = {1: 3.5, 2: 4.5, 3: 5.5, 4: 6.5}        # pickup cell centers on row 29
PY = 29.5

# 32x32 fixture: sealed border, open row 29, S=(2,29), F=(29,29), A-D on row 29
rows = ["#" * 32]
for y in range(1, 31):
    row = ["#"] + ["."] * 30 + ["#"]
    if y == 29:
        row[2] = "S"
        row[29] = "F"
        for t, c in CHARS.items():
            row[int(PX[t])] = c
    rows.append("".join(row))
rows.append("#" * 32)
with open(MAP, "w") as f:
    f.write("\n".join(rows) + "\n")

# key timeline: tap "e" = START GAME; after playing starts hold W to walk east
# over all four pickups (pN = N frames after state first becomes "playing")
with open(SCR, "w") as f:
    f.write("5 e\n")
    f.write("p40 W+\n")
    f.write("p600 W-\n")
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
                if int(lines[-1].split()[0][3:]) >= first_playing + 620:
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

# collect playing frames and detect pool changes (the pickup events)
events = {1: None, 2: None, 3: None, 4: None}
prev = None
P = first_playing if first_playing is not None else 0
for l in lines:
    d = parse(l)
    if "fr" not in d or "ammo" not in d:
        continue
    fr = int(d["fr"])
    if fr < P or d.get("st") != "playing":
        continue
    pools = [int(x) for x in d["ammo"].split(",")]
    msg = l.split(" msg=", 1)[1].strip() if " msg=" in l else ""   # 6L: hpMsg$ (innehåller mellanslag, sist i raden)
    if prev is not None:
        for t in (1, 2, 3, 4):
            if pools[t - 1] != prev[t - 1] and events[t] is None:
                events[t] = {"fr": fr, "px": float(d["px"]), "py": float(d["py"]),
                             "before": prev[t - 1], "after": pools[t - 1], "msg": msg}
    prev = pools

print()
print("%-6s %-14s %-14s %-6s %s" % ("typ", "pool före->efter", "forvantad delta", "pos", "verdict"))
for t in (1, 2, 3, 4):
    ev = events[t]
    exp = min(PICKUP[t], CAPS[t] - (ev["before"] if ev else 0))
    if ev is None:
        print("%-6s %-14s %-14s %-6s %s" % (CHARS[t], "-", "-", "-", "FAIL (ingen pickup)"))
        check("ammo type %s (%s) picked up" % (CHARS[t], t), False, "no pool change in telemetry")
        continue
    delta = ev["after"] - ev["before"]
    near = abs(ev["px"] - PX[t]) < 0.8 and abs(ev["py"] - PY) < 0.8
    ok = (delta == exp) and near
    print("%-6s %-14s %-14s %-6s %s" % (
        CHARS[t], "%d->%d" % (ev["before"], ev["after"]), "+%d" % exp,
        "(%.2f,%.2f)" % (ev["px"], ev["py"]), "PASS" if ok else "FAIL"))
    check("ammo type %s: pool %d->%d (delta +%d, at pickup cell)" % (CHARS[t], ev["before"], ev["after"], delta),
          ok, "expected +%d at (%.1f,%.1f)" % (exp, PX[t], PY))
    # 6L: hpMsg$ per typ — "+<amPickup> <vapennamn> AMMO"
    exp_msg = "+%d %s AMMO" % (PICKUP[t], WPNAME[t])
    check("6L msg type %s: hpMsg$='%s'" % (CHARS[t], exp_msg), ev["msg"] == exp_msg,
          "got '%s'" % ev["msg"])

print()
if fails:
    print("AMMO REPLAY TEST FAIL:", fails)
    sys.exit(1)
print("AMMO REPLAY TEST OK — all four ammo pickups PROVEN in real flow (menu->playing, walked over):")
print("  A(musket)+10 B(blunderbuss)+4 C(machine musket)+12 D(mini cannon)+2 (6H per-typ amPickup, capped)")
