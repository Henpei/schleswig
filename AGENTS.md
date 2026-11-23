# SCHLESWIG — AGENT CONVENTIONS (AGENTS.md)
Read this FIRST in every session, then follow it.

## Project
QB64-PE raycaster game (Wayland-native). Source:
schleswig/Schleswig.bas. Repo: Henpei/schleswig.
Working on: phases 4+ (enemy AI, projectiles,
weapons rendering).

## Language rules (STRICT)
- ALL commit messages: English.
- ALL new code comments: English.
- ALL in-game text: English.
- Variable/function names: English.

## Input schema
- KeyUse = universal interaction key (E) — upcoming phases reuse this
  exact check (Const KeyUse + Function KeyUseHit% in Schleswig.bas).
  SPACE is NOT a menu selector; menus select with E, mouse click works
  in parallel where applicable.

## Build (from /home/andre/QB64pe, NOT repo root)
  ./qb64pe -c schleswig/Schleswig.bas -o schleswig/schleswig -x
- Requirement: exit code 0. Shell is FISH: check
  $status, not $?.
- Compile errors land in internal/temp/compilelog.txt,
  but that file can be STALE (old attempts): trust the
  terminal "Output:"-line + exit code. Never name the
  binary the same as the source folder ("Är en
  katalog" / "is a directory" build failure).

## Run & selftest
- Run: ./schleswig/schleswig
- Selftest: ./schleswig/schleswig selftest
  → ALL phases must PASS, log:
  /tmp/schleswig_selftest.log
- Report exactly: "SELFTEST OK, n PASS / 0 FAIL".

## Every pass (workflow)
1. Read this file + the prompt.
2. Implement + bump strBuild$ (use latest commit
   hash shortform).
3. One commit, push origin/main, English message.
4. Report: changed lines (grep-proof where
   relevant), selftest status, commit hash, and a
   "SEN KLAR — André feel-test" checklist for
   hands-on verification.

## QB64-PE traps (learned the hard way)
- Variables read inside SUB/FUNCTION need DIM
  SHARED or they silently become local (=0).
- Image handles can be negative: check <> 0, not > 0.
- Wayland pointer lock: _MOUSEHIDE _DISABLE = lock
  (needs user click on Wayland); plain _MOUSEHIDE =
  hide only. NEVER use _MOUSESHOW: it was the cursor
  bug culprit. Session design: default Wayland
  cursor in main menu (before first lock), ONE
  _MOUSEHIDE _DISABLE at first fade end, no destroys
  except QuitGame.
- Procedural sound (GenSample# noise) consumes the
  global Rnd stream sample-by-sample, so Rnd is NOT
  predictable around PlaySound. For seeded/deterministic
  selftest checks use a dedicated LCG stream instead
  (see Function DodgeRnd# / dodgeSeed& in Schleswig.bas).

## PARKED (do not reactivate without André's OK)
- Virtual cursor + arrow sprite (commit aa26eee):
  vCurX/vCurY, MoveVirtualCursor, ButtonHit%,
  DrawCursor, cursorBuf&.
