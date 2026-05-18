"""Offline tests for verify_sync_wake_time_to_circadian_schedule.

All tests mock copy_from_env — no VM or Flux required.
"""
import json, os, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from verifier import verify_sync_wake_time_to_circadian_schedule as verify

_BASE = {
    "task": "sync_wake_time_to_circadian_schedule",
    "task_start": 1000000,
    "plist_exists": True,
    "plist_touched_after_task_start": True,
    "plist_parse_error": False,
    "initial_plist_mtime": 999999,
    "final_plist_mtime": 1000001,
    "initial_wakeTime": 480,
    "final_wakeTime": 480,
    "initial_SUEnableAutomaticChecks": True,
    "final_SUEnableAutomaticChecks": True,
    "initial_SUSendProfileInfo": True,
    "final_SUSendProfileInfo": True,
    "initial_lat": 40.4406,
    "final_lat": 40.4406,
    "final_plist_keys": ["lat", "lng", "wakeTime"],
}

def _make_env(result_dict):
    tf = tempfile.mktemp(suffix=".json")
    with open(tf, "w") as f:
        json.dump(result_dict, f)
    def copy_from_env(remote, local):
        with open(tf) as f:
            data = f.read()
        with open(local, "w") as f:
            f.write(data)
    return {"copy_from_env": copy_from_env}

def _run(d):
    return verify({}, _make_env(d), {})

def test_do_nothing():
    r = _run({**_BASE})
    assert r["passed"] is False
    assert r["score"] == 10, f"expected 10, got {r['score']}"

def test_wrong_target_lat_changed():
    r = _run({**_BASE, "final_lat": 51.5074})  # London
    assert r["score"] == 0, f"wrong-target gate: expected 0, got {r['score']}"
    assert r["passed"] is False
    assert "Wrong target" in r["feedback"]

def test_partial_wakeTime_only():
    # wakeTime correct (315) but SU keys still wrong
    r = _run({**_BASE, "final_wakeTime": 315})
    assert r["passed"] is False
    assert r["score"] == 70, f"expected 70 (10+60+0+0), got {r['score']}"

def test_partial_tier1():
    # wakeTime ±15 (300), SU still wrong
    r = _run({**_BASE, "final_wakeTime": 300})
    assert r["passed"] is False
    assert r["score"] == 40, f"expected 40 (10+30+0+0), got {r['score']}"

def test_partial_wakeTime_and_one_su():
    r = _run({**_BASE, "final_wakeTime": 315, "final_SUEnableAutomaticChecks": False})
    assert r["passed"] is True
    assert r["score"] == 85, f"expected 85 (10+60+15+0), got {r['score']}"

def test_full_correct():
    r = _run({**_BASE,
              "final_wakeTime": 315,
              "final_SUEnableAutomaticChecks": False,
              "final_SUSendProfileInfo": False})
    assert r["passed"] is True
    assert r["score"] == 100, f"expected 100, got {r['score']}"

def test_plist_missing():
    r = _run({**_BASE, "plist_exists": False})
    assert r["score"] == 0 and r["passed"] is False

def test_no_copy_from_env():
    r = verify({}, {}, {})
    assert r["score"] == 0 and r["passed"] is False

if __name__ == "__main__":
    tests = [
        test_do_nothing, test_wrong_target_lat_changed, test_partial_wakeTime_only,
        test_partial_tier1, test_partial_wakeTime_and_one_su, test_full_correct,
        test_plist_missing, test_no_copy_from_env,
    ]
    failures = []
    for t in tests:
        try:
            t()
            print(f"  PASS  {t.__name__}")
        except AssertionError as e:
            print(f"  FAIL  {t.__name__}: {e}")
            failures.append(t.__name__)
    print(f"\n{len(tests)-len(failures)}/{len(tests)} passed")
    sys.exit(len(failures))
