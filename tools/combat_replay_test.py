#!/usr/bin/env python3
"""6I combat replay regression test: sticky-W-under-mouse-spam in the REAL app
flow (menu -> StartRun -> fade -> playing) via `replay <map>`.

Fixture: player S=(4,20) with ONLY the axe (no weapon pickups — matches André's
first-fight context), one FOOT at (6,20) in melee range. Script drives:
  (a) W held 2s + frenetic click-spam (~10 clicks/s), W released AFTER spam
      -> assert mvF==0 within 1 frame of the W- token frame
  (b) W held + click-spam, W released MID-spam (spam continues)
      -> assert mvF==0 within 1 frame despite ongoing fire (Andrés exact seq)
  (c) symptom documentation: W+S together -> net zero velocity (pv=0,0)
      (documented, not asserted as desired)
Telemetry (/tmp/schleswig_replay.log, now logged EVERY frame in replay) carries
mv= (mvF,mvL,mvB,mvR), pv=, ksW=, shots=.

Usage: python3 tools/combat_replay_test.py [path-to-schleswig-binary]
Exit 0 = all assertions PASS.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "schleswig")
SCR = "/tmp/schleswig_replay.scr"
LOG = "/tmp/schleswig_replay.log"
MAP = "/tmp/schleswig_combat_map.map"

# 32x32 arena: S=(4,20), F=(6,20) two cells east (melee range, keeps swinging)
rows = ["#" * 32]
for y in range(1, 31):
    row = ["#"] + ["."] * 30 + ["#"]
    if y == 20:
        row[4] = "S"
        row[6] = "F"
    rows.append("".join(row))
rows.append("#" * 32)
with open(MAP, "w") as f:
    f.write("\n".join(rows) + "\n")

SCEN = sys.argv[2] if len(sys.argv) > 2 else "all"   # "all" or "e" (6I-FU3 shift-combo only)
script = [(5, "e")]
def spam(p0, p1, step=5):
    """frenetic click-spam: F+ / F- alternating every `step` frames (~6 clicks/s at 60fps, faster bursts)"""
    on = True
    p = int(p0[1:])
    end = int(p1[1:])
    while p <= end:
        script.append(("p%d" % p, "F+" if on else "F-"))
        on = not on
        p += step

def add(fr, tok):
    """append token at p<fr>; scenarios (a)-(d) only run when SCEN=="all" """
    if SCEN == "e" and fr < 1700:
        return
    script.append(("p%d" % fr, tok))
def spamp(p0, p1, step=5):
    on = True
    p = p0
    while p <= p1:
        add(p, "F+" if on else "F-")
        on = not on
        p += step

# (a) W hold 2s with click spam, release W after spam ends
add(20, "W+")
spamp(30, 150)
add(155, "F-")
add(160, "W-")
# (b) W hold + spam, W released MID-spam
add(200, "W+")
spamp(210, 350)
add(280, "W-")     # mid-spam release — spam continues to p350
add(355, "F-")
# (c) symptom documentation: W+S together
add(380, "W+")
add(390, "S+")
add(430, "W-")
add(440, "S-")
# (d) ANDRÉ'S EXACT 6I-FU2 SCENARIO: Shift+W sprint + repeated axe swings
# (click spam at melee cadence), W released MID-swing-spam, stamina exhausted
# (sprintLock) mid-sequence.
add(460, "SH+")
add(465, "W+")
spamp(470, 1600, step=10)
add(1450, "W-")    # W released AFTER stamina lock, mid-spam, still Shift
add(1610, "F-")
add(1650, "SH-")
# (e) 6I-FU3 shift-combo normalization: raw overlay events via E<code> tokens.
# Real libqb behavior under Shift: W down arrives as 87 (upper), release may
# arrive as -119 (lower) or only as -100304 (shift combo) — normalization must
# map all variants to one key id. When SCEN=="e" these are rebased to p20+.
EB = 1700 if SCEN == "all" else 20
def adde(off, tok):
    script.append(("p%d" % (EB + off), tok))
adde(0, "W+")       # polling down (keySim)
adde(5, "E87")      # overlay down as UPPER W
adde(20, "E-100304") # shift release only — must NOT clear W
adde(40, "E-119")   # W release as LOWER-case variant — must clear W (KeyNorm)
adde(60, "W+")
adde(65, "E87")
adde(80, "E-87")    # release as upper — clears W while keySim still down
adde(100, "W-")
adde(105, "E87")     # stale overlay down with polling up — guard must say UP
adde(130, "SH+")
adde(135, "W+")
adde(140, "E100304")  # shift down (combo code)
adde(145, "E87")      # W down
adde(200, "W-")
adde(205, "E-100304") # asymmetric release: shift combo only...
adde(210, "E-87")     # ...plus W release
adde(230, "SH-")

def frkey(item):
    fr = item[0]
    return int(fr[1:]) if isinstance(fr, str) and fr.startswith("p") else int(fr)
script.sort(key=frkey)   # tokens must be in frame order (the in-game While exits at the first not-yet-due token)
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

deadline = time.time() + 250
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
                if int(lines[-1].split()[0][3:]) >= first_playing + (EB + 260):
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

P = first_playing if first_playing is not None else 0

def parse(l):
    d = {}
    for part in l.split():
        if "=" in part:
            k, v = part.split("=", 1)
            d[k] = v
    return d

seq = []
for l in lines:
    d = parse(l)
    if d.get("st") != "playing":
        continue
    try:
        fr = int(d["fr"])
    except Exception:
        continue
    if fr < P:
        continue
    seq.append({"fr": fr, "mv": d.get("mv", "0000"), "pv": d.get("pv", "0,0"),
                "ksW": d.get("ksW", "0"), "shots": int(d.get("shots", 0)),
                "stam": d.get("stam", "100"), "lock": d.get("lock", "0"),
                "ksSH": d.get("ksSH", "0"), "spd": d.get("spd", "1")})

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("  " + detail if detail else ""))
    if not cond:
        fails.append(name)

def at_or_after(pn):
    target = P + pn + 1   # replay token pN applies at frame P+N+1 (replayAt& = -(N+1))
    for s in seq:
        if s["fr"] >= target:
            return s
    return None

check("menu->playing reached", first_playing is not None)

def checkA(name, cond, detail=""):
    """scenario (a)-(d) checks: only in SCEN==all mode"""
    if SCEN == "all":
        check(name, cond, detail)

# spam actually happened (axe swings counted as shots)
shots_spam1 = [s["shots"] for s in seq if P + 30 <= s["fr"] <= P + 150]
checkA("(a) click-spam produced swings during W hold", shots_spam1 and shots_spam1[-1] > shots_spam1[0],
      "shots %s -> %s" % (shots_spam1[0] if shots_spam1 else "-", shots_spam1[-1] if shots_spam1 else "-"))

# (a) W held then released after spam: mvF==0 within 1 frame of the W- token
s160 = at_or_after(160)  # W- token at p160
checkA("(a) W released after spam -> mvF=0 within 1 frame", s160 is not None and s160["mv"][0] == "0" and s160["ksW"] == "0",
      "fr=%s mv=%s ksW=%s" % (s160["fr"] if s160 else "-", s160["mv"] if s160 else "-", s160["ksW"] if s160 else "-"))
if s160:
    after = [s for s in seq if s["fr"] >= s160["fr"]]
    checkA("(a) stays stopped (no sticky) for 30+ frames", all(s["mv"][0] == "0" for s in after[:30]))

# (b) mid-spam release: mvF==0 within 1 frame of W- at p280 while spam continues
s280 = at_or_after(280)
checkA("(b) W released MID-spam -> mvF=0 within 1 frame", s280 is not None and s280["mv"][0] == "0" and s280["ksW"] == "0",
      "fr=%s mv=%s ksW=%s" % (s280["fr"] if s280 else "-", s280["mv"] if s280 else "-", s280["ksW"] if s280 else "-"))
spam_after = [s for s in seq if P + 281 <= s["fr"] <= P + 370]   # axe cooldown 1.2s ~ 72 frames, widen window
checkA("(b) spam was still active after release (shots increasing)", spam_after and spam_after[-1]["shots"] > spam_after[0]["shots"],
      "shots %s -> %s" % (spam_after[0]["shots"] if spam_after else "-", spam_after[-1]["shots"] if spam_after else "-"))
if s280:
    after = [s for s in seq if s280["fr"] <= s["fr"] <= s280["fr"] + 30]
    checkA("(b) stays stopped during continued spam (no sticky)", all(s["mv"][0] == "0" for s in after))

# (c) symptom documentation: W+S together -> net zero velocity
ws = [s for s in seq if P + 395 <= s["fr"] <= P + 425]
if ws:
    pv0 = ws[0]["pv"]
    checkA("(c) doc: W+S together -> mvF=1,mvB=1 and pv net ~0 (symptom of stuck W)",
          all(s["mv"][0] == "1" and s["mv"][2] == "1" for s in ws) and abs(float(pv0.split(",")[0])) < 0.05 and abs(float(pv0.split(",")[1])) < 0.05,
          "mv=%s pv=%s" % (ws[0]["mv"], pv0))
else:
    checkA("(c) doc: W+S window seen", False, "no telemetry in window")

s440 = at_or_after(440)
checkA("release both -> stopped", s440 is not None and s440["mv"] == "0000", "mv=%s" % (s440["mv"] if s440 else "-"))

# (d) André's scenario: sprint (Shift+W) was active when W was released mid-spam
s465 = at_or_after(465)
s600 = at_or_after(1450)
checkA("(d) sprint active before release (spd=1.5, stam draining)",
      s465 is not None and s465["spd"] == "1.5" and float(s465["stam"]) < 100,
      "fr=%s spd=%s stam=%s" % (s465["fr"] if s465 else "-", s465["spd"] if s465 else "-", s465["stam"] if s465 else "-"))
checkA("(d) W released mid sprint+swing spam -> mvF=0 within 1 frame",
      s600 is not None and s600["mv"][0] == "0" and s600["ksW"] == "0",
      "fr=%s mv=%s ksW=%s" % (s600["fr"] if s600 else "-", s600["mv"] if s600 else "-", s600["ksW"] if s600 else "-"))
if s600:
    after = [s for s in seq if s600["fr"] <= s["fr"] <= s600["fr"] + 40]
    checkA("(d) stays stopped during continued sprint+spam (no sticky)", all(s["mv"][0] == "0" for s in after))
dwin = [s for s in seq if P + 465 <= s["fr"] <= P + 1600]
lockseen = any(s["lock"] == "1" and float(s["stam"]) <= 0.5 for s in dwin)
checkA("(d) stamina exhausted mid-sprint (sprintLock=1 at stam~0 seen)", lockseen,
      "min stam in sprint window: %s" % min((float(s["stam"]) for s in dwin), default=-1))
checkA("(d) swings happened during sprint spam", dwin and dwin[-1]["shots"] > dwin[0]["shots"],
      "shots %s -> %s" % (dwin[0]["shots"] if dwin else "-", dwin[-1]["shots"] if dwin else "-"))

# (e) shift-combo normalization (raw overlay events via E<code>); offsets rebased by EB
def mv_at(off):
    s = at_or_after(EB + off)
    return s["mv"][0] if s else "?"
if True:
    check("(e1) W down (polling) + overlay down as upper 87 -> mvF=1", mv_at(5) == "1", "mvF=%s" % mv_at(5))
    check("(e2) shift-combo release E-100304 alone does NOT clear W", mv_at(25) == "1", "mvF=%s" % mv_at(25))
    check("(e3) release as lower variant E-119 clears W (KeyNorm 119->87)", mv_at(45) == "0", "mvF=%s" % mv_at(45))
    check("(e4) re-press W -> mvF=1, release as upper E-87 clears even with polling down", mv_at(65) == "1" and mv_at(85) == "0",
          "mvF@65=%s mvF@85=%s" % (mv_at(65), mv_at(85)))
    check("(e5) stale overlay ev=1 with polling up -> guard says UP (no sticky)", mv_at(110) == "0", "mvF=%s" % mv_at(110))
    s1835 = at_or_after(EB + 145)
    check("(e6) Shift+W sprint: mvF=1 and spd=1.5 with combo codes", s1835 is not None and s1835["mv"][0] == "1" and s1835["spd"] == "1.5",
          "mv=%s spd=%s" % (s1835["mv"] if s1835 else "-", s1835["spd"] if s1835 else "-"))
check("(e6) W release (W- + E-100304 + E-87) -> mvF=0 within 1 frame", mv_at(215) == "0", "mvF=%s" % mv_at(215))

print()
if fails:
    print("COMBAT REPLAY TEST FAIL:", fails)
    sys.exit(1)
print("COMBAT REPLAY TEST OK — W release honored within 1 frame even under click spam (a+b), x2 scenarios")
