"""Verifier for flux_env / repair_wrong_wake_time_encoding.

Scoring (100 points, pass at 80):
  C1 (10)  Gate: plist exists and parses
  C2 (60)  wakeTime repaired to 480 (8:00 AM in minutes from midnight):
              exact 480 = 60 pts
              within ±15 min (465 or 495) = 30 pts
              within ±30 min (450 or 510) = 10 pts
  C3 (15)  SUEnableAutomaticChecks preserved (still false)
  C4 (15)  SUSendProfileInfo preserved (still false)

Pass 80: requires correct wakeTime (480) + at least one SU key preserved.
  Correct wakeTime alone = 10+60 = 70 < 80 → fail (agent nuked other settings).
  ±15 min wakeTime + both SU = 10+30+15+15 = 70 < 80 → fail (close but not exact).
  Max partial without correct wakeTime: 10+0+15+15 = 40 < 80.

Encoding context:
  Baseline 28800 = 8 hours × 3600 sec/hour = seconds from midnight for 8:00 AM.
  Correct format: 8 hours × 60 min/hour = 480 minutes from midnight.
  wakeTime = 28800 overflows the 15-minute stepper range (max valid ≈ 1440 = 24:00).

Wrong-target gate: plist touched AND wakeTime unchanged at 28800 AND SU keys modified → 0.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict, List

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 80
BASELINE_WAKETIME = 28800
TARGET_WAKETIME = 480
REMOTE_RESULT = "/tmp/repair_wrong_wake_time_encoding_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "plist_gate": 0,
        "wakeTime_repaired": 0,
        "su_enable_preserved": 0,
        "su_send_preserved": 0,
    }


def verify_repair_wrong_wake_time_encoding(
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
                "feedback": "Plist does not exist (+0)",
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
    initial_sue = data.get("initial_SUEnableAutomaticChecks")
    final_sue = data.get("final_SUEnableAutomaticChecks")
    sue_modified = (initial_sue is not None and final_sue is not None and initial_sue != final_sue)
    initial_sus = data.get("initial_SUSendProfileInfo")
    final_sus = data.get("final_SUSendProfileInfo")
    sus_modified = (initial_sus is not None and final_sus is not None and initial_sus != final_sus)

    if plist_touched and wakeTime_unchanged and (sue_modified or sus_modified):
        changed = []
        if sue_modified: changed.append(f"SUEnableAutomaticChecks ({initial_sue}→{final_sue})")
        if sus_modified: changed.append(f"SUSendProfileInfo ({initial_sus}→{final_sus})")
        return {"score": 0, "passed": False,
                "feedback": (f"Wrong target: modified {', '.join(changed)} but left wakeTime "
                             f"at broken baseline {BASELINE_WAKETIME}. Fix wakeTime instead (+0)."),
                "subscores": subscores}

    # ---- C2: wakeTime repaired ----
    if final_wt == TARGET_WAKETIME:
        subscores["wakeTime_repaired"] = 60
        feedback.append(f"wakeTime == {TARGET_WAKETIME} (8:00 AM — correct encoding) (+60)")
    elif final_wt is not None and 465 <= final_wt <= 495:
        subscores["wakeTime_repaired"] = 30
        feedback.append(f"wakeTime {final_wt} within ±15 min of {TARGET_WAKETIME} (+30 partial)")
    elif final_wt is not None and 450 <= final_wt <= 510:
        subscores["wakeTime_repaired"] = 10
        feedback.append(f"wakeTime {final_wt} within ±30 min of {TARGET_WAKETIME} (+10 partial)")
    elif final_wt == BASELINE_WAKETIME or final_wt is None:
        feedback.append(f"wakeTime still at broken value {final_wt} — not repaired (+0)")
    else:
        feedback.append(f"wakeTime {final_wt} is not 480 and outside any partial window (+0)")

    # ---- C3: SUEnableAutomaticChecks preserved ----
    if initial_sue is False and final_sue is False:
        subscores["su_enable_preserved"] = 15
        feedback.append("SUEnableAutomaticChecks preserved false (+15)")
    else:
        feedback.append(f"SUEnableAutomaticChecks changed {initial_sue}→{final_sue} (+0)")

    # ---- C4: SUSendProfileInfo preserved ----
    if initial_sus is False and final_sus is False:
        subscores["su_send_preserved"] = 15
        feedback.append("SUSendProfileInfo preserved false (+15)")
    else:
        feedback.append(f"SUSendProfileInfo changed {initial_sus}→{final_sus} (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): wakeTime encoding repaired to {final_wt}.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
