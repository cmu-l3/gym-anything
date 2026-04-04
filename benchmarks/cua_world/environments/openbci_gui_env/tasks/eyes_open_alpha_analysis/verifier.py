#!/usr/bin/env python3
"""
Verifier for eyes_open_alpha_analysis task.

A cognitive neuroscientist must load the Eyes Open EEG recording in Playback
mode and configure OpenBCI GUI for alpha analysis: add Band Power and FFT Plot
widgets, set bandpass to 1-50 Hz, set Time Series scale to 100 µV, enable
Expert Mode, take a screenshot, and save settings.

Scoring (100 points total):
- Settings file saved after task start:       20 pts
- Band Power widget in settings:              20 pts
- FFT Plot widget in settings:                20 pts
- Bandpass filter 1–50 Hz:                   20 pts
  (10 pts for low ≈ 1 Hz + 10 pts for high ≈ 50 Hz)
- New screenshot captured:                   20 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "eyes_open_alpha_analysis"
RESULT_PATH = f"/tmp/{TASK_NAME}_result.json"


def verify_eyes_open_alpha_analysis(traj, env_info, task_info):
    """Verify the eyes-open alpha analysis environment was correctly configured."""
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
            "Settings file found but not modified after task start (0/20)"
        )
        subscores["settings_saved"] = False
    else:
        feedback_parts.append("No settings file found (0/20)")
        subscores["settings_saved"] = False

    # ── Criterion 2: Band Power widget present (20 pts) ─────────────────────
    widgets_found = analysis.get("widgets_found", [])
    widgets_found_lower = [w.lower() for w in widgets_found]

    has_band_power = any("band power" in w for w in widgets_found_lower)
    if has_band_power:
        score += 20
        subscores["band_power_widget"] = True
        feedback_parts.append("Band Power widget present in settings (20/20)")
    else:
        subscores["band_power_widget"] = False
        feedback_parts.append(
            f"Band Power widget not found in settings (0/20). "
            f"Widgets seen: {widgets_found if widgets_found else 'none'}"
        )

    # ── Criterion 3: FFT Plot widget present (20 pts) ───────────────────────
    has_fft = any("fft" in w for w in widgets_found_lower)
    if has_fft:
        score += 20
        subscores["fft_widget"] = True
        feedback_parts.append("FFT Plot widget present in settings (20/20)")
    else:
        subscores["fft_widget"] = False
        feedback_parts.append("FFT Plot widget not found in settings (0/20)")

    # ── Criterion 4: Bandpass 1–50 Hz (20 pts: 10 for low, 10 for high) ────
    bandpass_low = analysis.get("bandpass_low_hz")
    bandpass_high = analysis.get("bandpass_high_hz")
    bp_pts = 0

    if bandpass_low is not None:
        if 0.5 <= float(bandpass_low) <= 2.0:
            bp_pts += 10
            feedback_parts.append(f"Bandpass low = {bandpass_low} Hz ✓ (10/10)")
        else:
            feedback_parts.append(f"Bandpass low = {bandpass_low} Hz ✗ (expected ~1 Hz) (0/10)")
    else:
        feedback_parts.append("Bandpass low cutoff not found in settings (0/10)")

    if bandpass_high is not None:
        if 45.0 <= float(bandpass_high) <= 55.0:
            bp_pts += 10
            feedback_parts.append(f"Bandpass high = {bandpass_high} Hz ✓ (10/10)")
        else:
            feedback_parts.append(f"Bandpass high = {bandpass_high} Hz ✗ (expected ~50 Hz) (0/10)")
    else:
        feedback_parts.append("Bandpass high cutoff not found in settings (0/10)")

    score += bp_pts
    subscores["bandpass_filter"] = bp_pts

    # ── Criterion 5: New screenshot captured (20 pts) ───────────────────────
    new_screenshots = result.get("new_screenshots", 0)
    if new_screenshots >= 1:
        score += 20
        subscores["screenshot_taken"] = True
        feedback_parts.append(
            f"{new_screenshots} new screenshot(s) captured (20/20)"
        )
    else:
        subscores["screenshot_taken"] = False
        feedback_parts.append(
            "No new screenshots found (0/20) — "
            "Expert Mode must be enabled and 'm' pressed"
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
            "timeseries_scale_uv": analysis.get("timeseries_scale_uv"),
            "new_screenshots": new_screenshots,
            "settings_newer_than_task": settings_newer,
            "parse_error": analysis.get("parse_error"),
        },
    }
