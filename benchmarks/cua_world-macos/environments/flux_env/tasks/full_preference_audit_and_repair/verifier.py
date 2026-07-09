"""Verifier for flux_env / full_preference_audit_and_repair.

Scoring (100 points, pass at 85):
  C1 (10)  Gate: plist exists and parses
  C2 (40)  wakeTime == 480 (8:00 AM):
              exact 480 = 40 pts
              within ±30 min (450 or 510) = 20 pts
  C3 (25)  SUEnableAutomaticChecks == false
  C4 (25)  SUSendProfileInfo == false

Pass 85: requires exact wakeTime (480) + both SU keys fixed (all three drifted values corrected).
  ±30 wakeTime + both SU = 10+20+25+25 = 80 < 85 → still fails.
  Exact wakeTime + one SU = 10+40+25+0 = 75 < 85 → fails.
  All three exact = 100 ≥ 85 → passes.

Max partial (no full credits): 10+20+25+25=80 < 85. AP4 satisfied.
  (C3/C4 are binary — having them correct counts as full credit, not partial.)
  When C2 is ±30 (not exact) and C3+C4 both correct: 10+20+25+25=80 < 85 ✓.

Wrong-target gate: plist touched AND wakeTime unchanged at 660 AND lat modified → 0.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict, List

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 85
BASELINE_WAKETIME = 660
TARGET_WAKETIME = 480
REMOTE_RESULT = "/tmp/full_preference_audit_and_repair_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "plist_gate": 0,
        "wakeTime_repaired": 0,
        "su_enable_fixed": 0,
        "su_send_fixed": 0,
    }


def verify_full_preference_audit_and_repair(
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
    initial_lat = data.get("initial_lat")
    final_lat = data.get("final_lat")
    lat_modified = (
        initial_lat is not None and final_lat is not None
        and abs(initial_lat - final_lat) >= 1e-4
    )
    if plist_touched and wakeTime_unchanged and lat_modified:
        return {"score": 0, "passed": False,
                "feedback": (f"Wrong target: lat changed {initial_lat}→{final_lat} "
                             f"but wakeTime left at drifted baseline {BASELINE_WAKETIME} (+0)."),
                "subscores": subscores}

    # ---- C2: wakeTime repaired to 480 ----
    if final_wt == TARGET_WAKETIME:
        subscores["wakeTime_repaired"] = 40
        feedback.append(f"wakeTime == {TARGET_WAKETIME} (8:00 AM — repaired) (+40)")
    elif final_wt is not None and 450 <= final_wt <= 510:
        subscores["wakeTime_repaired"] = 20
        feedback.append(f"wakeTime {final_wt} within ±30 min of {TARGET_WAKETIME} (+20 partial)")
    elif final_wt == BASELINE_WAKETIME or final_wt is None:
        feedback.append(f"wakeTime still at drifted value {final_wt} (+0)")
    else:
        feedback.append(f"wakeTime {final_wt} is not 480 and outside partial window (+0)")

    # ---- C3: SUEnableAutomaticChecks repaired ----
    initial_sue = data.get("initial_SUEnableAutomaticChecks")
    final_sue = data.get("final_SUEnableAutomaticChecks")
    if final_sue is False:
        subscores["su_enable_fixed"] = 25
        feedback.append("SUEnableAutomaticChecks=false (repaired) (+25)")
    else:
        feedback.append(f"SUEnableAutomaticChecks={final_sue!r} — should be false (+0)")

    # ---- C4: SUSendProfileInfo repaired ----
    initial_sus = data.get("initial_SUSendProfileInfo")
    final_sus = data.get("final_SUSendProfileInfo")
    if final_sus is False:
        subscores["su_send_fixed"] = 25
        feedback.append("SUSendProfileInfo=false (repaired) (+25)")
    else:
        feedback.append(f"SUSendProfileInfo={final_sus!r} — should be false (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    drift_fixed = sum([
        final_wt == TARGET_WAKETIME,
        final_sue is False,
        final_sus is False,
    ])
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): all 3 drifted values repaired.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): {drift_fixed}/3 drifted values fixed, "
                           f"need {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
