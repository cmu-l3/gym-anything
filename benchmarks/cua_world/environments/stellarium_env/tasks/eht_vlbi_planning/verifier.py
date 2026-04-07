#!/usr/bin/env python3
"""
Verifier for eht_vlbi_planning task.

Scoring System (100 points total):
| Criterion | Points | Description |
|-----------|--------|-------------|
| Observatory Location | 25 | Latitude and longitude correctly set to ALMA coordinates (within 0.05 rad tolerance). |
| Radio View Setup | 20 | Both atmosphere and landscape toggled OFF in the configuration. |
| Antenna Grid Setup | 15 | Azimuthal coordinate grid toggled ON. |
| Target Screenshot | 20 | At least one new screenshot file exists in the Stellarium pictures directory. |
| Scheduling Report | 20 | The text file exists and contains the required context keywords. |

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# ALMA Observatory coordinates
# Lat: -23.019° -> -0.40175 rad
# Lon: -67.753° -> -1.18252 rad
ALMA_LAT_RAD = -0.40175
ALMA_LON_RAD = -1.18252
LAT_LON_TOLERANCE_RAD = 0.05  # ~2.8 degrees tolerance


def verify_eht_vlbi_planning(traj, env_info, task_info):
    """
    Verify EHT VLBI Planning task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "eht_vlbi_planning"

    try:
        # Copy result JSON from VM
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

        # ── Criterion 1: Observatory location (25 pts) ──────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - ALMA_LAT_RAD)
            lon_diff = abs(lon_rad - ALMA_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 25
                subscores["location"] = True
                feedback_parts.append(
                    f"ALMA location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~-23.02°N, ~-67.75°W for ALMA)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Radio View Setup (20 pts) ───────────────────────────
        # Both atmosphere and landscape must be OFF
        flag_atm = result.get('flag_atmosphere')
        flag_land = result.get('flag_landscape')

        if flag_atm is False and flag_land is False:
            score += 20
            subscores["view_setup"] = True
            feedback_parts.append("Atmosphere and landscape both disabled (Radio View)")
        else:
            subscores["view_setup"] = False
            if flag_atm is not False:
                feedback_parts.append(f"Atmosphere not disabled (flag_atmosphere={flag_atm})")
            if flag_land is not False:
                feedback_parts.append(f"Landscape not disabled (flag_landscape={flag_land})")

        # ── Criterion 3: Antenna Grid Setup (15 pts) ─────────────────────────
        flag_az_grid = result.get('flag_azimuthal_grid')
        if flag_az_grid is True:
            score += 15
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal coordinate grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append(f"Azimuthal grid not enabled (flag_azimuthal_grid={flag_az_grid})")

        # ── Criterion 4: Target Screenshot (20 pts) ──────────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} target screenshots taken")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots taken")

        # ── Criterion 5: Scheduling Report (20 pts) ──────────────────────────
        report_exists = result.get('report_exists', False)
        has_alma = result.get('report_has_alma', False)
        has_2017 = result.get('report_has_2017', False)
        has_target = result.get('report_has_target', False)

        if report_exists:
            content_matches = sum([has_alma, has_2017, has_target])
            if content_matches == 3:
                score += 20
                subscores["report"] = True
                feedback_parts.append("Scheduling report written with all required keywords")
            elif content_matches >= 1:
                score += 10
                subscores["report"] = False
                feedback_parts.append(f"Scheduling report missing some keywords (found {content_matches}/3 keywords)")
            else:
                subscores["report"] = False
                feedback_parts.append("Scheduling report found but missing required keywords")
        else:
            subscores["report"] = False
            feedback_parts.append("Scheduling report file not created")

        # ── Final evaluation ─────────────────────────────────────────────────
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification failed with exception: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification script error: {str(e)}"
        }