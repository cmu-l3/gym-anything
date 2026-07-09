"""Verifier for home_office_productivity on system_settings_env.

Scoring (100 points, pass at 60):
- 20 pts  C1 Auto appearance switch     NSGlobalDomain.AppleInterfaceStyleSwitchesAutomatically == 1
- 20 pts  C2 Always show scroll bars    NSGlobalDomain.AppleShowScrollBars == "Always"
- 20 pts  C3 UI sounds off              NSGlobalDomain.com.apple.sound.beep.feedback == 0
- 20 pts  C4 No recent apps in Dock     com.apple.dock.show-recents == false
- 20 pts  C5 Scale minimize effect      com.apple.dock.mineffect == "scale"

Partial-credit upper bound (Anti-Pattern #4): each criterion is binary → max partial = 0.
Pass threshold 60 > 0.

Reads /tmp/home_office_productivity_result.json produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/home_office_productivity_result.json"

BASELINE = {
    "auto_appearance": False,       # AppleInterfaceStyleSwitchesAutomatically absent = off
    "scrollbars": "Automatic",
    "ui_sound_feedback": 1,
    "dock_show_recents": True,
    "dock_mineffect": "genie",
}


def _empty_subscores() -> Dict[str, int]:
    return {
        "auto_appearance": 0,
        "scrollbars": 0,
        "ui_sound_feedback": 0,
        "dock_show_recents": 0,
        "dock_mineffect": 0,
    }


def verify_home_office_productivity(
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

    auto_appearance   = bool(data.get("auto_appearance", False))
    scrollbars        = data.get("scrollbars")
    ui_sound_feedback = data.get("ui_sound_feedback")
    dock_show_recents = bool(data.get("dock_show_recents", True))
    dock_mineffect    = data.get("dock_mineffect")

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: Auto appearance (20 pts) ----
    # AppleInterfaceStyleSwitchesAutomatically=1 → Day/Night auto-switch
    c1_full = c1_baseline = False
    if auto_appearance:
        subscores["auto_appearance"] = 20
        c1_full = True
        feedback.append("Auto appearance (Light/Dark by time) on (+20)")
    else:
        c1_baseline = True
        feedback.append("Auto appearance still off (+0)")

    # ---- C2: Always show scroll bars (20 pts) ----
    c2_full = c2_baseline = c2_other = False
    if scrollbars == "Always":
        subscores["scrollbars"] = 20
        c2_full = True
        feedback.append("Scroll bars: Always (+20)")
    elif scrollbars == "Automatic" or scrollbars is None:
        c2_baseline = True
        feedback.append("Scroll bars still Automatic (+0)")
    else:
        c2_other = True
        feedback.append(f"Scroll bars: {scrollbars!r} — not Always (+0)")

    # ---- C3: UI sounds off (20 pts) ----
    # beep.feedback == 0 means sound effects/UI feedback sounds are off
    c3_full = c3_baseline = c3_other = False
    if ui_sound_feedback == 0:
        subscores["ui_sound_feedback"] = 20
        c3_full = True
        feedback.append("UI sound feedback off (+20)")
    elif ui_sound_feedback == 1 or ui_sound_feedback is None:
        c3_baseline = True
        feedback.append("UI sound feedback still on (+0)")
    else:
        c3_other = True
        feedback.append(f"UI sound feedback: {ui_sound_feedback!r} (+0)")

    # ---- C4: No recent apps in Dock (20 pts) ----
    c4_full = c4_baseline = False
    if not dock_show_recents:
        subscores["dock_show_recents"] = 20
        c4_full = True
        feedback.append("Dock recent apps section removed (+20)")
    else:
        c4_baseline = True
        feedback.append("Dock still showing recent apps (+0)")

    # ---- C5: Scale minimize effect (20 pts) ----
    c5_full = c5_baseline = c5_other = False
    if dock_mineffect == "scale":
        subscores["dock_mineffect"] = 20
        c5_full = True
        feedback.append("Minimize effect: Scale (+20)")
    elif dock_mineffect == "genie" or dock_mineffect is None:
        c5_baseline = True
        feedback.append("Minimize effect still Genie (+0)")
    else:
        c5_other = True
        feedback.append(f"Minimize effect: {dock_mineffect!r} — not Scale (+0)")

    full_flags     = [c1_full, c2_full, c3_full, c4_full, c5_full]
    baseline_flags = [c1_baseline, c2_baseline, c3_baseline, c4_baseline, c5_baseline]
    other_flags    = [c2_other, c3_other, c5_other]

    if all(baseline_flags):
        return {"score": 0, "passed": False,
                "feedback": ("No settings changed from baseline. "
                             "Auto appearance, scroll bars, UI sounds, Dock recents, and minimize effect all unchanged."),
                "subscores": _empty_subscores()}

    if any(other_flags) and not any(full_flags):
        return {"score": 0, "passed": False,
                "feedback": ("Wrong target: settings changed but none reached the task's target values. "
                             + " | ".join(feedback)),
                "subscores": _empty_subscores()}

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD

    if passed:
        feedback.insert(0, f"PASSED ({total}/100): home office productivity profile applied.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
