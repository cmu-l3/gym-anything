#!/usr/bin/env python3
"""
Verifier for bci_research_dashboard task.

A computational neuroscience researcher must configure a 6-panel BCI dashboard
in OpenBCI GUI with Synthetic mode, 6 distinct widgets (Time Series, FFT Plot,
Band Power, Accelerometer, Focus, Head Plot), notch filter at 60 Hz, Expert
Mode enabled, a screenshot taken, and settings saved.

Scoring (100 points total):
- Settings file saved after task start:                    20 pts
- Distinct widget types in settings (≥5 of 6 required):   25 pts
  (5 pts per required widget found, max 25)
- Notch filter at 60 Hz:                                   20 pts
- Expert Mode enabled in settings:                         15 pts
- New screenshot captured:                                 20 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "bci_research_dashboard"
RESULT_PATH = f"/tmp/{TASK_NAME}_result.json"

REQUIRED_WIDGETS = ["Time Series", "FFT Plot", "Band Power", "Accelerometer", "Focus", "Head Plot"]


def verify_bci_research_dashboard(traj, env_info, task_info):
    """Verify the 6-panel BCI research dashboard was correctly configured."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    analysis = result.get("settings_analysis", {})

    # ── Criterion 1: Settings file saved after task start (20 pts) ──────────
    settings_newer = analysis.get("settings_newer_than_task", False)
    settings_found = analysis.get("settings_file_found", False)

    if settings_newer and settings_found:
        score += 20
        subscores["settings_saved"] = True
        feedback_parts.append("Settings file saved after task start (20/20)")
    elif settings_found:
        feedback_parts.append(
            "Settings file exists but NOT modified after task start (0/20)"
        )
        subscores["settings_saved"] = False
    else:
        feedback_parts.append("No settings file found (0/20)")
        subscores["settings_saved"] = False

    # ── Criterion 2: Widget diversity — ≥5 of 6 required widget types (25 pts) ──
    widgets_found = analysis.get("widgets_found", [])
    widgets_found_lower = [w.lower() for w in widgets_found]

    widget_hits = [w for w in REQUIRED_WIDGETS if w.lower() in widgets_found_lower]
    widget_pts = min(len(widget_hits) * 5, 25)

    score += widget_pts
    subscores["widgets_configured"] = widget_pts

    if len(widget_hits) >= 6:
        feedback_parts.append(
            f"All 6 required widgets present: {', '.join(widget_hits)} (25/25)"
        )
    elif len(widget_hits) >= 5:
        feedback_parts.append(
            f"{len(widget_hits)}/6 required widgets present: {', '.join(widget_hits)} ({widget_pts}/25)"
        )
    elif widget_hits:
        missing = [w for w in REQUIRED_WIDGETS if w.lower() not in widgets_found_lower]
        feedback_parts.append(
            f"Only {len(widget_hits)}/6 widgets found: {', '.join(widget_hits)} | "
            f"Missing: {', '.join(missing)} ({widget_pts}/25)"
        )
    else:
        feedback_parts.append(
            f"No required widgets found in settings (0/25). "
            f"Widgets seen: {widgets_found if widgets_found else 'none'}"
        )

    # ── Criterion 3: Notch filter at 60 Hz (20 pts) ─────────────────────────
    notch_hz = analysis.get("notch_hz")
    if notch_hz is not None:
        if 55.0 <= float(notch_hz) <= 65.0:
            score += 20
            subscores["notch_60hz"] = True
            feedback_parts.append(
                f"Notch filter = {notch_hz} Hz ✓ (target: 60 Hz) (20/20)"
            )
        else:
            subscores["notch_60hz"] = False
            feedback_parts.append(
                f"Notch filter = {notch_hz} Hz ✗ (expected 60 Hz) (0/20)"
            )
    else:
        subscores["notch_60hz"] = False
        feedback_parts.append("Notch filter value not found in settings (0/20)")

    # ── Criterion 4: Expert Mode enabled (15 pts) ───────────────────────────
    expert_mode = analysis.get("expert_mode_enabled", False)
    if expert_mode:
        score += 15
        subscores["expert_mode"] = True
        feedback_parts.append("Expert Mode enabled in settings (15/15)")
    else:
        subscores["expert_mode"] = False
        feedback_parts.append(
            "Expert Mode not detected in settings (0/15) — "
            "may not have been enabled, or key format differs"
        )

    # ── Criterion 5: New screenshot captured (20 pts) ───────────────────────
    new_screenshots = result.get("new_screenshots", 0)
    if new_screenshots >= 1:
        score += 20
        subscores["screenshot_taken"] = True
        feedback_parts.append(
            f"{new_screenshots} new screenshot(s) captured (20/20) — Expert Mode confirmed active"
        )
    else:
        subscores["screenshot_taken"] = False
        feedback_parts.append(
            "No new screenshots in ~/Documents/OpenBCI_GUI/Screenshots/ (0/20) — "
            "Expert Mode must be enabled, then press 'm'"
        )

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "widgets_found": widgets_found,
            "notch_hz": notch_hz,
            "expert_mode": expert_mode,
            "new_screenshots": new_screenshots,
            "settings_newer_than_task": settings_newer,
            "parse_error": analysis.get("parse_error"),
            "panel_count": analysis.get("panel_count"),
        },
    }
