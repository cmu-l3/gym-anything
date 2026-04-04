#!/usr/bin/env python3
"""
Verifier for alpha_neurofeedback_workspace task.

A neurofeedback therapist must configure a complete alpha neurofeedback
workspace in OpenBCI GUI: start a Synthetic session, configure a 4-panel
layout with Time Series / FFT Plot / Band Power / Focus widgets, set bandpass
to 1-40 Hz, enable Expert Mode, take a screenshot, and save settings.

Scoring (100 points total):
- Settings file saved after task start:           25 pts
- Required widgets present in settings:           25 pts
  (Time Series + FFT Plot + Band Power + Focus each worth ~6 pts)
- Bandpass low cutoff ~1 Hz:                      15 pts
- Bandpass high cutoff ~40 Hz:                    10 pts
- New screenshot file captured:                   25 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "alpha_neurofeedback_workspace"
RESULT_PATH = f"/tmp/{TASK_NAME}_result.json"

# Required widgets for this workspace
REQUIRED_WIDGETS = ["Time Series", "FFT Plot", "Band Power", "Focus"]


def verify_alpha_neurofeedback_workspace(traj, env_info, task_info):
    """Verify the alpha neurofeedback workspace was correctly configured."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result JSON from VM
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
    task_start = result.get("task_start", 0)

    # ── Criterion 1: Settings file saved after task start (25 pts) ──────────
    settings_newer = analysis.get("settings_newer_than_task", False)
    settings_found = analysis.get("settings_file_found", False)

    if settings_newer and settings_found:
        score += 25
        subscores["settings_saved"] = True
        feedback_parts.append("Settings file saved after task start (25/25)")
    elif settings_found and not settings_newer:
        feedback_parts.append(
            "Settings file exists but was NOT modified after task start — "
            "agent may not have saved settings (0/25)"
        )
        subscores["settings_saved"] = False
    else:
        feedback_parts.append("No settings file found in Settings/ directory (0/25)")
        subscores["settings_saved"] = False

    # ── Criterion 2: Required widgets present (25 pts, ~6 pts each) ─────────
    widgets_found = analysis.get("widgets_found", [])
    widgets_found_lower = [w.lower() for w in widgets_found]

    widget_points = 0
    widget_hits = []
    widget_misses = []

    for required in REQUIRED_WIDGETS:
        if required.lower() in widgets_found_lower:
            widget_points += 6
            widget_hits.append(required)
        else:
            widget_misses.append(required)

    # Round up to 25 if all 4 found
    if len(widget_hits) == 4:
        widget_points = 25

    score += widget_points
    subscores["widgets_configured"] = widget_points
    if widget_hits:
        feedback_parts.append(
            f"Widgets found: {', '.join(widget_hits)} ({widget_points}/25)"
        )
    if widget_misses:
        feedback_parts.append(f"Missing widgets: {', '.join(widget_misses)}")

    # ── Criterion 3: Bandpass low cutoff ≈ 1 Hz (15 pts) ───────────────────
    bandpass_low = analysis.get("bandpass_low_hz")
    if bandpass_low is not None:
        if 0.5 <= float(bandpass_low) <= 2.0:
            score += 15
            subscores["bandpass_low"] = True
            feedback_parts.append(
                f"Bandpass low cutoff = {bandpass_low} Hz ✓ (target: 1 Hz) (15/15)"
            )
        else:
            subscores["bandpass_low"] = False
            feedback_parts.append(
                f"Bandpass low cutoff = {bandpass_low} Hz ✗ (expected ~1 Hz) (0/15)"
            )
    else:
        subscores["bandpass_low"] = False
        feedback_parts.append(
            "Bandpass low cutoff not found in settings (0/15) — "
            "settings may use different key names"
        )

    # ── Criterion 4: Bandpass high cutoff ≈ 40 Hz (10 pts) ─────────────────
    bandpass_high = analysis.get("bandpass_high_hz")
    if bandpass_high is not None:
        if 35.0 <= float(bandpass_high) <= 45.0:
            score += 10
            subscores["bandpass_high"] = True
            feedback_parts.append(
                f"Bandpass high cutoff = {bandpass_high} Hz ✓ (target: 40 Hz) (10/10)"
            )
        else:
            subscores["bandpass_high"] = False
            feedback_parts.append(
                f"Bandpass high cutoff = {bandpass_high} Hz ✗ (expected ~40 Hz) (0/10)"
            )
    else:
        subscores["bandpass_high"] = False
        feedback_parts.append(
            "Bandpass high cutoff not found in settings (0/10)"
        )

    # ── Criterion 5: New screenshot captured (25 pts) ───────────────────────
    new_screenshots = result.get("new_screenshots", 0)
    if new_screenshots >= 1:
        score += 25
        subscores["screenshot_taken"] = True
        feedback_parts.append(
            f"{new_screenshots} new screenshot(s) in Screenshots/ (25/25) — "
            "Expert Mode was active"
        )
    else:
        subscores["screenshot_taken"] = False
        feedback_parts.append(
            "No new screenshots in ~/Documents/OpenBCI_GUI/Screenshots/ (0/25) — "
            "Expert Mode may not have been enabled, or 'm' key was not pressed"
        )

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "widgets_found": widgets_found,
            "bandpass_low_hz": bandpass_low,
            "bandpass_high_hz": bandpass_high,
            "new_screenshots": new_screenshots,
            "settings_newer_than_task": settings_newer,
            "parse_error": analysis.get("parse_error"),
        },
    }
