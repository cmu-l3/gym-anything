"""Verifier for flux_env / sync_wake_time_to_circadian_schedule.

Scoring (100 points, pass at 85):
  C1 (10)  Gate: plist exists and parses
  C2 (60)  wakeTime at target 315 (5:15 AM):
              exact 315 = 60 pts
              within ±15 min (300 or 330) = 30 pts
              within ±30 min (285 or 345) = 10 pts
  C3 (15)  SUEnableAutomaticChecks == false
  C4 (15)  SUSendProfileInfo == false

Pass threshold 85: requires exact wakeTime (315) + at least one SU fix,
  OR exact wakeTime + both SU fixes.
  Getting wakeTime to ±15 min (300/330) + both SU fixes = max 70 < 85 → still fails.
  Partial tier max without any full credit: 10+30+15+15 = 70 < 85.

Target derivation (documented here so the verifier is self-contained):
  Pittsburgh, PA civil twilight July 15 = 6:02 AM
  6:02 AM − 45 min = 5:17 AM
  Nearest 15-min f.lux increment: 5:15 AM = 315 minutes from midnight
  (315 ÷ 15 = 21 exactly → valid stepper value)

Wrong-target gate: if plist was touched after task_start AND wakeTime is
  still at baseline 480 AND a protected field (lat, SUHasLaunchedBefore) was
  modified → score 0 immediately.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict, List

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 85
TARGET_WAKETIME = 315
BASELINE_WAKETIME = 480
REMOTE_RESULT = "/tmp/sync_wake_time_to_circadian_schedule_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "plist_gate": 0,
        "wakeTime_target": 0,
        "su_enable_fixed": 0,
        "su_send_fixed": 0,
    }


def verify_sync_wake_time_to_circadian_schedule(
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

    # ---- C1: plist gate ----
    if not data.get("plist_exists", False):
        return {"score": 0, "passed": False,
                "feedback": "Plist does not exist at ~/Library/Preferences/org.herf.Flux.plist (+0)",
                "subscores": subscores}
    if data.get("plist_parse_error", False):
        return {"score": 0, "passed": False,
                "feedback": "Plist exists but failed to parse (+0)",
                "subscores": subscores}
    subscores["plist_gate"] = 10
    feedback.append("Plist exists and parses (+10)")

    final_wt = data.get("final_wakeTime")
    plist_touched = bool(data.get("plist_touched_after_task_start", False))

    # ---- Wrong-target gate ----
    wakeTime_unchanged = (final_wt == BASELINE_WAKETIME) or (final_wt is None)
    initial_lat = data.get("initial_lat")
    final_lat = data.get("final_lat")
    lat_modified = (
        initial_lat is not None and final_lat is not None
        and abs(initial_lat - final_lat) >= 1e-4
    )
    if plist_touched and wakeTime_unchanged and lat_modified:
        return {"score": 0, "passed": False,
                "feedback": (f"Wrong target: plist was edited (lat changed "
                             f"{initial_lat}→{final_lat}) but wakeTime was not changed "
                             f"from baseline {BASELINE_WAKETIME}. Edit wakeTime instead (+0)."),
                "subscores": subscores}

    # ---- C2: wakeTime tier ----
    if final_wt == TARGET_WAKETIME:
        subscores["wakeTime_target"] = 60
        feedback.append(f"wakeTime == {TARGET_WAKETIME} (5:15 AM — correct circadian offset) (+60)")
    elif final_wt is not None and 300 <= final_wt <= 330:
        subscores["wakeTime_target"] = 30
        feedback.append(f"wakeTime {final_wt} is within ±15 min of target {TARGET_WAKETIME} (+30 partial)")
    elif final_wt is not None and 285 <= final_wt <= 345:
        subscores["wakeTime_target"] = 10
        feedback.append(f"wakeTime {final_wt} is within ±30 min of target {TARGET_WAKETIME} (+10 partial)")
    elif final_wt is None:
        feedback.append("wakeTime key missing from plist (+0)")
    else:
        feedback.append(f"wakeTime {final_wt} is outside any partial-credit window (target 315) (+0)")

    # ---- C3: SUEnableAutomaticChecks disabled ----
    final_sue = data.get("final_SUEnableAutomaticChecks")
    if final_sue is False:
        subscores["su_enable_fixed"] = 15
        feedback.append("SUEnableAutomaticChecks=false (+15)")
    else:
        feedback.append(f"SUEnableAutomaticChecks={final_sue!r} — should be false (+0)")

    # ---- C4: SUSendProfileInfo disabled ----
    final_sus = data.get("final_SUSendProfileInfo")
    if final_sus is False:
        subscores["su_send_fixed"] = 15
        feedback.append("SUSendProfileInfo=false (+15)")
    else:
        feedback.append(f"SUSendProfileInfo={final_sus!r} — should be false (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): circadian schedule configured correctly.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
