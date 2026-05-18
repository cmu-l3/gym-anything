"""Offline tests for verify_configure_complete_sleep_profile."""
import json, os, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from verifier import verify_configure_complete_sleep_profile as verify

_INITIAL_KV = {
    "wakeTime": 600,
    "SUEnableAutomaticChecks": True,
    "SUSendProfileInfo": False,
    "SUHasLaunchedBefore": True,
    "lat": 40.4406, "lng": -79.9959, "place": "Pittsburgh, PA", "version": 3,
}

_BASE = {
    "task": "configure_complete_sleep_profile",
    "task_start": 1000000,
    "plist_exists": True,
    "plist_touched_after_task_start": True,
    "initial_plist_mtime": 999999, "final_plist_mtime": 1000001,
    "initial_wakeTime": 600,  "final_wakeTime": 600,
    "initial_SUEnableAutomaticChecks": True,  "final_SUEnableAutomaticChecks": True,
    "initial_SUSendProfileInfo": False,       "final_SUSendProfileInfo": False,
    "initial_plist_kv": _INITIAL_KV,
    "final_plist_kv": dict(_INITIAL_KV),  # unchanged
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
    # gate=10, wakeTime unchanged, no K, SUEnable still true
    assert r["passed"] is False
    assert r["score"] == 10, f"expected 10, got {r['score']}"

def test_wrong_target_sus_flipped():
    final_kv = dict(_INITIAL_KV)  # no K, no wakeTime change
    r = _run({**_BASE, "final_SUSendProfileInfo": True, "final_plist_kv": final_kv})
    assert r["score"] == 0, f"wrong-target gate: expected 0, got {r['score']}"

def test_wakeTime_and_su_only():
    r = _run({**_BASE, "final_wakeTime": 390, "final_SUEnableAutomaticChecks": False})
    # 10+35+0+25=70 < 80
    assert r["passed"] is False
    assert r["score"] == 70, f"expected 70, got {r['score']}"

def test_wakeTime_and_k_only():
    final_kv = {**_INITIAL_KV, "nightColor": 1900}
    r = _run({**_BASE, "final_wakeTime": 390, "final_plist_kv": final_kv})
    # 10+35+30+0=75 < 80
    assert r["passed"] is False
    assert r["score"] == 75, f"expected 75, got {r['score']}"

def test_close_wakeTime_k_su():
    # wakeTime ±15 (375), K exact, SUEnable fixed
    final_kv = {**_INITIAL_KV, "nightColor": 1900}
    r = _run({**_BASE, "final_wakeTime": 375,
              "final_SUEnableAutomaticChecks": False, "final_plist_kv": final_kv})
    # 10+20+30+25=85 ≥ 80
    assert r["passed"] is True
    assert r["score"] == 85, f"expected 85, got {r['score']}"

def test_full_correct():
    final_kv = {**_INITIAL_KV, "nightColor": 1900}
    r = _run({**_BASE, "final_wakeTime": 390,
              "final_SUEnableAutomaticChecks": False, "final_plist_kv": final_kv})
    assert r["passed"] is True
    assert r["score"] == 100, f"expected 100, got {r['score']}"

def test_close_k():
    # K=1800 (±150 tier = 15 pts)
    final_kv = {**_INITIAL_KV, "nightColor": 1800}
    r = _run({**_BASE, "final_wakeTime": 390,
              "final_SUEnableAutomaticChecks": False, "final_plist_kv": final_kv})
    # 10+35+15+25=85 ≥ 80
    assert r["passed"] is True
    assert r["score"] == 85, f"expected 85, got {r['score']}"

def test_plist_missing():
    r = _run({**_BASE, "plist_exists": False})
    assert r["score"] == 0 and r["passed"] is False

if __name__ == "__main__":
    tests = [
        test_do_nothing, test_wrong_target_sus_flipped,
        test_wakeTime_and_su_only, test_wakeTime_and_k_only,
        test_close_wakeTime_k_su, test_full_correct, test_close_k, test_plist_missing,
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
