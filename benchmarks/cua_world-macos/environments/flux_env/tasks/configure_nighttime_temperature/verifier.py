"""Verifier for flux_env / configure_nighttime_temperature.

Scoring (100 points, pass at 75):
  C1 (10)  Gate: plist exists and both KV dumps are valid
  C2 (70)  A plist key changed to a Bedtime K value near 1900:
              70 if the changed K ∈ [1850, 1950]  (Candle preset)
              50 if the changed K ∈ [1700, 2100]  (close but not exact)
              20 if the changed K ∈ [1500, 2300]  (direction correct)
  C3 (10)  wakeTime preserved at baseline 480
  C4 (10)  SUSendProfileInfo preserved as false

Max partial: 10+20+10+10 = 50 < 75 → cannot pass on partials alone.

Detection strategy (key-name agnostic):
  Diff initial_plist_kv vs final_plist_kv. Any key that:
    - Is new in final OR changed value from initial, AND
    - Has an integer/float value in [1000, 7500] (K-temp range), AND
    - Is NOT one of the known non-K keys (wakeTime, version, steptime, etc.)
  is a candidate for the Bedtime K key. Score is based on the closest
  candidate value to 1900K.

Wrong-target gate: if plist was touched AND wakeTime was simultaneously
  deleted or changed from 480 → score 0 (agent edited wrong thing).
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 75
BASELINE_WAKETIME = 480
REMOTE_RESULT = "/tmp/configure_nighttime_temperature_result.json"
TARGET_K = 1900

# Keys that contain integers but are NOT K-temperature values.
NON_K_KEYS = frozenset({
    "wakeTime", "version", "steptime", "wakeDay", "wakeNight",
    "SULastCheckTime", "latestVer",
})

# K-temperature plausible range (absolute bounds for the filter).
K_MIN, K_MAX = 1000, 7500


def _empty_subscores() -> Dict[str, int]:
    return {
        "plist_gate": 0,
        "k_temp_target": 0,
        "wakeTime_preserved": 0,
        "sus_preserved": 0,
    }


def _find_k_candidate(
    initial_kv: Dict[str, Any],
    final_kv: Dict[str, Any],
) -> Tuple[Optional[str], Optional[float]]:
    """Return (key_name, value) of the best K-temperature candidate, or (None, None)."""
    best_key: Optional[str] = None
    best_val: Optional[float] = None
    best_dist = float("inf")

    for key, val in final_kv.items():
        if key in NON_K_KEYS:
            continue
        if not isinstance(val, (int, float)):
            continue
        if not (K_MIN <= val <= K_MAX):
            continue
        # Check this key either appeared or changed.
        initial_val = initial_kv.get(key)
        if initial_val == val:
            continue  # unchanged — agent didn't touch it
        # It's a new or changed K-range value.
        dist = abs(val - TARGET_K)
        if dist < best_dist:
            best_dist = dist
            best_key = key
            best_val = float(val)

    return best_key, best_val


def verify_configure_nighttime_temperature(
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
                "feedback": f"Initial plist KV dump invalid: {initial_kv}",
                "subscores": subscores}
    if not isinstance(final_kv, dict) or "_error" in final_kv:
        return {"score": 0, "passed": False,
                "feedback": f"Final plist KV dump invalid: {final_kv}",
                "subscores": subscores}
    subscores["plist_gate"] = 10
    feedback.append("Plist KV dumps valid (+10)")

    plist_touched = bool(data.get("plist_touched_after_task_start", False))
    final_wt = data.get("final_wakeTime")

    # ---- Wrong-target gate ----
    if plist_touched and final_wt is not None and final_wt != BASELINE_WAKETIME:
        return {"score": 0, "passed": False,
                "feedback": (f"Wrong target: wakeTime was modified from {BASELINE_WAKETIME} "
                             f"to {final_wt}. Task requires changing the Bedtime K temperature, "
                             f"not wakeTime (+0)."),
                "subscores": subscores}

    # ---- C2: K-temperature change detected ----
    k_key, k_val = _find_k_candidate(initial_kv, final_kv)
    if k_val is None:
        feedback.append(f"No K-temperature change detected in plist (target 1900K) (+0)")
    elif 1850 <= k_val <= 1950:
        subscores["k_temp_target"] = 70
        feedback.append(f"Bedtime K = {k_val:.0f}K via key '{k_key}' — Candle target exact (+70)")
    elif 1700 <= k_val <= 2100:
        subscores["k_temp_target"] = 50
        feedback.append(f"Bedtime K = {k_val:.0f}K via key '{k_key}' — close to 1900K target (+50 partial)")
    elif 1500 <= k_val <= 2300:
        subscores["k_temp_target"] = 20
        feedback.append(f"Bedtime K = {k_val:.0f}K via key '{k_key}' — direction correct but far (+20 partial)")
    else:
        feedback.append(f"K change detected ({k_key}={k_val:.0f}) but outside any partial window (+0)")

    # ---- C3: wakeTime preserved ----
    if final_wt == BASELINE_WAKETIME:
        subscores["wakeTime_preserved"] = 10
        feedback.append(f"wakeTime preserved at {BASELINE_WAKETIME} (+10)")
    else:
        feedback.append(f"wakeTime changed from {BASELINE_WAKETIME} to {final_wt} — unrelated edit (+0)")

    # ---- C4: SUSendProfileInfo preserved ----
    initial_sus = data.get("initial_SUSendProfileInfo")
    final_sus = data.get("final_SUSendProfileInfo")
    if initial_sus is False and final_sus is False:
        subscores["sus_preserved"] = 10
        feedback.append("SUSendProfileInfo preserved as false (+10)")
    else:
        feedback.append(f"SUSendProfileInfo changed {initial_sus}→{final_sus} — unrelated edit (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): Bedtime K = {k_val:.0f}K via '{k_key}'.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
