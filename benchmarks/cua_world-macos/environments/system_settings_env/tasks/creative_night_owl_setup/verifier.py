"""Verifier for creative_night_owl_setup on system_settings_env.

Scoring (100 points, pass at 60):
- 20 pts  C1 Reduce Motion on          NSGlobalDomain.AppleReduceMotion == 1
- 25 pts  C2 Fast key repeat           NSGlobalDomain.KeyRepeat <= 2
                                        (partial: 10 if changed from baseline 6 but > 2)
- 25 pts  C3 Short initial delay       NSGlobalDomain.InitialKeyRepeat <= 15
                                        (partial: 10 if changed from baseline 25 but > 15)
- 15 pts  C4 Bottom-left → Desktop     com.apple.dock.wvous-bl-corner == 4
- 15 pts  C5 Top-right → Mission Ctrl  com.apple.dock.wvous-tr-corner == 2

Partial-credit upper bound (Anti-Pattern #4): 0+10+10+0+0 = 20. Pass threshold 60 > 20.

Reads /tmp/creative_night_owl_setup_result.json produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/creative_night_owl_setup_result.json"

BASELINE = {
    "reduce_motion": False,
    "key_repeat": 6,
    "initial_key_repeat": 25,
    "hot_corner_bottom_left": 0,
    "hot_corner_top_right": 0,
}


def _empty_subscores() -> Dict[str, int]:
    return {
        "reduce_motion": 0,
        "key_repeat": 0,
        "initial_key_repeat": 0,
        "hot_corner_bottom_left": 0,
        "hot_corner_top_right": 0,
    }


def verify_creative_night_owl_setup(
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

    reduce_motion      = bool(data.get("reduce_motion", False))
    key_repeat         = data.get("key_repeat")
    initial_key_repeat = data.get("initial_key_repeat")
    bl_corner          = data.get("hot_corner_bottom_left")
    tr_corner          = data.get("hot_corner_top_right")

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: Reduce Motion (20 pts) ----
    c1_full = c1_baseline = c1_other = False
    if reduce_motion:
        subscores["reduce_motion"] = 20
        c1_full = True
        feedback.append("Reduce Motion on (+20)")
    else:
        c1_baseline = True
        feedback.append("Reduce Motion still off (+0)")

    # ---- C2: Key repeat speed (25 full, 10 partial) ----
    # Lower KeyRepeat = faster; baseline=6, target<=2
    c2_full = c2_baseline = c2_other = False
    if isinstance(key_repeat, int) and key_repeat <= 2:
        subscores["key_repeat"] = 25
        c2_full = True
        feedback.append(f"KeyRepeat {key_repeat} ≤ 2 — fastest (+25)")
    elif key_repeat is None or key_repeat == BASELINE["key_repeat"]:
        c2_baseline = True
        feedback.append(f"KeyRepeat still at baseline {BASELINE['key_repeat']} (+0)")
    elif isinstance(key_repeat, int) and key_repeat != BASELINE["key_repeat"]:
        subscores["key_repeat"] = 10
        c2_other = True
        feedback.append(f"KeyRepeat {key_repeat} — faster than default but not maximum (partial +10)")
    else:
        c2_other = True
        feedback.append(f"KeyRepeat unexpected: {key_repeat!r} (+0)")

    # ---- C3: Initial key repeat delay (25 full, 10 partial) ----
    # Lower InitialKeyRepeat = shorter delay; baseline=25, target<=15
    c3_full = c3_baseline = c3_other = False
    if isinstance(initial_key_repeat, int) and initial_key_repeat <= 15:
        subscores["initial_key_repeat"] = 25
        c3_full = True
        feedback.append(f"InitialKeyRepeat {initial_key_repeat} ≤ 15 — shortest (+25)")
    elif initial_key_repeat is None or initial_key_repeat == BASELINE["initial_key_repeat"]:
        c3_baseline = True
        feedback.append(f"InitialKeyRepeat still at baseline {BASELINE['initial_key_repeat']} (+0)")
    elif isinstance(initial_key_repeat, int) and initial_key_repeat != BASELINE["initial_key_repeat"]:
        subscores["initial_key_repeat"] = 10
        c3_other = True
        feedback.append(f"InitialKeyRepeat {initial_key_repeat} — shorter than default but not target (partial +10)")
    else:
        c3_other = True
        feedback.append(f"InitialKeyRepeat unexpected: {initial_key_repeat!r} (+0)")

    # ---- C4: Bottom-left hot corner → Desktop (15 pts) ----
    # 4 = Show Desktop
    c4_full = c4_baseline = c4_other = False
    if bl_corner == 4:
        subscores["hot_corner_bottom_left"] = 15
        c4_full = True
        feedback.append("Bottom-left hot corner → Desktop (+15)")
    elif bl_corner is None or bl_corner == 0:
        c4_baseline = True
        feedback.append("Bottom-left hot corner still disabled (+0)")
    else:
        c4_other = True
        feedback.append(f"Bottom-left hot corner set to {bl_corner} — not Desktop (+0)")

    # ---- C5: Top-right hot corner → Mission Control (15 pts) ----
    # 2 = Mission Control
    c5_full = c5_baseline = c5_other = False
    if tr_corner == 2:
        subscores["hot_corner_top_right"] = 15
        c5_full = True
        feedback.append("Top-right hot corner → Mission Control (+15)")
    elif tr_corner is None or tr_corner == 0:
        c5_baseline = True
        feedback.append("Top-right hot corner still disabled (+0)")
    else:
        c5_other = True
        feedback.append(f"Top-right hot corner set to {tr_corner} — not Mission Control (+0)")

    full_flags     = [c1_full, c2_full, c3_full, c4_full, c5_full]
    baseline_flags = [c1_baseline, c2_baseline, c3_baseline, c4_baseline, c5_baseline]
    other_flags    = [c1_other, c2_other, c3_other, c4_other, c5_other]

    if all(baseline_flags):
        return {"score": 0, "passed": False,
                "feedback": ("No settings changed from baseline. "
                             "Reduce Motion, key repeat, initial delay, and both hot corners untouched."),
                "subscores": _empty_subscores()}

    if any(other_flags) and not any(full_flags):
        return {"score": 0, "passed": False,
                "feedback": ("Wrong target: settings changed but none reached the task's target values. "
                             + " | ".join(feedback)),
                "subscores": _empty_subscores()}

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD

    if passed:
        feedback.insert(0, f"PASSED ({total}/100): creative night-owl profile applied.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
