"""Verifier for presentation_mode_setup on system_settings_env.

Scoring (100 points, pass at 60):
- 20 pts  C1 Dark appearance        NSGlobalDomain.AppleInterfaceStyle == "Dark"
- 20 pts  C2 Dock at left edge      com.apple.dock.orientation == "left"
                                    (partial: 5 if "right" — wrong direction)
- 20 pts  C3 Dock auto-hide on      com.apple.dock.autohide == true
- 20 pts  C4 Small Dock icons       com.apple.dock.tilesize <= 32
                                    (partial: 10 if changed from 48 but > 32)
- 20 pts  C5 24-hour clock          DateFormat contains uppercase "HH" OR
                                    ShowAMPM == false (the System Settings UI
                                    "Show AM/PM" toggle path — live test
                                    showed the toggle writes ShowAMPM=0
                                    without rewriting DateFormat)

Partial-credit upper bound (Anti-Pattern #4 in 14_task_design_antipatterns.md):
    0 + 5 + 0 + 10 + 0 = 15.  Pass threshold 60 > 15 → safe.

Strict wrong-target gate (Pattern #2 in 03_verification_patterns.md): if any
setting was changed from baseline to a non-target value AND zero criteria
score full credit, return score=0 immediately (the agent toggled things but
landed nowhere correct — credit would be misleading).

Reads /tmp/presentation_mode_setup_result.json produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/presentation_mode_setup_result.json"

# Documented baseline values, mirrored from setup_task.sh. Used to decide
# whether a non-target value is "still at baseline" (do-nothing) vs.
# "changed-but-wrong-target" (triggers the strict gate).
BASELINE = {
    "appearance": None,           # AppleInterfaceStyle absent ⇒ Light
    "dock_orientation": "bottom",
    "dock_autohide": False,
    "dock_tilesize": 48,
    "clock_date_format": "EEE MMM d  h:mm a",
    "clock_show_ampm": True,      # baseline: 12-hour with AM/PM marker
}


def _empty_subscores() -> Dict[str, int]:
    return {
        "dark_mode": 0,
        "dock_orientation": 0,
        "dock_autohide": 0,
        "dock_tilesize": 0,
        "clock_24h": 0,
    }


def verify_presentation_mode_setup(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    # Pull the export-script JSON to the host.
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            logger.warning("copy_from_env failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Could not retrieve result file from sandbox: {exc}",
                    "subscores": _empty_subscores()}
        try:
            with open(local_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            logger.warning("result JSON parse failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Export produced unparseable JSON: {exc}",
                    "subscores": _empty_subscores()}
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    # Pull each measured value, defending against missing keys.
    appearance       = data.get("appearance")
    dock_orientation = data.get("dock_orientation")
    dock_autohide    = bool(data.get("dock_autohide", False))
    dock_tilesize    = data.get("dock_tilesize")
    clock_dateformat = data.get("clock_date_format")
    clock_is_24h     = bool(data.get("clock_is_24h", False))

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: Dark appearance (20 pts) ----
    c1_full = c1_baseline = c1_other = False
    if appearance == "Dark":
        subscores["dark_mode"] = 20
        c1_full = True
        feedback.append("Dark appearance enabled (+20)")
    elif appearance is None:   # baseline — Light
        c1_baseline = True
        feedback.append("Appearance still Light — Dark mode not enabled (+0)")
    else:
        c1_other = True
        feedback.append(f"Appearance set to unexpected value {appearance!r} (+0)")

    # ---- C2: Dock at left edge (20 pts, partial 5 for "right") ----
    c2_full = c2_baseline = c2_other = False
    if dock_orientation == "left":
        subscores["dock_orientation"] = 20
        c2_full = True
        feedback.append("Dock at left edge (+20)")
    elif dock_orientation == "right":
        subscores["dock_orientation"] = 5
        c2_other = True
        feedback.append("Dock at right edge — wrong direction (partial +5)")
    elif dock_orientation == "bottom" or dock_orientation is None:
        c2_baseline = True
        feedback.append("Dock still at bottom — position not changed (+0)")
    else:
        c2_other = True
        feedback.append(f"Dock orientation set to unexpected value {dock_orientation!r} (+0)")

    # ---- C3: Dock auto-hide (20 pts) — boolean, no "other" path ----
    c3_full = c3_baseline = c3_other = False
    if dock_autohide:
        subscores["dock_autohide"] = 20
        c3_full = True
        feedback.append("Dock auto-hide enabled (+20)")
    else:
        c3_baseline = True
        feedback.append("Dock auto-hide still off (+0)")

    # ---- C4: Dock tilesize (20 full, 10 partial) ----
    c4_full = c4_baseline = c4_other = False
    if isinstance(dock_tilesize, int) and dock_tilesize <= 32:
        subscores["dock_tilesize"] = 20
        c4_full = True
        feedback.append(f"Dock icon size {dock_tilesize} ≤ 32 (+20)")
    elif dock_tilesize is None or dock_tilesize == 48:
        c4_baseline = True
        feedback.append("Dock icon size still at default 48 (+0)")
    elif isinstance(dock_tilesize, int) and dock_tilesize != 48:
        subscores["dock_tilesize"] = 10
        c4_other = True
        feedback.append(f"Dock icon size {dock_tilesize} — changed but not small enough (partial +10)")
    else:
        c4_other = True
        feedback.append(f"Dock tilesize unexpected: {dock_tilesize!r} (+0)")

    # ---- C5: 24-hour clock (20 pts) ----
    # `clock_is_24h` is True iff either DateFormat contains "HH" with no
    # AM/PM marker OR ShowAMPM is explicitly false (UI-toggle path). See
    # export_result.sh for the derivation.
    clock_show_ampm = data.get("clock_show_ampm")
    c5_full = c5_baseline = c5_other = False
    if clock_is_24h:
        subscores["clock_24h"] = 20
        c5_full = True
        feedback.append("Menu bar clock in 24-hour format (+20)")
    elif (
        (clock_dateformat is None or clock_dateformat == BASELINE["clock_date_format"])
        and (clock_show_ampm in (None, True))
    ):
        c5_baseline = True
        feedback.append("Menu bar clock still 12-hour (+0)")
    else:
        c5_other = True
        feedback.append(
            f"Clock format changed but not to 24-hour: "
            f"DateFormat={clock_dateformat!r}, ShowAMPM={clock_show_ampm!r} (+0)"
        )

    full_flags     = [c1_full, c2_full, c3_full, c4_full, c5_full]
    baseline_flags = [c1_baseline, c2_baseline, c3_baseline, c4_baseline, c5_baseline]
    other_flags    = [c1_other, c2_other, c3_other, c4_other, c5_other]

    # ---- Gate 1: do-nothing → score 0 ----
    # If every criterion is at baseline (no change attempted), return 0
    # explicitly with a clear message rather than letting it fall through
    # to "0 score, no progress".
    if all(baseline_flags):
        return {"score": 0, "passed": False,
                "feedback": ("No settings changed from baseline. None of Dark mode, Dock position, "
                             "Dock auto-hide, Dock icon size, or 24-hour clock were touched."),
                "subscores": _empty_subscores()}

    # ---- Gate 2: strict wrong-target rejection (Pattern #2) ----
    # If the agent changed something but landed only on non-target values
    # AND nothing scored full credit, treat as wrong-target → 0.
    if any(other_flags) and not any(full_flags):
        return {"score": 0, "passed": False,
                "feedback": ("Wrong target: some settings were changed but none reached the task's "
                             "target values. " + " | ".join(feedback)),
                "subscores": _empty_subscores()}

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD

    if passed:
        feedback.insert(0, f"PASSED ({total}/100): presentation-mode configuration applied.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
