#!/usr/bin/env python3
"""Verifier for configure_scautopick_thresholds_scconfig task.

A network operator must configure scautopick detection thresholds in scconfig to
reduce false detections from cultural noise in the 1-4 Hz band.

Required changes to $SEISCOMP_ROOT/etc/scautopick.cfg:
  filter = BW(4,4,20)            → 4th-order Butterworth bandpass 4-20 Hz
  thresholds.trigOn = 3.5        → STA/LTA trigger-on threshold
  thresholds.trigOff = 1.5       → STA/LTA trigger-off threshold
  picker.AIC.minSNR = 2.0        → AIC picker minimum SNR

Scoring:
  25 pts: filter contains "BW(4,4,20)"
  25 pts: thresholds.trigOn = 3.5
  25 pts: thresholds.trigOff = 1.5
  25 pts: picker.AIC.minSNR = 2.0

Wrong-target guard: config file must exist and be newer than task start.
"""

import json
import os
import tempfile


def _approx_equal(val_str, target_float, tolerance=0.05):
    """Return True if val_str parses to a float within tolerance of target_float."""
    try:
        return abs(float(val_str) - target_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_configure_scautopick_thresholds_scconfig(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "configure_scautopick_thresholds_scconfig"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(result_path, tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {e}",
        }

    config_exists = result.get("config_exists", False)
    if isinstance(config_exists, str):
        config_exists = config_exists.lower() == "true"
    config_is_new = result.get("config_is_new", False)
    if isinstance(config_is_new, str):
        config_is_new = config_is_new.lower() == "true"

    # ── Wrong-target guard ────────────────────────────────────────────────────
    # If the config was not written (or existed before task start), fail early.
    if not config_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "scautopick.cfg does not exist. "
                "The agent must open scconfig, navigate to Module Parameters > scautopick, "
                "set the required parameters, and save/update the configuration."
            ),
        }
    if not config_is_new:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "scautopick.cfg exists but was NOT modified during the task session. "
                "Changes must be saved via scconfig's Save/Update button."
            ),
        }

    score = 0
    parts = []

    filter_val = result.get("filter", "")
    trig_on_val = result.get("thresholds_trigOn", "")
    trig_off_val = result.get("thresholds_trigOff", "")
    min_snr_val = result.get("picker_AIC_minSNR", "")

    # ── Criterion 1 (25 pts): filter = BW(4,4,20) ────────────────────────────
    # Accept any reasonable representation of a 4-20 Hz Butterworth filter
    filter_ok = (
        "BW(4,4,20)" in filter_val
        or "BW(4, 4, 20)" in filter_val
        or "BW(4,4.0,20)" in filter_val
        or "BW(4,4.0,20.0)" in filter_val
    )
    if filter_ok:
        score += 25
        parts.append(f"Filter correctly set to '{filter_val}' (25/25)")
    else:
        parts.append(
            f"Filter '{filter_val}' does not match required 'BW(4,4,20)' (0/25)"
        )

    # ── Criterion 2 (25 pts): thresholds.trigOn = 3.5 ────────────────────────
    if _approx_equal(trig_on_val, 3.5):
        score += 25
        parts.append(f"thresholds.trigOn = {trig_on_val} ≈ 3.5 (25/25)")
    else:
        parts.append(
            f"thresholds.trigOn = '{trig_on_val}' — expected 3.5 (0/25)"
        )

    # ── Criterion 3 (25 pts): thresholds.trigOff = 1.5 ───────────────────────
    if _approx_equal(trig_off_val, 1.5):
        score += 25
        parts.append(f"thresholds.trigOff = {trig_off_val} ≈ 1.5 (25/25)")
    else:
        parts.append(
            f"thresholds.trigOff = '{trig_off_val}' — expected 1.5 (0/25)"
        )

    # ── Criterion 4 (25 pts): picker.AIC.minSNR = 2.0 ───────────────────────
    if _approx_equal(min_snr_val, 2.0):
        score += 25
        parts.append(f"picker.AIC.minSNR = {min_snr_val} ≈ 2.0 (25/25)")
    else:
        parts.append(
            f"picker.AIC.minSNR = '{min_snr_val}' — expected 2.0 (0/25)"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
