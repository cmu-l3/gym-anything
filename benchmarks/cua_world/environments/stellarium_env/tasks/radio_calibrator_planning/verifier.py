#!/usr/bin/env python3
"""
Verifier for radio_calibrator_planning task.

Scoring (100 points total):
- Location set to Green Bank Observatory: 20 pts
- Time set correctly to Jan 20 2024: 10 pts
- Atmosphere disabled: 10 pts
- Ground/landscape disabled: 10 pts
- Equatorial grid enabled: 10 pts
- 3+ screenshots taken: 25 pts
- Calibration plan file written with correct targets: 15 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Green Bank Observatory ground truth
GBT_LAT_RAD = 0.67078    # 38.4330 degrees N
GBT_LON_RAD = -1.39345   # -79.8398 degrees W
LAT_LON_TOLERANCE_RAD = 0.05  # ~2.8 degrees tolerance (generous)

# Date/Time ground truth
TARGET_JD = 2460329.708  # 2024-01-20 05:00:00 UTC
JD_TOLERANCE = 0.5       # +/- 12 hours


def verify_radio_calibrator_planning(traj, env_info, task_info):
    """
    Verify radio calibrator observation planning task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "radio_calibrator_planning"

    try:
        # Copy result JSON from VM safely
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        try:
            copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []
        
        if not result.get("config_exists"):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Stellarium config.ini not found. Task failed to set up or export."
            }

        # ── Criterion 1: Observatory location (20 pts) ───────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - GBT_LAT_RAD)
            lon_diff = abs(lon_rad - GBT_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                feedback_parts.append(f"Green Bank location set (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°")
        else:
            feedback_parts.append("Location coordinates missing from config")

        # ── Criterion 2: Date/Time (10 pts) ──────────────────────────────────
        preset_sky_time = result.get('preset_sky_time')
        startup_time_mode = result.get('startup_time_mode', '').lower()

        if preset_sky_time and (startup_time_mode == 'preset' or abs(preset_sky_time - TARGET_JD) <= JD_TOLERANCE):
            time_diff = abs(preset_sky_time - TARGET_JD)
            if time_diff <= JD_TOLERANCE:
                score += 10
                feedback_parts.append(f"Observation time set correctly (JD ≈ {preset_sky_time:.2f})")
            else:
                feedback_parts.append(f"Wrong observation time (JD {preset_sky_time:.2f}, expected {TARGET_JD})")
        else:
            feedback_parts.append("Observation time not explicitly saved in configuration")

        # ── Criterion 3: Atmosphere disabled (10 pts) ────────────────────────
        if result.get('flag_atmosphere') is False:
            score += 10
            feedback_parts.append("Atmosphere disabled")
        else:
            feedback_parts.append("Atmosphere still enabled")

        # ── Criterion 4: Ground/Landscape disabled (10 pts) ──────────────────
        if result.get('flag_landscape') is False:
            score += 10
            feedback_parts.append("Ground/Landscape disabled")
        else:
            feedback_parts.append("Ground/Landscape still enabled")

        # ── Criterion 5: Equatorial grid enabled (10 pts) ────────────────────
        if result.get('flag_equatorial_grid') is True:
            score += 10
            feedback_parts.append("Equatorial grid enabled")
        else:
            feedback_parts.append("Equatorial grid not enabled")

        # ── Criterion 6: Screenshots taken (25 pts) ──────────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 25
            feedback_parts.append(f"{new_ss} target screenshots captured")
        elif new_ss == 2:
            score += 15
            feedback_parts.append("Only 2 screenshots captured (partial)")
        elif new_ss == 1:
            score += 5
            feedback_parts.append("Only 1 screenshot captured (partial)")
        else:
            feedback_parts.append("No screenshots captured")

        # ── Criterion 7: Calibration Plan Document (15 pts) ──────────────────
        if result.get('plan_exists'):
            targets_found = sum([
                result.get('plan_has_m1', False),
                result.get('plan_has_m42', False),
                result.get('plan_has_m87', False)
            ])
            
            if targets_found == 3:
                score += 15
                feedback_parts.append("Calibration plan contains all 3 required targets")
            elif targets_found > 0:
                score += (targets_found * 5)
                feedback_parts.append(f"Calibration plan missing some targets ({targets_found}/3 found)")
            else:
                feedback_parts.append("Calibration plan exists but is missing target names")
        else:
            feedback_parts.append("Calibration plan file not created")

        # Determine pass/fail
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {str(e)}"
        }