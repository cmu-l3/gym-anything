#!/usr/bin/env python3
"""
Verifier for hilal_crescent_assessment task.

Scoring (100 points total):
- Location latitude correct (~21.42° N): 10 pts
- Location longitude correct (~39.83° E): 10 pts
- Date/time approximately correct (JD ~2460025.156): 15 pts
- Atmosphere enabled: 10 pts
- Ground/landscape disabled: 10 pts
- Azimuthal grid enabled: 10 pts
- Screenshots taken (3+): 15 pts
- Report file exists with target/context content: 20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Ground truth for Mecca
MECCA_LAT_RAD = 0.37389    # ~21.4225 deg N
MECCA_LON_RAD = 0.69509    # ~39.8262 deg E
LAT_LON_TOLERANCE_RAD = 0.03  # generous enough for manual input matching

# Ground truth for Date (March 22, 2023 15:45 UTC)
TARGET_JD = 2460025.156
JD_TOLERANCE = 0.5         # within ~12 hours is acceptable for credit

def verify_hilal_crescent_assessment(traj, env_info, task_info):
    """
    Verify hilal visibility assessment task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "hilal_crescent_assessment"

    try:
        # Copy result JSON from container
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
        subscores = {}

        # ── Criterion 1 & 2: Location Latitude and Longitude (10 pts + 10 pts) ──
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - MECCA_LAT_RAD)
            lon_diff = abs(lon_rad - MECCA_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD:
                score += 10
                subscores["latitude"] = True
                feedback_parts.append(f"Latitude correct ({math.degrees(lat_rad):.2f}°)")
            else:
                subscores["latitude"] = False
                feedback_parts.append(f"Latitude incorrect: {math.degrees(lat_rad):.2f}° (expected ~21.42°)")

            if lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 10
                subscores["longitude"] = True
                feedback_parts.append(f"Longitude correct ({math.degrees(lon_rad):.2f}°)")
            else:
                subscores["longitude"] = False
                feedback_parts.append(f"Longitude incorrect: {math.degrees(lon_rad):.2f}° (expected ~39.83°)")
        else:
            subscores["latitude"] = False
            subscores["longitude"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 3: Date/Time (15 pts) ──
        preset_time = result.get('preset_sky_time')
        if preset_time is not None:
            jd_diff = abs(preset_time - TARGET_JD)
            if jd_diff <= JD_TOLERANCE:
                score += 15
                subscores["time"] = True
                feedback_parts.append(f"Date/time correct (JD {preset_time:.2f})")
            else:
                subscores["time"] = False
                feedback_parts.append(f"Date/time incorrect: JD {preset_time:.2f} (expected ~{TARGET_JD:.2f})")
        else:
            subscores["time"] = False
            feedback_parts.append("Date/time not found in config")

        # ── Criterion 4: Atmosphere enabled (10 pts) ──
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is True:
            score += 10
            subscores["atmosphere"] = True
            feedback_parts.append("Atmosphere enabled")
        else:
            subscores["atmosphere"] = False
            feedback_parts.append("Atmosphere disabled (should be ON)")

        # ── Criterion 5: Ground/landscape disabled (10 pts) ──
        flag_land = result.get('flag_landscape')
        if flag_land is False:
            score += 10
            subscores["landscape"] = True
            feedback_parts.append("Landscape disabled")
        else:
            subscores["landscape"] = False
            feedback_parts.append("Landscape enabled (should be OFF)")

        # ── Criterion 6: Azimuthal grid enabled (10 pts) ──
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            score += 10
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append("Azimuthal grid disabled (should be ON)")

        # ── Criterion 7: Screenshots taken (15 pts) ──
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 15
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} screenshots captured")
        elif new_ss >= 1:
            score += 5  # Partial credit
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshot(s) captured (required: 3)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No new screenshots taken")

        # ── Criterion 8: Report file with context (20 pts) ──
        report_exists = result.get('report_exists', False)
        report_has_target = result.get('report_has_target', False)
        report_has_context = result.get('report_has_context', False)

        if report_exists:
            if report_has_target and report_has_context:
                score += 20
                subscores["report"] = True
                feedback_parts.append("Hilal report created with correct keywords")
            elif report_has_target or report_has_context:
                score += 10  # Partial credit
                subscores["report"] = False
                feedback_parts.append("Hilal report created but missing some required keywords")
            else:
                score += 5  # File exists but poor content
                subscores["report"] = False
                feedback_parts.append("Hilal report created but missing required contextual keywords")
        else:
            subscores["report"] = False
            feedback_parts.append("Hilal report not created")

        # Evaluate pass/fail
        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {str(e)}"
        }