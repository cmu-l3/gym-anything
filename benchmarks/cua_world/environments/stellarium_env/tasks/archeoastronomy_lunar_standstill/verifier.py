#!/usr/bin/env python3
"""
Verifier for archeoastronomy_lunar_standstill task.

Scoring (100 points):
- Location Configuration (lat within 0.05 rad of 0.649 rad): 20 pts
- Azimuthal Grid Enabled: 15 pts
- Atmosphere Disabled: 15 pts
- Landscape Enabled: 10 pts
- Cardinal points enabled: 5 pts
- Screenshot Captured: 15 pts
- Standstill Brief Written with correct content: 20 pts

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Chimney Rock Ground Truth
# Latitude 37.193 N -> 0.64914 rad
# Longitude 107.309 W -> -1.87288 rad
CHIMNEY_ROCK_LAT_RAD = 0.64914
CHIMNEY_ROCK_LON_RAD = -1.87288
LAT_LON_TOLERANCE_RAD = 0.05

def verify_archeoastronomy_lunar_standstill(traj, env_info, task_info):
    """
    Verify archeoastronomy lunar standstill task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "archeoastronomy_lunar_standstill"

    try:
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

        # 1. Location Configuration (20 pts)
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - CHIMNEY_ROCK_LAT_RAD)
            lon_diff = abs(lon_rad - CHIMNEY_ROCK_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"Chimney Rock location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~37.19°N, ~-107.31°W)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # 2. Atmosphere Disabled (15 pts)
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is False:
            score += 15
            subscores["atmosphere_off"] = True
            feedback_parts.append("Atmosphere disabled")
        else:
            subscores["atmosphere_off"] = False
            feedback_parts.append("Atmosphere still enabled")

        # 3. Landscape Enabled (10 pts)
        flag_land = result.get('flag_landscape')
        if flag_land is True:
            score += 10
            subscores["landscape_on"] = True
            feedback_parts.append("Landscape enabled")
        else:
            subscores["landscape_on"] = False
            feedback_parts.append("Landscape disabled")

        # 4. Azimuthal Grid Enabled (15 pts)
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            score += 15
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append("Azimuthal grid not enabled")

        # 5. Cardinal Points Enabled (5 pts)
        flag_card = result.get('flag_cardinal_points')
        if flag_card is True:
            score += 5
            subscores["cardinal_points"] = True
            feedback_parts.append("Cardinal points enabled")
        else:
            subscores["cardinal_points"] = False
            feedback_parts.append("Cardinal points not enabled")

        # 6. Screenshot Captured (15 pts)
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 15
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} screenshot(s) captured")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots taken")

        # 7. Standstill Brief Written (20 pts)
        brief_exists = result.get('brief_exists', False)
        brief_chimney = result.get('brief_has_chimney_rock', False)
        brief_date = result.get('brief_has_date', False)
        brief_azimuth = result.get('brief_has_azimuth', False)

        if brief_exists:
            brief_score = 5
            parts = []
            if brief_chimney:
                brief_score += 5
                parts.append("Location")
            if brief_date:
                brief_score += 5
                parts.append("Date")
            if brief_azimuth:
                brief_score += 5
                parts.append("Azimuth")
            
            score += brief_score
            subscores["brief"] = True if brief_score == 20 else False
            feedback_parts.append(f"Brief file exists ({', '.join(parts) if parts else 'missing content'})")
        else:
            subscores["brief"] = False
            feedback_parts.append("Brief file not written")

        passed = score >= 70 and subscores.get("location", False) and subscores.get("brief", False)

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
            "feedback": f"Error during verification: {e}"
        }