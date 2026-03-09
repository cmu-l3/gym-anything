#!/usr/bin/env python3
"""
Verifier for motor_imagery_channel_protocol task.

A BCI researcher must load a Motor Imagery EEG recording in Playback mode,
disable 6 non-motor-cortex channels (keep only C3=ch3 and C4=ch4), set
bandpass to 8-30 Hz (Mu+Beta band), add FFT Plot widget, and save settings.

Scoring (100 points total):
- Settings file saved after task start:           20 pts
- ≥4 channels disabled in settings:               30 pts
  (full 30 pts for 6 inactive; 15 pts for 4-5 inactive)
- Bandpass low cutoff ≈ 8 Hz:                     20 pts
- Bandpass high cutoff ≈ 30 Hz:                   10 pts
- FFT Plot widget present in settings:            20 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TASK_NAME = "motor_imagery_channel_protocol"
RESULT_PATH = f"/tmp/{TASK_NAME}_result.json"


def verify_motor_imagery_channel_protocol(traj, env_info, task_info):
    """Verify motor imagery channel protocol was correctly configured."""
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
            "Settings file exists but was not modified after task start (0/20)"
        )
        subscores["settings_saved"] = False
    else:
        feedback_parts.append("No settings file found in Settings/ directory (0/20)")
        subscores["settings_saved"] = False

    # ── Criterion 2: Channels disabled (30 pts) ─────────────────────────────
    # Motor cortex channels (C3=ch3, C4=ch4) should remain active
    # All others (ch1, ch2, ch5, ch6, ch7, ch8) should be inactive
    inactive_count = analysis.get("channels_inactive_count")
    active_count = analysis.get("channels_active_count")
    chan_states = analysis.get("channel_states", [])

    channel_pts = 0
    channel_detail = ""

    if inactive_count is not None:
        if inactive_count >= 6:
            channel_pts = 30
            channel_detail = f"6+ channels disabled (inactive={inactive_count}) (30/30)"
        elif inactive_count >= 4:
            channel_pts = 15
            channel_detail = (
                f"Partial: {inactive_count} channels disabled (target: 6) (15/30)"
            )
        else:
            channel_detail = (
                f"Insufficient channels disabled: {inactive_count} (need ≥4 for partial, 6 for full) (0/30)"
            )
    else:
        channel_detail = (
            "Channel active/inactive state not parseable from settings — "
            "key format may differ (0/30)"
        )

    score += channel_pts
    subscores["channels_disabled"] = channel_pts
    feedback_parts.append(channel_detail)

    # ── Criterion 3: Bandpass low cutoff ≈ 8 Hz (20 pts) ───────────────────
    bandpass_low = analysis.get("bandpass_low_hz")
    if bandpass_low is not None:
        if 6.0 <= float(bandpass_low) <= 10.0:
            score += 20
            subscores["bandpass_low"] = True
            feedback_parts.append(
                f"Bandpass low = {bandpass_low} Hz ✓ (target: 8 Hz) (20/20)"
            )
        else:
            subscores["bandpass_low"] = False
            feedback_parts.append(
                f"Bandpass low = {bandpass_low} Hz ✗ (expected ~8 Hz) (0/20)"
            )
    else:
        subscores["bandpass_low"] = False
        feedback_parts.append(
            "Bandpass low cutoff not found in settings (0/20)"
        )

    # ── Criterion 4: Bandpass high cutoff ≈ 30 Hz (10 pts) ─────────────────
    bandpass_high = analysis.get("bandpass_high_hz")
    if bandpass_high is not None:
        if 25.0 <= float(bandpass_high) <= 35.0:
            score += 10
            subscores["bandpass_high"] = True
            feedback_parts.append(
                f"Bandpass high = {bandpass_high} Hz ✓ (target: 30 Hz) (10/10)"
            )
        else:
            subscores["bandpass_high"] = False
            feedback_parts.append(
                f"Bandpass high = {bandpass_high} Hz ✗ (expected ~30 Hz) (0/10)"
            )
    else:
        subscores["bandpass_high"] = False
        feedback_parts.append("Bandpass high cutoff not found in settings (0/10)")

    # ── Criterion 5: FFT Plot widget present (20 pts) ───────────────────────
    widgets_found = analysis.get("widgets_found", [])
    has_fft = any("fft" in w.lower() for w in widgets_found)

    if has_fft:
        score += 20
        subscores["fft_widget"] = True
        feedback_parts.append("FFT Plot widget present in settings (20/20)")
    else:
        subscores["fft_widget"] = False
        feedback_parts.append(
            "FFT Plot widget not found in settings (0/20) — "
            f"widgets found: {widgets_found if widgets_found else 'none'}"
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
            "channels_active": active_count,
            "channels_inactive": inactive_count,
            "settings_newer_than_task": settings_newer,
            "parse_error": analysis.get("parse_error"),
        },
    }
