"""Verifier for flux_env / set_wake_time_to_6am.

Scoring (100 points, pass at 70):
  C1 (10)  Gate: plist exists, parses, and is the expected domain
  C2 ( 5)  wakeTime changed from baseline 480 to anything else
  C3 (60)  wakeTime equals target 360 exactly
              partial 30 if within ±10 min (350-370 inclusive)
              partial 15 if within ±30 min (330-390 inclusive)
              (the 3 C3 tiers are mutually exclusive; max C3 partial = 30)
  C4 (10)  Anti-gaming: lat preserved at baseline (≈ 40.4406)
  C5 (10)  Anti-gaming: SUSendProfileInfo preserved as false

Max partial total (no full credits on any criterion):
  10 + 5 + 30 + 10 + 10 = 65  →  strictly < pass threshold 70.  ✓
  Per Anti-Pattern #4.

Strict wrong-target gate (Pattern #2 in
03_verification_patterns.md):
  If the agent touched the plist (mtime > task_start) AND left wakeTime
  unchanged AND modified a *protected* field (lat, lng, or
  SUSendProfileInfo) → score=0 immediately, regardless of C1/C4/C5
  credits. This blocks the gaming strategy of "edit some other meaningful
  setting and hope for partial credit".

  Why not gate on "any new key added": Flux itself writes harmless
  bookkeeping keys like `version` and `wakeDay`/`wakeNight` shortly after
  launch. Treating those as "agent introduced an unrelated key" would
  punish do-nothing trajectories. We instead gate on changes to a
  specific protected set (lat, lng, SUSendProfileInfo) the agent would
  only modify deliberately.

Read pattern: copy_from_env(/tmp/set_wake_time_to_6am_result.json, local) —
produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict, List


logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70
TARGET_WAKETIME = 360
BASELINE_WAKETIME = 480
REMOTE_RESULT = "/tmp/set_wake_time_to_6am_result.json"

# "Protected" keys: the agent must not modify these. If wakeTime is
# unchanged AND any of these is modified after task_start, the strict
# wrong-target gate fires. (Note we cannot use a generic "key wasn't here
# before" gate because Flux writes its own bookkeeping keys — `version`,
# possibly `wakeDay` / `wakeNight` / `latestVer` — shortly after launch.)
#
# `lat` and `lng` are both included so the gate is symmetric across the
# location pair — an agent that flips only `lng` is just as much "wrong
# target" as one that flips only `lat`.
PROTECTED_KEYS_FOR_GATE = ("lat", "lng", "SUSendProfileInfo")


def _empty_subscores() -> Dict[str, int]:
    return {
        "plist_gate": 0,
        "wakeTime_changed": 0,
        "wakeTime_target": 0,
        "anti_gaming_lat": 0,
        "anti_gaming_susend": 0,
    }


def verify_set_wake_time_to_6am(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False,
                "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    # Pull export-script JSON onto the host for parsing.
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
    plist_exists = bool(data.get("plist_exists", False))
    parse_error = bool(data.get("plist_parse_error", False))
    final_keys = data.get("final_plist_keys", []) or []
    if not isinstance(final_keys, list):
        final_keys = []
    if not plist_exists:
        return {"score": 0, "passed": False,
                "feedback": "Plist file does not exist at ~/Library/Preferences/org.herf.Flux.plist (+0)",
                "subscores": subscores}
    if parse_error:
        return {"score": 0, "passed": False,
                "feedback": "Plist exists but does not parse (corruption or wrong format)",
                "subscores": subscores}
    subscores["plist_gate"] = 10
    feedback.append("Plist exists and parses (+10)")

    final_wakeTime = data.get("final_wakeTime")
    initial_wakeTime = data.get("initial_wakeTime")
    plist_touched = bool(data.get("plist_touched_after_task_start", False))

    # ---- Strict wrong-target gate ----
    # If the agent touched the plist after task_start, left wakeTime
    # unchanged, AND modified one of the protected fields (lat or
    # SUSendProfileInfo), they edited the wrong setting → score 0.
    wakeTime_unchanged = (final_wakeTime == BASELINE_WAKETIME) or (
        final_wakeTime is None and initial_wakeTime == BASELINE_WAKETIME)
    initial_lat = data.get("initial_lat")
    final_lat = data.get("final_lat")
    lat_modified = (
        initial_lat is not None and final_lat is not None
        and abs(initial_lat - final_lat) >= 1e-4
    )
    initial_lng = data.get("initial_lng")
    final_lng = data.get("final_lng")
    lng_modified = (
        initial_lng is not None and final_lng is not None
        and abs(initial_lng - final_lng) >= 1e-4
    )
    initial_su = data.get("initial_SUSendProfileInfo")
    final_su = data.get("final_SUSendProfileInfo")
    su_modified = (initial_su is not None and final_su is not None and initial_su != final_su)

    if plist_touched and wakeTime_unchanged and (lat_modified or lng_modified or su_modified):
        modified_fields = []
        if lat_modified:
            modified_fields.append(f"lat ({initial_lat} → {final_lat})")
        if lng_modified:
            modified_fields.append(f"lng ({initial_lng} → {final_lng})")
        if su_modified:
            modified_fields.append(f"SUSendProfileInfo ({initial_su} → {final_su})")
        return {"score": 0, "passed": False,
                "feedback": (f"Wrong target: agent modified protected field(s) "
                             f"{', '.join(modified_fields)} but left wakeTime at "
                             f"baseline {BASELINE_WAKETIME}. Edit `wakeTime` instead (+0)."),
                "subscores": subscores}

    # ---- C2: wakeTime changed at all ----
    if final_wakeTime is None:
        # wakeTime got deleted from the plist entirely — agent did something
        # destructive. No C2 credit; downstream C3 will also score 0.
        feedback.append("wakeTime key missing from plist (agent deleted it?) (+0)")
    elif final_wakeTime != BASELINE_WAKETIME:
        subscores["wakeTime_changed"] = 5
        feedback.append(f"wakeTime changed from {BASELINE_WAKETIME} to {final_wakeTime} (+5)")
    else:
        feedback.append(f"wakeTime unchanged from baseline {BASELINE_WAKETIME} (+0)")

    # ---- C3: wakeTime target tiers (mutually exclusive) ----
    if final_wakeTime == TARGET_WAKETIME:
        subscores["wakeTime_target"] = 60
        feedback.append(f"wakeTime exactly {TARGET_WAKETIME} (6:00 AM target) (+60)")
    elif final_wakeTime is not None and 350 <= final_wakeTime <= 370:
        subscores["wakeTime_target"] = 30
        feedback.append(f"wakeTime within ±10 min of target ({final_wakeTime}) (+30 partial)")
    elif final_wakeTime is not None and 330 <= final_wakeTime <= 390:
        subscores["wakeTime_target"] = 15
        feedback.append(f"wakeTime within ±30 min of target ({final_wakeTime}) (+15 partial)")
    elif final_wakeTime is not None:
        feedback.append(f"wakeTime is {final_wakeTime}, outside any partial-credit window (+0)")

    # ---- C4: lat preserved ----
    initial_lat = data.get("initial_lat")
    final_lat = data.get("final_lat")
    if initial_lat is not None and final_lat is not None and abs(initial_lat - final_lat) < 1e-4:
        subscores["anti_gaming_lat"] = 10
        feedback.append(f"lat preserved at {final_lat:.4f} (+10)")
    else:
        feedback.append(f"lat changed from {initial_lat} to {final_lat} — unrelated edit (+0)")

    # ---- C5: SUSendProfileInfo preserved (still false) ----
    initial_su = data.get("initial_SUSendProfileInfo")
    final_su = data.get("final_SUSendProfileInfo")
    if initial_su is False and final_su is False:
        subscores["anti_gaming_susend"] = 10
        feedback.append("SUSendProfileInfo preserved as false (+10)")
    else:
        feedback.append(f"SUSendProfileInfo changed from {initial_su} to {final_su} — unrelated edit (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): wakeTime correctly set to {final_wakeTime}.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
