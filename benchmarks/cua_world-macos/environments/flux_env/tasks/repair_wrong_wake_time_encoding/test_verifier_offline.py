"""Offline tests for verify_repair_wrong_wake_time_encoding."""
import json, os, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from verifier import verify_repair_wrong_wake_time_encoding as verify

_BASE = {
    "task": "repair_wrong_wake_time_encoding",
    "task_start": 1000000,
    "plist_exists": True,
    "plist_touched_after_task_start": True,
    "plist_parse_error": False,
    "initial_plist_mtime": 999999,
    "final_plist_mtime": 1000001,
    "initial_wakeTime": 28800,
    "final_wakeTime": 28800,   # unchanged = do-nothing
    "initial_SUEnableAutomaticChecks": False,
    "final_SUEnableAutomaticChecks": False,
    "initial_SUSendProfileInfo": False,
    "final_SUSendProfileInfo": False,
    "initial_lat": 40.4406,
    "final_lat": 40.4406,
    "final_plist_keys": ["lat", "wakeTime", "SUEnableAutomaticChecks", "SUSendProfileInfo"],
}

def _make_env(d):
    tf = tempfile.mktemp(suffix=".json")
    with open(tf, "w") as f: json.dump(d, f)
    def copy_from_env(remote, local):
        with open(tf) as src, open(local, "w") as dst: dst.write(src.read())
    return {"copy_from_env": copy_from_env}

def _run(d): return verify({}, _make_env(d), {})

def test_do_nothing():
    r = _run({**_BASE})
    assert r["passed"] is False
    # 10 (gate) + 0 (wakeTime) + 15 (SUE preserved) + 15 (SUS preserved) = 40
    assert r["score"] == 40, f"expected 40, got {r['score']}"

def test_wrong_target_sue_modified():
    r = _run({**_BASE, "final_SUEnableAutomaticChecks": True})
    assert r["score"] == 0, f"wrong-target gate: expected 0, got {r['score']}"

def test_wrong_target_sus_modified():
    r = _run({**_BASE, "final_SUSendProfileInfo": True})
    assert r["score"] == 0, f"wrong-target gate: expected 0, got {r['score']}"

def test_partial_tier1():
    # wakeTime ±15 (e.g., 465), both SU preserved
    r = _run({**_BASE, "final_wakeTime": 465})
    assert r["passed"] is False
    assert r["score"] == 70, f"expected 70 (10+30+15+15), got {r['score']}"

def test_partial_tier2():
    # wakeTime ±30 (e.g., 510)
    r = _run({**_BASE, "final_wakeTime": 510})
    assert r["passed"] is False
    assert r["score"] == 50, f"expected 50 (10+10+15+15), got {r['score']}"

def test_full_correct():
    r = _run({**_BASE, "final_wakeTime": 480})
    assert r["passed"] is True
    assert r["score"] == 100, f"expected 100, got {r['score']}"

def test_correct_wakeTime_broke_sue():
    r = _run({**_BASE, "final_wakeTime": 480, "final_SUEnableAutomaticChecks": True})
    assert r["score"] == 85, f"expected 85 (10+60+0+15), got {r['score']}"
    assert r["passed"] is True

def test_correct_wakeTime_broke_both_su():
    r = _run({**_BASE, "final_wakeTime": 480,
              "final_SUEnableAutomaticChecks": True, "final_SUSendProfileInfo": True})
    assert r["score"] == 70, f"expected 70 (10+60+0+0), got {r['score']}"
    assert r["passed"] is False

def test_plist_missing():
    r = _run({**_BASE, "plist_exists": False})
    assert r["score"] == 0 and r["passed"] is False

if __name__ == "__main__":
    tests = [
        test_do_nothing, test_wrong_target_sue_modified, test_wrong_target_sus_modified,
        test_partial_tier1, test_partial_tier2, test_full_correct,
        test_correct_wakeTime_broke_sue, test_correct_wakeTime_broke_both_su,
        test_plist_missing,
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
