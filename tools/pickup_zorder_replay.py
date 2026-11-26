#!/usr/bin/env python3
"""6K repro: two pickups on the SAME sightline — medkit M near (10,20),
ammo A far (14,20), player S=(4,20) facing east, one far enemy F=(28,20)
(keeps start-facing east, sealed off by distance). Runs the normal binary in
replay mode and saves the periodic screenshot /tmp/schleswig_replay.bmp to
the path given as argv[2] (e.g. docs/pickup-dumps/6k_bug.bmp / 6k_fix.bmp).

Usage: python3 tools/pickup_zorder_replay.py ./schleswig out.bmp
"""
import os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "schleswig")
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/schleswig_zorder.bmp"
SCR = "/tmp/schleswig_replay.scr"
LOG = "/tmp/schleswig_replay.log"
BMP = "/tmp/schleswig_replay.bmp"
MAP = "/tmp/schleswig_zorder_map.map"

# 32x32: S=(4,20), M=(10,20) near, A=(14,20) far, F=(28,20) far east (facing)
rows = ["#" * 32]
for y in range(1, 31):
    row = ["#"] + ["."] * 30 + ["#"]
    if y == 20:
        row[4] = "S"
        row[10] = "M"
        row[14] = "A"
        row[28] = "F"
    rows.append("".join(row))
rows.append("#" * 32)
with open(MAP, "w") as f:
    f.write("\n".join(rows) + "\n")
with open(SCR, "w") as f:
    f.write("5 e\n")   # start game, then stand still
for p in (LOG, BMP):
    if os.path.exists(p):
        os.remove(p)

env = dict(os.environ)
env["SDL_VIDEODRIVER"] = "dummy"
env["SDL_AUDIODRIVER"] = "dummy"
proc = subprocess.Popen([BIN, "replay", MAP], cwd=os.path.dirname(os.path.abspath(BIN)) or ".",
                        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
deadline = time.time() + 90
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
                if int(lines[-1].split()[0][3:]) >= first_playing + 130:
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

if os.path.exists(BMP):
    shutil.copy(BMP, OUT)
    print("saved", OUT)
else:
    print("NO SCREENSHOT — replay did not reach frame 120")
    sys.exit(1)
