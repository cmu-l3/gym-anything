"""Verifier for flux_env / configure_complete_sleep_profile.

Scoring (100 points, pass at 80):
  C1 (10)  Gate: plist exists, both KV dumps valid
  C2 (35)  wakeTime == 390 (6:30 AM):
              exact 390 = 35
              ±15 min (375 or 405) = 20
              ±30 min (360 or 420) = 10
  C3 (30)  Bedtime K changed to ~1900 via plist diff:
              K ∈ [1850, 1950] = 30
              K ∈ [1700, 2100] = 15
              K ∈ [1500, 2300] =  5
  C4 (25)  SUEnableAutomaticChecks == false

Pass 80: requires all three changes at close-to-exact values.
  Exact wakeTime + exact K + no SU fix = 10+35+30+0=75 < 80 → still fails.
  Close wakeTime (±15) + exact K + SU = 10+20+30+25=85 ≥ 80 → passes.

Max partial (no full criterion): 10+20+15+0=45 < 80 → AP4 satisfied.
  (SU is binary — fully correct earns 25, nothing earns 0.)

Wrong-target gate: if SUSendProfileInfo (baseline=false) is flipped to true
  while wakeTime or K are unchanged → score 0 (agent edited protected field).
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 80
BASELINE_WAKETIME = 600
TARGET_WAKETIME = 390
TARGET_K = 1900
REMOTE_RESULT = "/tmp/configure_complete_sleep_profile_result.json"

NON_K_KEYS = frozenset({
    "wakeTime", "version", "steptime", "wakeDay", "wakeNight", "SULastCheckTime", "latestVer",
})
K_MIN, K_MAX = 1000, 7500


def _empty_subscores() -> Dict[str, int]:
    return {
        "plist_gate": 0,
        "wakeTime_target": 0,
        "k_temp_target": 0,
        "su_enable_fixed": 0,
    }


def _find_k_candidate(
    initial_kv: Dict[str, Any], final_kv: Dict[str, Any]
) -> Tuple[Optional[str], Optional[float]]:
    best_key, best_val, best_dist = None, None, float("inf")
    for key, val in final_kv.items():
        if key in NON_K_KEYS:
            continue
        if not isinstance(val, (int, float)):
            continue
        if not (K_MIN <= val <= K_MAX):
            continue
        if initial_kv.get(key) == val:
            continue
        d = abs(val - TARGET_K)
        if d < best_dist:
            best_dist, best_key, best_val = d, key, float(val)
    return best_key, best_val


def verify_configure_complete_sleep_profile(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False,
                "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as fh:
        local_path = fh.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            logger.warning("copy_from_env failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Could not retrieve result file: {exc}",
                    "subscores": _empty_subscores()}
        try:
            with open(local_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as exc:
            return {"score": 0, "passed": False,
                    "feedback": f"Export produced unparseable JSON: {exc}",
                    "subscores": _empty_subscores()}
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    subscores = _empty_subscores()
    feedback: List[str] = []

    # ---- C1: gate ----
    if not data.get("plist_exists", False):
        return {"score": 0, "passed": False,
                "feedback": "Plist does not exist (+0)",
                "subscores": subscores}
    initial_kv = data.get("initial_plist_kv", {})
    final_kv = data.get("final_plist_kv", {})
    if not isinstance(initial_kv, dict) or "_error" in initial_kv:
        return {"score": 0, "passed": False,
                "feedback": f"Initial KV dump invalid: {initial_kv}",
                "subscores": subscores}
    if not isinstance(final_kv, dict) or "_error" in final_kv:
        return {"score": 0, "passed": False,
                "feedback": f"Final KV dump invalid: {final_kv}",
                "subscores": subscores}
    subscores["plist_gate"] = 10
    feedback.append("Plist KV dumps valid (+10)")

    # ---- Wrong-target gate ----
    initial_sus = data.get("initial_SUSendProfileInfo")
    final_sus = data.get("final_SUSendProfileInfo")
    sus_flipped = (initial_sus is False and final_sus is True)
    final_wt = data.get("final_wakeTime")
    k_key_precheck, _ = _find_k_candidate(initial_kv, final_kv)
    wt_unchanged = (final_wt == BASELINE_WAKETIME or final_wt is None)
    if sus_flipped and wt_unchanged and k_key_precheck is None:
        return {"score": 0, "passed": False,
                "feedback": ("Wrong target: SUSendProfileInfo flipped to true but "
                             "wakeTime and Bedtime K were not changed (+0)."),
                "subscores": subscores}

    # ---- C2: wakeTime ----
    if final_wt == TARGET_WAKETIME:
        subscores["wakeTime_target"] = 35
        feedback.append(f"wakeTime == {TARGET_WAKETIME} (6:30 AM) (+35)")
    elif final_wt is not None and 375 <= final_wt <= 405:
        subscores["wakeTime_target"] = 20
        feedback.append(f"wakeTime {final_wt} within ±15 min of {TARGET_WAKETIME} (+20 partial)")
    elif final_wt is not None and 360 <= final_wt <= 420:
        subscores["wakeTime_target"] = 10
        feedback.append(f"wakeTime {final_wt} within ±30 min of {TARGET_WAKETIME} (+10 partial)")
    else:
        feedback.append(f"wakeTime {final_wt} outside partial window (target 390) (+0)")

    # ---- C3: Bedtime K ----
    k_key, k_val = _find_k_candidate(initial_kv, final_kv)
    if k_val is None:
        feedback.append("No Bedtime K change detected in plist (+0)")
    elif 1850 <= k_val <= 1950:
        subscores["k_temp_target"] = 30
        feedback.append(f"Bedtime K = {k_val:.0f}K via '{k_key}' (Candle target) (+30)")
    elif 1700 <= k_val <= 2100:
        subscores["k_temp_target"] = 15
        feedback.append(f"Bedtime K = {k_val:.0f}K via '{k_key}' — close to 1900K (+15 partial)")
    elif 1500 <= k_val <= 2300:
        subscores["k_temp_target"] = 5
        feedback.append(f"Bedtime K = {k_val:.0f}K via '{k_key}' — direction correct (+5 partial)")
    else:
        feedback.append(f"K change detected ({k_key}={k_val:.0f}) outside any window (+0)")

    # ---- C4: SUEnableAutomaticChecks fixed ----
    final_sue = data.get("final_SUEnableAutomaticChecks")
    if final_sue is False:
        subscores["su_enable_fixed"] = 25
        feedback.append("SUEnableAutomaticChecks=false (fixed) (+25)")
    else:
        feedback.append(f"SUEnableAutomaticChecks={final_sue!r} — should be false (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): sleep profile configured.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
