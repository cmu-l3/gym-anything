#!/usr/bin/env python3
"""
Verifier for eeg_recording_session task.

A research lab assistant must set up OpenBCI GUI for a complete EEG recording
session: start Synthetic mode, configure 4-panel layout (Time Series, Band Power,
FFT Plot, Accelerometer), set bandpass 1-50 Hz, set notch 60 Hz, enable Expert
Mode, start a recording, take a screenshot while recording, stop the recording,
and save settings.

Scoring (100 points total):
- Settings file saved after task start:                20 pts
- New recording file in Recordings/ (>2 KB):           30 pts
- Bandpass filter 1–50 Hz (10 pts low + 10 pts high):  20 pts
- Notch filter at 60 Hz:                               15 pts
- New screenshot captured:                             15 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "eeg_recording_session"
RESULT_PATH = f"/tmp/{TASK_NAME}_result.json"

MIN_RECORDING_BYTES = 2048  # 2 KB — enough for a real EEG header + some samples


def verify_eeg_recording_session(traj, env_info, task_info):
    """Verify the EEG recording session was correctly set up and executed."""
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
    recording = result.get("recording_analysis", {})

    # ── Criterion 1: Settings file saved after task start (20 pts) ──────────
    settings_newer = analysis.get("settings_newer_than_task", False)
    settings_found = analysis.get("settings_file_found", False)

    if settings_newer and settings_found:
        score += 20
        subscores["settings_saved"] = True
        feedback_parts.append("Settings file saved after task start (20/20)")
    elif settings_found:
        feedback_parts.append(
            "Settings file found but NOT modified after task start (0/20)"
        )
        subscores["settings_saved"] = False
    else:
        feedback_parts.append("No settings file found (0/20)")
        subscores["settings_saved"] = False

    # ── Criterion 2: EEG recording file created and substantial (30 pts) ────
    has_substantial = result.get("has_substantial_recording", False)
    new_recs = recording.get("new_recordings", [])
    new_rec_count = recording.get("new_recording_count", 0)
    largest_bytes = recording.get("largest_recording_bytes", 0)

    if has_substantial:
        score += 30
        subscores["recording_created"] = True
        feedback_parts.append(
            f"EEG recording file created with {largest_bytes:,} bytes > {MIN_RECORDING_BYTES:,} min (30/30)"
        )
    elif new_rec_count > 0:
        # File exists but too small (session may have been aborted immediately)
        score += 10
        subscores["recording_created"] = "partial"
        feedback_parts.append(
            f"Recording file found but too small ({largest_bytes} bytes < {MIN_RECORDING_BYTES} min) — "
            "was the recording started and allowed to capture data? (10/30)"
        )
    else:
        subscores["recording_created"] = False
        feedback_parts.append(
            f"No new recording file found in Recordings/ directory (0/30) — "
            "was the recording started via the GUI's record button?"
        )

    # ── Criterion 3: Bandpass filter 1–50 Hz (20 pts: 10+10) ───────────────
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
            feedback_parts.append(
                f"Bandpass high = {bandpass_high} Hz ✗ (expected ~50 Hz) (0/10)"
            )
    else:
        feedback_parts.append("Bandpass high cutoff not found in settings (0/10)")

    score += bp_pts
    subscores["bandpass_filter"] = bp_pts

    # ── Criterion 4: Notch filter at 60 Hz (15 pts) ─────────────────────────
    notch_hz = analysis.get("notch_hz")
    if notch_hz is not None:
        if 55.0 <= float(notch_hz) <= 65.0:
            score += 15
            subscores["notch_60hz"] = True
            feedback_parts.append(
                f"Notch filter = {notch_hz} Hz ✓ (target: 60 Hz) (15/15)"
            )
        else:
            subscores["notch_60hz"] = False
            feedback_parts.append(
                f"Notch filter = {notch_hz} Hz ✗ (expected 60 Hz) (0/15)"
            )
    else:
        subscores["notch_60hz"] = False
        feedback_parts.append(
            "Notch filter value not found in settings (0/15) — "
            "may not have been configured"
        )

    # ── Criterion 5: New screenshot captured (15 pts) ───────────────────────
    new_screenshots = result.get("new_screenshots", 0)
    if new_screenshots >= 1:
        score += 15
        subscores["screenshot_taken"] = True
        feedback_parts.append(
            f"{new_screenshots} new screenshot(s) captured (15/15)"
        )
    else:
        subscores["screenshot_taken"] = False
        feedback_parts.append(
            "No new screenshots found (0/15) — "
            "Expert Mode must be active and 'm' key pressed"
        )

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "widgets_found": analysis.get("widgets_found", []),
            "bandpass_low_hz": bandpass_low,
            "bandpass_high_hz": bandpass_high,
            "notch_hz": notch_hz,
            "new_screenshots": new_screenshots,
            "new_recording_count": new_rec_count,
            "largest_recording_bytes": largest_bytes,
            "settings_newer_than_task": settings_newer,
            "parse_error": analysis.get("parse_error"),
        },
    }
