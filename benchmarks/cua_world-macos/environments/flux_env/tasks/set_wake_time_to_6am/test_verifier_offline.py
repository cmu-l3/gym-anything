"""Offline mock tests for verify_set_wake_time_to_6am.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/flux_env/tasks/set_wake_time_to_6am/test_verifier_offline.py

Required scenarios per task_creation_notes/13_file_content_verification_and_offline_testing.md:
  - do-nothing                       → score 0 (well below pass)
  - wrong-target (strict gate fires) → score 0
  - partial (close but not exact)    → 0 < score < pass_threshold
  - full-correct                     → score >= pass_threshold

Plus the contamination/anti-gaming scenarios from
task_creation_notes/14_task_design_antipatterns.md #4 and #13:
  - close-but-tier-1 partial         → 30+5+10+10+10 = 65 (< 70, no false pass)
  - flipped SUSendProfileInfo        → loses C5, still passes if wakeTime correct
  - wakeTime deleted (destructive)   → 0 + 0 + 0 + 10 + 10 = 20 (no false pass)
  - mass-edit attack (lat changed too) → 0 strict-gate triggered? No — lat is
                                          IN EXPECTED_KEYS so no "unrelated"
                                          key added; falls through to scoring
                                          and just loses C4. Documented.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERIFIER_PATH = HERE / "verifier.py"
spec = importlib.util.spec_from_file_location("verifier", VERIFIER_PATH)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
verify = mod.verify_set_wake_time_to_6am


def make_env_info(fake_result: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(fake_result).encode()); fixture.close()
    def copy_from_env(_remote: str, local: str) -> None:
        shutil.copy(fixture.name, local)
    return {"copy_from_env": copy_from_env, "_fixture": fixture.name}


def run(name: str, fake_result: dict, expect_score, expect_passed: bool) -> bool:
    env_info = make_env_info(fake_result)
    out = verify(traj={}, env_info=env_info, task_info={})
    Path(env_info["_fixture"]).unlink(missing_ok=True)
    score = out["score"]; passed = out["passed"]
    if isinstance(expect_score, tuple):
        lo, hi = expect_score
        score_ok = lo <= score <= hi
        expect_desc = f"{lo}..{hi}"
    else:
        score_ok = score == expect_score
        expect_desc = str(expect_score)
    pass_ok = passed == expect_passed
    status = "PASS" if (score_ok and pass_ok) else "FAIL"
    print(f"[{status}] {name}: got score={score} passed={passed} "
          f"(expected score={expect_desc} passed={expect_passed})")
    if not (score_ok and pass_ok):
        print(f"    subscores: {out['subscores']}")
        print(f"    feedback:  {out['feedback']}")
        return False
    return True


TASK_START = 1_700_000_000
EXPECTED_KEYS = ["SUEnableAutomaticChecks", "SUHasLaunchedBefore",
                 "SUSendProfileInfo", "lat", "lng", "place", "wakeTime"]


def base(initial_wakeTime=480, final_wakeTime=480,
         initial_lat=40.4406, final_lat=40.4406,
         initial_lng=-79.9959, final_lng=-79.9959,
         initial_susend=False, final_susend=False,
         plist_touched=False, final_keys=None,
         plist_exists=True, parse_error=False,
         initial_mtime=1_699_999_500, final_mtime=1_699_999_500,
         plist_size=300):
    return {
        "task": "set_wake_time_to_6am",
        "task_start": TASK_START,
        "plist_exists": plist_exists,
        "plist_touched_after_task_start": plist_touched,
        "plist_parse_error": parse_error,
        "initial_plist_mtime": initial_mtime,
        "final_plist_mtime": final_mtime,
        "final_plist_size_bytes": plist_size,
        "initial_wakeTime": initial_wakeTime,
        "final_wakeTime": final_wakeTime,
        "initial_lat": initial_lat, "final_lat": final_lat,
        "initial_lng": initial_lng, "final_lng": final_lng,
        "initial_SUSendProfileInfo": initial_susend,
        "final_SUSendProfileInfo": final_susend,
        "final_plist_keys": final_keys if final_keys is not None else list(EXPECTED_KEYS),
    }


DO_NOTHING = base(
    # Setup wrote everything to baseline; agent did nothing → plist
    # unchanged → wakeTime still 480 → no edits at all.
    plist_touched=False,
)

WRONG_TARGET_GATE_LAT = base(
    # Agent changed `lat` (a protected field) but left wakeTime unchanged.
    # Strict gate fires → score 0.
    plist_touched=True,
    final_mtime=TASK_START + 30,
    final_lat=37.7749,   # San Francisco — clearly different from baseline
)

WRONG_TARGET_GATE_LNG = base(
    # Agent changed `lng` only (the other half of the location pair).
    # Strict gate must fire symmetrically with the `lat` case → score 0.
    plist_touched=True,
    final_mtime=TASK_START + 30,
    final_lng=-122.4194,   # San Francisco longitude — clearly different
)

WRONG_TARGET_GATE_SUSEND = base(
    # Agent flipped SUSendProfileInfo (a protected field) but left wakeTime
    # unchanged. Strict gate fires → score 0.
    plist_touched=True, final_mtime=TASK_START + 30,
    final_susend=True,
)

FLUX_ADDED_BOOKKEEPING_KEYS = base(
    # Flux launched and added `version` (its own bookkeeping key) after
    # task_start. plist_touched=True but neither protected field changed
    # and wakeTime is unchanged. Gate must NOT fire — this is the
    # do-nothing trajectory with Flux side-effects. Score = 30 (same as
    # DO_NOTHING).
    plist_touched=True, final_mtime=TASK_START + 30,
    final_keys=list(EXPECTED_KEYS) + ["version"],
)

PARTIAL_TIER_2 = base(
    # wakeTime set to 380 — within ±30 min of 360 (broad partial only).
    # C1=10, C2=5, C3=15, C4=10, C5=10 = 50. Below pass.
    plist_touched=True, final_mtime=TASK_START + 30,
    final_wakeTime=380,
)

PARTIAL_TIER_1 = base(
    # wakeTime set to 365 — within ±10 min of 360 (tighter partial).
    # C1=10, C2=5, C3=30, C4=10, C5=10 = 65. Strictly below pass 70.
    # This is the worst-case max-partial scenario from Anti-Pattern #4.
    plist_touched=True, final_mtime=TASK_START + 30,
    final_wakeTime=365,
)

FULL_CORRECT = base(
    # wakeTime exactly 360. C1=10, C2=5, C3=60, C4=10, C5=10 = 95. Pass.
    plist_touched=True, final_mtime=TASK_START + 30,
    final_wakeTime=360,
)

FULL_CORRECT_LOSES_C5 = base(
    # wakeTime exactly 360 BUT agent also flipped SUSendProfileInfo.
    # C1=10, C2=5, C3=60, C4=10, C5=0 = 85. Still passes (above 70), but
    # the agent loses anti-gaming credit. Acceptable — wakeTime is right.
    plist_touched=True, final_mtime=TASK_START + 30,
    final_wakeTime=360, final_susend=True,
)

WAKETIME_DELETED = base(
    # Agent deleted the wakeTime key entirely (destructive). C2 zero (no
    # change credit because final_wakeTime is None), C3 zero. C1/C4/C5 OK.
    # 10+0+0+10+10 = 20. Below pass. No false credit.
    plist_touched=True, final_mtime=TASK_START + 30,
    final_wakeTime=None,
)

OUT_OF_RANGE = base(
    # Agent set wakeTime to 480-of-night (e.g., they confused AM/PM and
    # set 6 PM = 1080). C2=5 (changed), C3=0 (outside any tier). 25 total.
    plist_touched=True, final_mtime=TASK_START + 30,
    final_wakeTime=1080,
)

NO_PLIST = base(
    # Plist file missing (corrupted env). Should return score 0 immediately.
    plist_exists=False,
)

PARSE_ERROR = base(
    # Plist parse failed (corrupted). Score 0 immediately.
    parse_error=True,
)


if __name__ == "__main__":
    print("=== Offline verifier tests: set_wake_time_to_6am ===")
    results = [
        run("do-nothing",                 DO_NOTHING,           expect_score=30,  expect_passed=False),
        run("wrong-target-lat-changed",   WRONG_TARGET_GATE_LAT, expect_score=0,  expect_passed=False),
        run("wrong-target-lng-changed",   WRONG_TARGET_GATE_LNG, expect_score=0,  expect_passed=False),
        run("wrong-target-susend-flipped", WRONG_TARGET_GATE_SUSEND, expect_score=0, expect_passed=False),
        run("flux-bookkeeping-key (gate must NOT fire)", FLUX_ADDED_BOOKKEEPING_KEYS, expect_score=30, expect_passed=False),
        run("partial-tier-2 (380)",       PARTIAL_TIER_2,       expect_score=50,  expect_passed=False),
        run("partial-tier-1 (365, MAX)",  PARTIAL_TIER_1,       expect_score=65,  expect_passed=False),
        run("full-correct (360)",         FULL_CORRECT,         expect_score=95,  expect_passed=True),
        run("full-correct, loses C5",     FULL_CORRECT_LOSES_C5, expect_score=85, expect_passed=True),
        run("wakeTime deleted",           WAKETIME_DELETED,     expect_score=30,  expect_passed=False),
        run("out-of-range (1080)",        OUT_OF_RANGE,         expect_score=35,  expect_passed=False),
        run("no plist",                   NO_PLIST,             expect_score=0,   expect_passed=False),
        run("plist parse error",          PARSE_ERROR,          expect_score=0,   expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
