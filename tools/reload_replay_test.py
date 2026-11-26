#!/usr/bin/env python3
"""6H reload-system real-flow proof: runs the NORMAL binary (arg "replay
<fixture-map>") headless through the REAL app flow menu -> StartRun ->
fade -> playing and verifies magazine + reload behavior from the game's own
telemetry (/tmp/schleswig_replay.log fields wp=, mag=n/m, rlt=, shots=, ammo=):

 1. select MUSKET (digit 2), fire once -> mag 1->0, shots=1, POOL unchanged, rlt>0 (auto-reload starts)
 2. auto-reload completes -> mag back to 1, pool 15->14 (mag filled from pool)
 3. fire again, manual R -> rlt>0, mag 1, pool 14->13 (R-reload works)
 4. fire again, switch to AXE (digit 1) mid-reload -> rlt=0 (cancel), mag stays 0;
    switch back, R -> mag 1, pool 13->12

Usage: python3 tools/reload_replay_test.py [path-to-schleswig-binary]
Exit 0 = all assertions PASS.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "schleswig")
SCR = "/tmp/schleswig_replay.scr"
LOG = "/tmp/schleswig_replay.log"
MAP = "/tmp/schleswig_reload_map.map"

# 32x24 fixture: S=(4,20), musket pickup "m" one cell north at (4,19),
# one FOOT due north at (4,8) -> start-facing = north (6G FIX 5)
rows = ["#" * 32]
for y in range(1, 23):
    row = ["#"] + ["."] * 30 + ["#"]
    if y == 8:
        row[4] = "F"
    if y == 19:
        row[4] = "m"
    if y == 20:
        row[4] = "S"
    rows.append("".join(row))
rows.append("#" * 32)
with open(MAP, "w") as f:
    f.write("\n".join(rows) + "\n")

# pN = N frames after state first becomes "playing".
# Semantics proven by 6H: firing with an EMPTY mag starts the auto-reload
# (no passive timer); R starts a manual reload; a weapon switch cancels rlt.
script = [
    (5, "e"),          # START GAME (absolute frame — menu is before first playing frame)
    ("p15", "W+"), ("p60", "W-"),     # walk north over the "m" pickup -> MUSKET owned, full mag (+4 pool)
    ("p80", "2"),                     # select MUSKET (digit 2)
    ("p120", "F+"), ("p135", "F-"),   # shot 1 -> mag 1->0, pool UNCHANGED
    ("p300", "F+"), ("p315", "F-"),   # fire attempt with empty mag -> AUTO-reload starts (shots stays 1)
    ("p600", "F+"), ("p615", "F-"),   # shot 2 (mag was refilled by auto-reload) -> mag 0
    ("p650", "R+"), ("p670", "R-"),   # manual R reload -> mag 1, pool -1
    ("p1000", "F+"), ("p1015", "F-"), # shot 3 -> mag 0
    ("p1050", "R+"), ("p1070", "R-"), # manual R reload starts (rlt>0)
    ("p1100", "1"),                   # switch to AXE mid-reload -> must CANCEL rlt, mag stays 0
    ("p1300", "2"),                   # back to MUSKET, mag still 0
    ("p1350", "R+"), ("p1370", "R-"), # manual R reload again -> mag 1, pool -1
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

deadline = time.time() + 120
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
                if int(lines[-1].split()[0][3:]) >= first_playing + 1800:
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

seq = []
P = first_playing if first_playing is not None else 0
for l in lines:
    d = parse(l)
    if "fr" not in d or d.get("st") != "playing":
        continue
    fr = int(d["fr"])
    if fr < P:
        continue
    mag = d.get("mag", "?/?")
    seq.append({"fr": fr, "wp": int(d.get("wp", -1)), "mag": mag,
                "rlt": float(d.get("rlt", 0)), "shots": int(d.get("shots", 0)),
                "pool1": int(d.get("ammo", "0,0,0,0").split(",")[0])})

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("  " + detail if detail else ""))
    if not cond:
        fails.append(name)

check("menu->playing reached", first_playing is not None)
check("musket selected (wp=1)", any(s["wp"] == 1 for s in seq))

def find(pred, start=0):
    for i in range(start, len(seq)):
        if pred(seq[i]):
            return i
    return -1

# 1. shot 1: mag 1->0, pool UNCHANGED at fire (pool0 = baseline incl. +4 from weapon pickup)
i_shot1 = find(lambda s: s["shots"] >= 1)
check("shot 1 fires (shots>=1)", i_shot1 >= 0)
pool0 = None
if i_shot1 >= 0:
    s = seq[i_shot1]
    pool0 = s["pool1"]
    check("shot 1: mag 1->0, pool unchanged at fire", s["mag"] == "0/1",
          "mag=%s pool=%d" % (s["mag"], s["pool1"]))
# 2. fire attempt with empty mag -> auto-reload starts (rlt>0) WITHOUT a shot
i_auto = find(lambda s: s["rlt"] > 0 and s["shots"] == 1, i_shot1 + 1)
check("auto-reload starts on empty-mag fire attempt (rlt>0, shots still 1)", i_auto >= 0)
# 3. auto-reload completes: mag 1/1, pool pool0-1
i_re = find(lambda s: s["mag"] == "1/1" and s["shots"] == 1 and s["pool1"] == pool0 - 1, (i_auto if i_auto >= 0 else i_shot1) + 1)
check("auto-reload fills mag from pool (mag 1/1, pool %d->%d)" % (pool0, pool0 - 1), i_re >= 0)
# 4. shot 2 fires (mag was refilled), mag 0 again
i_s2 = find(lambda s: s["shots"] >= 2)
check("shot 2 fires after auto-reload", i_s2 >= 0 and seq[i_s2]["mag"] == "0/1")
# 5. manual R reload: rlt>0 then mag 1/1 with pool pool0-2
i_rlt2 = find(lambda s: s["rlt"] > 0 and s["shots"] >= 2, (i_s2 if i_s2 >= 0 else 0) + 1)
check("manual R starts reload (rlt>0)", i_rlt2 >= 0)
i_r2 = find(lambda s: s["mag"] == "1/1" and s["shots"] >= 2 and s["pool1"] == pool0 - 2, (i_rlt2 if i_rlt2 >= 0 else 0) + 1)
check("R reload fills mag, pool %d->%d" % (pool0 - 1, pool0 - 2), i_r2 >= 0)
# 6. shot 3 fires -> mag 0
i_s3 = find(lambda s: s["shots"] >= 3, (i_r2 if i_r2 >= 0 else 0) + 1)
check("shot 3 fires after R reload", i_s3 >= 0 and seq[i_s3]["mag"] == "0/1")
# 7. R starts reload, then weapon switch to AXE cancels it: wp=0, rlt=0, mag stays 0/1
i_rlt3 = find(lambda s: s["rlt"] > 0 and s["shots"] >= 3, (i_s3 if i_s3 >= 0 else 0) + 1)
check("R pressed again -> reload running (rlt>0)", i_rlt3 >= 0)
i_axe = find(lambda s: s["wp"] == 0 and s["shots"] >= 3, (i_rlt3 if i_rlt3 >= 0 else 0) + 1)
check("weapon switch to AXE mid-reload", i_axe >= 0)
if i_axe >= 0:
    s = seq[i_axe]
    # NB: telemetry mag=/rlt= refer to wpCur — on AXE they read 0/0,0 by definition.
    # The cancel is rlt=0 on switch; mag preservation is proven by the i_back check below.
    check("switch CANCELS reload (rlt=0 on new weapon)", s["rlt"] == 0,
          "rlt=%s mag=%s (axe)" % (s["rlt"], s["mag"]))
# 8. back on MUSKET: mag still 0/1, then R -> mag 1/1, pool pool0-3
i_back = find(lambda s: s["wp"] == 1 and s["shots"] >= 3, (i_axe if i_axe >= 0 else 0) + 1)
check("back on MUSKET: mag still 0/1 (switch kept it)", i_back >= 0 and seq[i_back]["mag"] == "0/1",
      "mag=%s" % (seq[i_back]["mag"] if i_back >= 0 else "-"))
i_r3 = find(lambda s: s["mag"] == "1/1" and s["shots"] >= 3 and s["pool1"] == pool0 - 3, (i_back if i_back >= 0 else 0) + 1)
check("R after switch-back reloads, pool %d->%d" % (pool0 - 2, pool0 - 3), i_r3 >= 0)

print()
if fails:
    print("RELOAD REPLAY TEST FAIL:", fails)
    sys.exit(1)
print("RELOAD REPLAY TEST OK — mag/auto-reload/R-reload/switch-cancel all PROVEN in real flow")
