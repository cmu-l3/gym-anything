"""Verifier for family_accessibility_elderly on system_settings_env.

Scoring (100 points, pass at 60):
- 20 pts  C1 Increase Contrast on       com.apple.universalaccess.increaseContrast == 1
- 20 pts  C2 Reduce Transparency on     com.apple.universalaccess.reduceTransparency == 1
- 20 pts  C3 Large cursor               com.apple.universalaccess.cursorSize >= 3.0
                                        (partial: 10 if cursorSize in [1.5, 3.0))
- 15 pts  C4 Scroll wheel zoom on       com.apple.universalaccess.closeViewScrollWheelToggle == 1
- 15 pts  C5 Sticky keys on             com.apple.universalaccess.stickyKey == 1
- 10 pts  C6 Slow keys on               com.apple.universalaccess.slowKey == 1

Partial-credit upper bound (Anti-Pattern #4): 0+0+10+0+0+0 = 10. Pass threshold 60 > 10.

Reads /tmp/family_accessibility_elderly_result.json produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/family_accessibility_elderly_result.json"

BASELINE = {
    "increase_contrast": False,
    "reduce_transparency": False,
    "cursor_size": 1.0,
    "scroll_wheel_zoom": False,
    "sticky_key": False,
    "slow_key": False,
}


def _empty_subscores() -> Dict[str, int]:
    return {
        "increase_contrast": 0,
        "reduce_transparency": 0,
        "cursor_size": 0,
        "scroll_wheel_zoom": 0,
        "sticky_key": 0,
        "slow_key": 0,
    }


def verify_family_accessibility_elderly(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

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

    increase_contrast   = bool(data.get("increase_contrast", False))
    reduce_transparency = bool(data.get("reduce_transparency", False))
    cursor_size         = data.get("cursor_size")
    scroll_wheel_zoom   = bool(data.get("scroll_wheel_zoom", False))
    sticky_key          = bool(data.get("sticky_key", False))
    slow_key            = bool(data.get("slow_key", False))

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: Increase Contrast (20 pts) ----
    c1_full = c1_baseline = c1_other = False
    if increase_contrast:
        subscores["increase_contrast"] = 20
        c1_full = True
        feedback.append("Increase Contrast on (+20)")
    else:
        c1_baseline = True
        feedback.append("Increase Contrast still off (+0)")

    # ---- C2: Reduce Transparency (20 pts) ----
    c2_full = c2_baseline = c2_other = False
    if reduce_transparency:
        subscores["reduce_transparency"] = 20
        c2_full = True
        feedback.append("Reduce Transparency on (+20)")
    else:
        c2_baseline = True
        feedback.append("Reduce Transparency still off (+0)")

    # ---- C3: Large cursor (20 full, 10 partial) ----
    c3_full = c3_baseline = c3_other = False
    if isinstance(cursor_size, (int, float)) and cursor_size >= 3.0:
        subscores["cursor_size"] = 20
        c3_full = True
        feedback.append(f"Cursor size {cursor_size} ≥ 3.0 (+20)")
    elif isinstance(cursor_size, (int, float)) and cursor_size >= 1.5:
        subscores["cursor_size"] = 10
        c3_other = True
        feedback.append(f"Cursor size {cursor_size} — enlarged but < 3.0 (partial +10)")
    elif cursor_size is None or (isinstance(cursor_size, (int, float)) and cursor_size <= 1.0):
        c3_baseline = True
        feedback.append("Cursor size at baseline 1.0 (+0)")
    else:
        c3_other = True
        feedback.append(f"Cursor size unexpected: {cursor_size!r} (+0)")

    # ---- C4: Scroll wheel zoom (15 pts) ----
    c4_full = c4_baseline = c4_other = False
    if scroll_wheel_zoom:
        subscores["scroll_wheel_zoom"] = 15
        c4_full = True
        feedback.append("Scroll wheel zoom on (+15)")
    else:
        c4_baseline = True
        feedback.append("Scroll wheel zoom still off (+0)")

    # ---- C5: Sticky keys (15 pts) ----
    c5_full = c5_baseline = c5_other = False
    if sticky_key:
        subscores["sticky_key"] = 15
        c5_full = True
        feedback.append("Sticky keys on (+15)")
    else:
        c5_baseline = True
        feedback.append("Sticky keys still off (+0)")

    # ---- C6: Slow keys (10 pts) ----
    c6_full = c6_baseline = c6_other = False
    if slow_key:
        subscores["slow_key"] = 10
        c6_full = True
        feedback.append("Slow keys on (+10)")
    else:
        c6_baseline = True
        feedback.append("Slow keys still off (+0)")

    full_flags     = [c1_full, c2_full, c3_full, c4_full, c5_full, c6_full]
    baseline_flags = [c1_baseline, c2_baseline, c3_baseline, c4_baseline, c5_baseline, c6_baseline]
    other_flags    = [c1_other, c2_other, c3_other, c4_other, c5_other, c6_other]

    if all(baseline_flags):
        return {"score": 0, "passed": False,
                "feedback": ("No accessibility settings changed from baseline. "
                             "None of contrast, transparency, cursor size, scroll zoom, sticky keys, "
                             "or slow keys were modified."),
                "subscores": _empty_subscores()}

    if any(other_flags) and not any(full_flags):
        return {"score": 0, "passed": False,
                "feedback": ("Wrong target: settings changed but none reached the task's target values. "
                             + " | ".join(feedback)),
                "subscores": _empty_subscores()}

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD

    if passed:
        feedback.insert(0, f"PASSED ({total}/100): elderly accessibility profile applied.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
