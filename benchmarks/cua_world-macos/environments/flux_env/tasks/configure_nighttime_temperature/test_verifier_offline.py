"""Offline tests for verify_configure_nighttime_temperature.

Tests the key-name-agnostic K-temp diff detection logic.
"""
import json, os, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from verifier import verify_configure_nighttime_temperature as verify

_INITIAL_KV = {
    "wakeTime": 480,
    "SUEnableAutomaticChecks": False,
    "SUSendProfileInfo": False,
    "SUHasLaunchedBefore": True,
    "lat": 40.4406,
    "lng": -79.9959,
    "place": "Pittsburgh, PA",
    "version": 3,
}

_BASE = {
    "task": "configure_nighttime_temperature",
    "task_start": 1000000,
    "plist_exists": True,
    "plist_touched_after_task_start": True,
    "initial_plist_mtime": 999999,
    "final_plist_mtime": 1000001,
    "initial_wakeTime": 480,
    "final_wakeTime": 480,
    "initial_SUSendProfileInfo": False,
    "final_SUSendProfileInfo": False,
    "initial_plist_kv": _INITIAL_KV,
    "final_plist_kv": dict(_INITIAL_KV),  # unchanged = do-nothing
}

def _make_env(result_dict):
    tf = tempfile.mktemp(suffix=".json")
    with open(tf, "w") as f:
        json.dump(result_dict, f)
    def copy_from_env(remote, local):
        with open(tf) as src, open(local, "w") as dst:
            dst.write(src.read())
    return {"copy_from_env": copy_from_env}

def _run(d):
    return verify({}, _make_env(d), {})

def test_do_nothing():
    r = _run({**_BASE})
    assert r["passed"] is False
    assert r["score"] == 30, f"expected 30 (10+0+10+10), got {r['score']}"

def test_wrong_target_wakeTime_changed():
    final_kv = {**_INITIAL_KV, "someNightKey": 1900}
    r = _run({**_BASE, "final_wakeTime": 600, "final_plist_kv": final_kv})
    assert r["score"] == 0, f"wrong-target gate: expected 0, got {r['score']}"
    assert "Wrong target" in r["feedback"]

def test_k_exact():
    final_kv = {**_INITIAL_KV, "nightColor": 1900}
    r = _run({**_BASE, "final_plist_kv": final_kv})
    assert r["passed"] is True
    assert r["score"] == 100, f"expected 100, got {r['score']}"

def test_k_close():
    # K = 1800 (in [1700,2100]) → 50 pts for K
    final_kv = {**_INITIAL_KV, "nightColor": 1800}
    r = _run({**_BASE, "final_plist_kv": final_kv})
    assert r["passed"] is True
    assert r["score"] == 80, f"expected 80 (10+50+10+10), got {r['score']}"

def test_k_direction():
    # K = 2200 (in [1500,2300]) → 20 pts
    final_kv = {**_INITIAL_KV, "nightColor": 2200}
    r = _run({**_BASE, "final_plist_kv": final_kv})
    assert r["passed"] is False
    assert r["score"] == 50, f"expected 50 (10+20+10+10), got {r['score']}"

def test_k_wrong_range():
    # K = 4000 — clearly daytime K, not nighttime; outside [1500,2300]
    final_kv = {**_INITIAL_KV, "dayColor": 4000}
    r = _run({**_BASE, "final_plist_kv": final_kv})
    assert r["passed"] is False
    # No K candidate within any window
    assert r["score"] == 30, f"expected 30, got {r['score']}"

def test_non_k_key_ignored():
    # steptime = 1900 should NOT be counted as K (it's in NON_K_KEYS)
    final_kv = {**_INITIAL_KV, "steptime": 1900}
    r = _run({**_BASE, "final_plist_kv": final_kv})
    assert r["passed"] is False
    assert r["score"] == 30  # gate + preservation, no K credit

def test_sus_changed_drops_c4():
    final_kv = {**_INITIAL_KV, "nightColor": 1900}
    r = _run({**_BASE, "final_plist_kv": final_kv, "final_SUSendProfileInfo": True})
    assert r["score"] == 90, f"expected 90 (10+70+10+0), got {r['score']}"
    assert r["passed"] is True

def test_plist_missing():
    r = _run({**_BASE, "plist_exists": False})
    assert r["score"] == 0 and r["passed"] is False

if __name__ == "__main__":
    tests = [
        test_do_nothing, test_wrong_target_wakeTime_changed, test_k_exact,
        test_k_close, test_k_direction, test_k_wrong_range, test_non_k_key_ignored,
        test_sus_changed_drops_c4, test_plist_missing,
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
