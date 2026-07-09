"""Offline tests for verify_full_preference_audit_and_repair."""
import json, os, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from verifier import verify_full_preference_audit_and_repair as verify

_BASE = {
    "task": "full_preference_audit_and_repair",
    "task_start": 1000000,
    "plist_exists": True,
    "plist_touched_after_task_start": True,
    "plist_parse_error": False,
    "initial_plist_mtime": 999999, "final_plist_mtime": 1000001,
    "initial_wakeTime": 660, "final_wakeTime": 660,
    "initial_SUEnableAutomaticChecks": True,  "final_SUEnableAutomaticChecks": True,
    "initial_SUSendProfileInfo": True,        "final_SUSendProfileInfo": True,
    "initial_lat": 40.4406,                   "final_lat": 40.4406,
    "final_plist_keys": ["lat", "wakeTime", "SUEnableAutomaticChecks", "SUSendProfileInfo"],
}

def _make_env(d):
    tf = tempfile.mktemp(suffix=".json")
    with open(tf, "w") as f: json.dump(d, f)
    def copy_from_env(r, l):
        with open(tf) as s, open(l, "w") as o: o.write(s.read())
    return {"copy_from_env": copy_from_env}

def _run(d): return verify({}, _make_env(d), {})

def test_do_nothing():
    r = _run({**_BASE})
    assert r["passed"] is False
    # gate=10, wakeTime still 660=0, SUEnable still true=0, SUSend still true=0
    assert r["score"] == 10, f"expected 10, got {r['score']}"

def test_wrong_target_lat_changed():
    r = _run({**_BASE, "final_lat": 51.5074})
    assert r["score"] == 0, f"wrong-target gate: expected 0, got {r['score']}"

def test_fix_wakeTime_only():
    r = _run({**_BASE, "final_wakeTime": 480})
    assert r["passed"] is False
    assert r["score"] == 50, f"expected 50 (10+40), got {r['score']}"

def test_fix_both_su_only():
    r = _run({**_BASE, "final_SUEnableAutomaticChecks": False, "final_SUSendProfileInfo": False})
    assert r["passed"] is False
    assert r["score"] == 60, f"expected 60 (10+0+25+25), got {r['score']}"

def test_fix_wakeTime_and_sue():
    r = _run({**_BASE, "final_wakeTime": 480, "final_SUEnableAutomaticChecks": False})
    assert r["passed"] is False
    assert r["score"] == 75, f"expected 75 (10+40+25+0), got {r['score']}"

def test_close_wakeTime_and_both_su():
    # ±30 wakeTime (510) + both SU fixed → 10+20+25+25=80 < 85 → FAIL
    r = _run({**_BASE, "final_wakeTime": 510,
              "final_SUEnableAutomaticChecks": False, "final_SUSendProfileInfo": False})
    assert r["passed"] is False
    assert r["score"] == 80, f"expected 80 (10+20+25+25), got {r['score']}"

def test_full_correct():
    r = _run({**_BASE, "final_wakeTime": 480,
              "final_SUEnableAutomaticChecks": False, "final_SUSendProfileInfo": False})
    assert r["passed"] is True
    assert r["score"] == 100, f"expected 100, got {r['score']}"

def test_plist_parse_error():
    r = _run({**_BASE, "plist_parse_error": True})
    assert r["score"] == 0 and r["passed"] is False

def test_plist_missing():
    r = _run({**_BASE, "plist_exists": False})
    assert r["score"] == 0 and r["passed"] is False

if __name__ == "__main__":
    tests = [
        test_do_nothing, test_wrong_target_lat_changed,
        test_fix_wakeTime_only, test_fix_both_su_only, test_fix_wakeTime_and_sue,
        test_close_wakeTime_and_both_su, test_full_correct,
        test_plist_parse_error, test_plist_missing,
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
