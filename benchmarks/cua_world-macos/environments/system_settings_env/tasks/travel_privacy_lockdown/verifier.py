"""Verifier for travel_privacy_lockdown on system_settings_env.

Scoring (100 points, pass at 60):
- 20 pts  C1 Dark Mode on              NSGlobalDomain.AppleInterfaceStyle == "Dark"
- 20 pts  C2 Short screensaver idle    com.apple.screensaver.idleTime <= 120 seconds
                                        (partial: 10 if > 120 but <= 300 — changed but not tight)
- 20 pts  C3 Password on wake          com.apple.screensaver.askForPassword == 1
- 20 pts  C4 Immediate password        com.apple.screensaver.askForPasswordDelay == 0
- 20 pts  C5 Top-left → Lock Screen    com.apple.dock.wvous-tl-corner == 13

Partial-credit upper bound (Anti-Pattern #4): 0+10+0+0+0 = 10. Pass threshold 60 > 10.

Reads /tmp/travel_privacy_lockdown_result.json produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/travel_privacy_lockdown_result.json"

BASELINE = {
    "appearance": None,          # Light (absent key)
    "screensaver_idle_time": 300,
    "screensaver_ask_password": 0,
    "screensaver_password_delay": 5,
    "hot_corner_top_left": 0,
}


def _empty_subscores() -> Dict[str, int]:
    return {
        "dark_mode": 0,
        "screensaver_idle_time": 0,
        "screensaver_ask_password": 0,
        "screensaver_password_delay": 0,
        "hot_corner_top_left": 0,
    }


def verify_travel_privacy_lockdown(
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

    appearance        = data.get("appearance")
    ss_idle           = data.get("screensaver_idle_time")
    ss_password       = data.get("screensaver_ask_password")
    ss_delay          = data.get("screensaver_password_delay")
    tl_corner         = data.get("hot_corner_top_left")

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: Dark mode (20 pts) ----
    c1_full = c1_baseline = c1_other = False
    if appearance == "Dark":
        subscores["dark_mode"] = 20
        c1_full = True
        feedback.append("Dark mode on (+20)")
    elif appearance is None:
        c1_baseline = True
        feedback.append("Appearance still Light (+0)")
    else:
        c1_other = True
        feedback.append(f"Appearance set to {appearance!r} — not Dark (+0)")

    # ---- C2: Short screensaver idle ≤ 120 s (20 full, 10 partial) ----
    c2_full = c2_baseline = c2_other = False
    if isinstance(ss_idle, int) and ss_idle <= 120:
        subscores["screensaver_idle_time"] = 20
        c2_full = True
        feedback.append(f"Screensaver idle time {ss_idle}s ≤ 120 (+20)")
    elif isinstance(ss_idle, int) and ss_idle <= 300 and ss_idle != BASELINE["screensaver_idle_time"]:
        subscores["screensaver_idle_time"] = 10
        c2_other = True
        feedback.append(f"Screensaver idle time {ss_idle}s — shorter but > 120 (partial +10)")
    elif ss_idle is None or ss_idle == BASELINE["screensaver_idle_time"]:
        c2_baseline = True
        feedback.append(f"Screensaver idle time still at baseline {BASELINE['screensaver_idle_time']}s (+0)")
    else:
        c2_other = True
        feedback.append(f"Screensaver idle time: {ss_idle!r} — not ≤ 120 (+0)")

    # ---- C3: Require password on wake (20 pts) ----
    c3_full = c3_baseline = c3_other = False
    if ss_password == 1:
        subscores["screensaver_ask_password"] = 20
        c3_full = True
        feedback.append("Require password after screensaver: on (+20)")
    elif ss_password == 0 or ss_password is None:
        c3_baseline = True
        feedback.append("Password on wake still off (+0)")
    else:
        c3_other = True
        feedback.append(f"askForPassword unexpected: {ss_password!r} (+0)")

    # ---- C4: Immediate password (delay == 0) (20 pts) ----
    c4_full = c4_baseline = c4_other = False
    if ss_delay == 0:
        subscores["screensaver_password_delay"] = 20
        c4_full = True
        feedback.append("Password grace period: 0 seconds (immediate) (+20)")
    elif ss_delay == BASELINE["screensaver_password_delay"] or ss_delay is None:
        c4_baseline = True
        feedback.append(f"Password grace period still at baseline {BASELINE['screensaver_password_delay']}s (+0)")
    else:
        c4_other = True
        feedback.append(f"Password delay: {ss_delay}s — not 0 (+0)")

    # ---- C5: Top-left hot corner → Lock Screen (20 pts) ----
    # 13 = Lock Screen
    c5_full = c5_baseline = c5_other = False
    if tl_corner == 13:
        subscores["hot_corner_top_left"] = 20
        c5_full = True
        feedback.append("Top-left hot corner → Lock Screen (+20)")
    elif tl_corner is None or tl_corner == 0:
        c5_baseline = True
        feedback.append("Top-left hot corner still disabled (+0)")
    else:
        c5_other = True
        feedback.append(f"Top-left hot corner: {tl_corner} — not Lock Screen (+0)")

    full_flags     = [c1_full, c2_full, c3_full, c4_full, c5_full]
    baseline_flags = [c1_baseline, c2_baseline, c3_baseline, c4_baseline, c5_baseline]
    other_flags    = [c1_other, c2_other, c3_other, c4_other, c5_other]

    if all(baseline_flags):
        return {"score": 0, "passed": False,
                "feedback": ("No settings changed from baseline. "
                             "Dark mode, screensaver idle time, password lock, and top-left corner all unchanged."),
                "subscores": _empty_subscores()}

    if any(other_flags) and not any(full_flags):
        return {"score": 0, "passed": False,
                "feedback": ("Wrong target: settings changed but none reached the task's target values. "
                             + " | ".join(feedback)),
                "subscores": _empty_subscores()}

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD

    if passed:
        feedback.insert(0, f"PASSED ({total}/100): travel privacy/lock-down profile applied.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
