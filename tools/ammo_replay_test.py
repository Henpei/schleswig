#!/usr/bin/env python3
"""6G/6L/6L-B ammo real-flow proof: runs the NORMAL binary (arg "replay <fixture-map>")
headless (SDL dummy drivers) through the REAL app flow menu -> StartRun ->
fade -> playing, walks the player over ammo pickups and asserts from the game's
own telemetry log (/tmp/schleswig_replay.log, "ammo=n1,n2,n3,n4 ... msg=<hpMsg$>"
per frame) that every pool behaves exactly per spec when the player passes over
the pickup cell.

6L-B coverage (cap visibility): fixtures walk over pickups so that, from the
fresh-run pools 15/0/0/0 (StartRun: ammoN(1)=startAmmo=15, rest 0), the EXACT
event sequence is asserted per pickup:
  normal   x4 types: "+10 MUSKET AMMO" / "+4 BLUNDERBUSS AMMO" /
                     "+12 MACHINE MUSKET AMMO" / "+2 MINI CANNON AMMO"
  partial  (35+10, cap 40): "+5 MUSKET AMMO (FULL: +5 lost)", pool == cap after
  full     (pool already at cap, one per type): "<NAME> AMMO FULL", pool unchanged
6H amounts amPickup 10/4/12/2, caps capAmmo 40/16/48/12.

NOTE: the map spawn pool holds max 10 ammo pickups (spAmN < 10 in ParseMap), so
each fixture uses <= 10 pickups and the scenarios are split into three maps:
  main    (10 pk): normal x4 types + A partial + FULL A + B up to cap
  fullBC  (10 pk): B x5 -> FULL B, C x5 -> FULL C (36+12=48 = cap exactly, then FULL)
  fullD   ( 7 pk): D x7 -> 12 = cap exactly, then FULL D

Fixture maps are generated in /tmp (the real maps/*.map are NOT touched).
Layout per fixture: 32x32, S=(2,2), one melee F=(29,29) far away (never detects),
pickups in COLUMN 2 starting at row 3; the 0.2.0-b start-facing rule (S row < 32
-> angle=+pi/2 = south) makes holding W walk straight down the column over all of them.

Every scenario runs TWICE (deterministic) — both runs must be green.

Usage: python3 tools/ammo_replay_test.py [path-to-schleswig-binary]
Exit 0 = all ammo pickup behaviour proven in real flow.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "schleswig")
SCR = "/tmp/schleswig_replay.scr"
LOG = "/tmp/schleswig_replay.log"

CAPS = {1: 40, 2: 16, 3: 48, 4: 12}         # 6H capAmmo per type (musket/blunder/MG/cannon; B 12->16, D 8->12)
PICKUP = {1: 10, 2: 4, 3: 12, 4: 2}         # 6H amPickup(AMMO_N) per type (was single Const +10)
CHARS = {1: "A", 2: "B", 3: "C", 4: "D"}     # map char per ammo type
WPNAME = {1: "MUSKET", 2: "BLUNDERBUSS", 3: "MACHINE MUSKET", 4: "MINI CANNON"}   # 6L: wpName$ per ammo-typ
NAME2T = {v: k for k, v in WPNAME.items()}


def seq_normal(t, before):
    return (t, before, before + PICKUP[t], "+%d %s AMMO" % (PICKUP[t], WPNAME[t]))


# (type, before, after, expected hpMsg$) per pickup, in walk order (row 3,4,5,...)
SCENARIOS = {
    "main": {
        "pickups": ["A", "B", "C", "D", "A", "A", "A", "B", "B", "B"],
        "expected": [
            seq_normal(1, 15),                                   # 15->25
            seq_normal(2, 0),                                    # 0->4
            seq_normal(3, 0),                                    # 0->12
            seq_normal(4, 0),                                    # 0->2
            seq_normal(1, 25),                                   # 25->35
            (1, 35, 40, "+5 MUSKET AMMO (FULL: +5 lost)"),       # 6L-B partial: 35+10 -> cap 40
            (1, 40, 40, "MUSKET AMMO FULL"),                     # 6L-B full A
            seq_normal(2, 4),                                    # 4->8
            seq_normal(2, 8),                                    # 8->12
            seq_normal(2, 12),                                   # 12->16 = cap exactly -> normal
        ],
    },
    "fullBC": {
        "pickups": ["B", "B", "B", "B", "B", "C", "C", "C", "C", "C"],
        "expected": [
            seq_normal(2, 0), seq_normal(2, 4), seq_normal(2, 8), seq_normal(2, 12),
            (2, 16, 16, "BLUNDERBUSS AMMO FULL"),                # 6L-B full B
            seq_normal(3, 0), seq_normal(3, 12), seq_normal(3, 24), seq_normal(3, 36),  # 36->48 = cap exactly
            (3, 48, 48, "MACHINE MUSKET AMMO FULL"),             # 6L-B full C
        ],
    },
    "fullD": {
        "pickups": ["D", "D", "D", "D", "D", "D", "D"],
        "expected": [
            seq_normal(4, 0), seq_normal(4, 2), seq_normal(4, 4), seq_normal(4, 6),
            seq_normal(4, 8), seq_normal(4, 10),                 # 10->12 = cap exactly
            (4, 12, 12, "MINI CANNON AMMO FULL"),                # 6L-B full D
        ],
    },
}

HOLD_FRAMES = 2600   # W held this many frames after playing starts (headless ~130fps -> 10 cells needs ~1500 frames)
RUNS = 2


def write_fixture(pickups):
    map_path = "/tmp/schleswig_ammo_map.map"
    rows = ["#" * 32]
    for y in range(1, 31):
        row = ["#"] + ["."] * 30 + ["#"]
        if y == 2:
            row[2] = "S"      # S row 2 < 32 -> 0.2.0-b rule faces SOUTH
        if y == 29:
            row[29] = "F"     # far away, stays PATROLL (undetected never fires)
        rows.append("".join(row))
    for i, c in enumerate(pickups):
        rows[3 + i] = rows[3 + i][:2] + c + rows[3 + i][3:]   # column 2, rows 3..
    rows.append("#" * 32)
    with open(map_path, "w") as f:
        f.write("\n".join(rows) + "\n")
    return map_path


def write_script():
    with open(SCR, "w") as f:
        f.write("5 e\n")                       # tap "e" = START GAME in the real menu
        f.write("p40 W+\n")                    # after playing starts: hold W
        f.write("p%d W-\n" % HOLD_FRAMES)


def run_once(map_path):
    write_script()
    if os.path.exists(LOG):
        os.remove(LOG)
    env = dict(os.environ)
    env["SDL_VIDEODRIVER"] = "dummy"
    env["SDL_AUDIODRIVER"] = "dummy"
    proc = subprocess.Popen([BIN, "replay", map_path], cwd=os.path.dirname(os.path.abspath(BIN)) or ".",
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
                    if int(lines[-1].split()[0][3:]) >= first_playing + HOLD_FRAMES + 20:
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
    return lines, first_playing


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


for run_no in range(1, RUNS + 1):
    for sc_name, sc in SCENARIOS.items():
        tag = "run%d/%s" % (run_no, sc_name)
        print("=== %s ===" % tag)
        map_path = write_fixture(sc["pickups"])
        lines, first_playing = run_once(map_path)
        check("%s: menu->playing reached" % tag, first_playing is not None)

        # collect events: a pickup event = any pool changed OR hpMsg$ changed to a
        # new "... AMMO..." message (FULL pickups leave the pool unchanged)
        events = []
        prev_pools = None
        prev_msg = ""
        P = first_playing if first_playing is not None else 0
        for l in lines:
            d = parse(l)
            if "fr" not in d or "ammo" not in d:
                continue
            fr = int(d["fr"])
            if fr < P or d.get("st") != "playing":
                continue
            pools = [int(x) for x in d["ammo"].split(",")]
            msg = l.split(" msg=", 1)[1].strip() if " msg=" in l else ""
            if prev_pools is not None:
                changed = [t + 1 for t in range(4) if pools[t] != prev_pools[t]]
                msg_new_ammo = (msg != prev_msg) and ("AMMO" in msg)
                if changed or msg_new_ammo:
                    if changed:
                        t = changed[0]
                    else:
                        t = 0
                        for w in sorted(WPNAME.values(), key=len, reverse=True):  # longest first: MACHINE MUSKET before MUSKET
                            if msg.startswith(w + " "):
                                t = NAME2T[w]
                                break
                    events.append({"fr": fr, "pools_before": prev_pools, "pools_after": pools,
                                   "msg": msg, "px": float(d["px"]), "py": float(d["py"]), "type": t})
            prev_pools = pools
            prev_msg = msg

        exp = sc["expected"]
        check("%s: %d pickup events seen (expected %d)" % (tag, len(events), len(exp)),
              len(events) == len(exp), "got %d" % len(events))

        n_ok = 0
        for i, ev in enumerate(events):
            if i >= len(exp):
                break
            et, eb, ea, emsg = exp[i]
            ok = (ev["type"] == et and ev["pools_before"][et - 1] == eb
                  and ev["pools_after"][et - 1] == ea and ev["msg"] == emsg)
            n_ok += 1 if ok else 0
            print("  %-3d %-2s %2d->%-2d @x=%-5s %-38s %s" % (
                i + 1, CHARS[et], ev["pools_before"][et - 1], ev["pools_after"][et - 1],
                "%.1f" % ev["px"], "%s | got '%s'" % (emsg, ev["msg"]),
                "PASS" if ok else "FAIL"))
        check("%s: exact event sequence (%d events: normal/partial/FULL msgs 6L+6L-B)" % (tag, len(exp)),
              n_ok == len(exp), "%d/%d match" % (n_ok, len(exp)))

        # explicit 6L-B assertions on the scenarios that contain them
        if sc_name == "main" and len(events) == len(exp):
            ev_p, ev_f = events[5], events[6]
            check("%s: 6L-B partial 35+10 cap40 -> pool==40, msg '+5 MUSKET AMMO (FULL: +5 lost)'" % tag,
                  ev_p["pools_after"][0] == CAPS[1] and ev_p["msg"] == "+5 MUSKET AMMO (FULL: +5 lost)",
                  "pool=%d msg='%s'" % (ev_p["pools_after"][0], ev_p["msg"]))
            check("%s: 6L-B full A -> 'MUSKET AMMO FULL', pool unchanged at 40" % tag,
                  ev_f["msg"] == "MUSKET AMMO FULL" and ev_f["pools_after"][0] == CAPS[1],
                  "msg='%s' pool=%d" % (ev_f["msg"], ev_f["pools_after"][0]))
        if sc_name == "fullBC" and len(events) == len(exp):
            check("%s: 6L-B full B -> 'BLUNDERBUSS AMMO FULL' pool==16" % tag,
                  events[4]["msg"] == "BLUNDERBUSS AMMO FULL" and events[4]["pools_after"][1] == CAPS[2],
                  "msg='%s' pool=%d" % (events[4]["msg"], events[4]["pools_after"][1]))
            check("%s: 6L-B full C -> 'MACHINE MUSKET AMMO FULL' pool==48" % tag,
                  events[9]["msg"] == "MACHINE MUSKET AMMO FULL" and events[9]["pools_after"][2] == CAPS[3],
                  "msg='%s' pool=%d" % (events[9]["msg"], events[9]["pools_after"][2]))
        if sc_name == "fullD" and len(events) == len(exp):
            check("%s: 6L-B full D -> 'MINI CANNON AMMO FULL' pool==12" % tag,
                  events[6]["msg"] == "MINI CANNON AMMO FULL" and events[6]["pools_after"][3] == CAPS[4],
                  "msg='%s' pool=%d" % (events[6]["msg"], events[6]["pools_after"][3]))
        print()

if fails:
    print("AMMO REPLAY TEST FAIL:", fails)
    sys.exit(1)
print("AMMO REPLAY TEST OK x%d — ammo pickups PROVEN in real flow (menu->playing, walked over):" % RUNS)
print("  6H per-typ amPickup 10/4/12/2 capped at 40/16/48/12; 6L per-typ hpMsg$;")
print("  6L-B cap visibility: partial '+5 MUSKET AMMO (FULL: +5 lost)' with pool==cap,")
print("  and '<NAME> AMMO FULL' per type when the pool is already at cap (pool unchanged).")
