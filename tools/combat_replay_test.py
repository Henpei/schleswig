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

# (a) W hold 2s with click spam, release W after spam ends
script.append(("p20", "W+"))
spam("p30", "p150")
script.append(("p155", "F-"))
script.append(("p160", "W-"))
# (b) W hold + spam, W released MID-spam
script.append(("p200", "W+"))
spam("p210", "p350")
script.append(("p280", "W-"))     # mid-spam release — spam continues to p350
script.append(("p355", "F-"))
# (c) symptom documentation: W+S together
script.append(("p380", "W+"))
script.append(("p390", "S+"))
script.append(("p430", "W-"))
script.append(("p440", "S-"))

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
                if int(lines[-1].split()[0][3:]) >= first_playing + 450:
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
                "ksW": d.get("ksW", "0"), "shots": int(d.get("shots", 0))})

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

# spam actually happened (axe swings counted as shots)
shots_spam1 = [s["shots"] for s in seq if P + 30 <= s["fr"] <= P + 150]
check("(a) click-spam produced swings during W hold", shots_spam1 and shots_spam1[-1] > shots_spam1[0],
      "shots %s -> %s" % (shots_spam1[0] if shots_spam1 else "-", shots_spam1[-1] if shots_spam1 else "-"))

# (a) W held then released after spam: mvF==0 within 1 frame of the W- token
s160 = at_or_after(160)  # W- token at p160
check("(a) W released after spam -> mvF=0 within 1 frame", s160 is not None and s160["mv"][0] == "0" and s160["ksW"] == "0",
      "fr=%s mv=%s ksW=%s" % (s160["fr"] if s160 else "-", s160["mv"] if s160 else "-", s160["ksW"] if s160 else "-"))
if s160:
    after = [s for s in seq if s["fr"] >= s160["fr"]]
    check("(a) stays stopped (no sticky) for 30+ frames", all(s["mv"][0] == "0" for s in after[:30]))

# (b) mid-spam release: mvF==0 within 1 frame of W- at p280 while spam continues
s280 = at_or_after(280)
check("(b) W released MID-spam -> mvF=0 within 1 frame", s280 is not None and s280["mv"][0] == "0" and s280["ksW"] == "0",
      "fr=%s mv=%s ksW=%s" % (s280["fr"] if s280 else "-", s280["mv"] if s280 else "-", s280["ksW"] if s280 else "-"))
spam_after = [s for s in seq if P + 281 <= s["fr"] <= P + 370]   # axe cooldown 1.2s ~ 72 frames, widen window
check("(b) spam was still active after release (shots increasing)", spam_after and spam_after[-1]["shots"] > spam_after[0]["shots"],
      "shots %s -> %s" % (spam_after[0]["shots"] if spam_after else "-", spam_after[-1]["shots"] if spam_after else "-"))
if s280:
    after = [s for s in seq if s280["fr"] <= s["fr"] <= s280["fr"] + 30]
    check("(b) stays stopped during continued spam (no sticky)", all(s["mv"][0] == "0" for s in after))

# (c) symptom documentation: W+S together -> net zero velocity
ws = [s for s in seq if P + 395 <= s["fr"] <= P + 425]
if ws:
    pv0 = ws[0]["pv"]
    check("(c) doc: W+S together -> mvF=1,mvB=1 and pv net ~0 (symptom of stuck W)",
          all(s["mv"][0] == "1" and s["mv"][2] == "1" for s in ws) and abs(float(pv0.split(",")[0])) < 0.05 and abs(float(pv0.split(",")[1])) < 0.05,
          "mv=%s pv=%s" % (ws[0]["mv"], pv0))
else:
    check("(c) doc: W+S window seen", False, "no telemetry in window")

s440 = at_or_after(440)
check("release both -> stopped", s440 is not None and s440["mv"] == "0000", "mv=%s" % (s440["mv"] if s440 else "-"))

print()
if fails:
    print("COMBAT REPLAY TEST FAIL:", fails)
    sys.exit(1)
print("COMBAT REPLAY TEST OK — W release honored within 1 frame even under click spam (a+b), x2 scenarios")
