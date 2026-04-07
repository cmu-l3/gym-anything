#!/usr/bin/env python3
"""
Verifier for titanic_night_sky_research task.

Scoring (100 points):
- Location latitude correct (41.73°N +/- tolerance): 15 pts
- Location longitude correct (50.23°W +/- tolerance): 10 pts
- Ground/landscape disabled: 10 pts
- Atmosphere enabled: 10 pts
- Constellation lines enabled: 8 pts
- Constellation names enabled: 7 pts
- 3+ screenshots taken: 20 pts
- Research notes file exists & has size > 0: 10 pts
- Research notes content contains "1912" and "moon": 10 pts

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Ground truth coordinates (radians)
TARGET_LAT_RAD = math.radians(41.726)   # ~ 0.72826 rad
TARGET_LON_RAD = math.radians(-50.233)  # ~ -0.87673 rad
LAT_LON_TOLERANCE_RAD = 0.05            # ~ 2.8 degrees tolerance


def verify_titanic_night_sky_research(traj, env_info, task_info):
    """
    Verify the Titanic sky research task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "titanic_night_sky_research"

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

        # ── Criterion 1: Location Check (Latitude: 15 pts, Longitude: 10 pts)
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - TARGET_LAT_RAD)
            lon_diff = abs(lon_rad - TARGET_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD:
                score += 15
                subscores["latitude"] = True
                feedback_parts.append(f"Latitude correct ({math.degrees(lat_rad):.2f}°N)")
            else:
                subscores["latitude"] = False
                feedback_parts.append(f"Wrong latitude ({math.degrees(lat_rad):.2f}°N, expected ~41.73°N)")

            if lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 10
                subscores["longitude"] = True
                feedback_parts.append(f"Longitude correct ({math.degrees(lon_rad):.2f}°)")
            else:
                subscores["longitude"] = False
                feedback_parts.append(f"Wrong longitude ({math.degrees(lon_rad):.2f}°, expected ~-50.23°W)")
        else:
            subscores["latitude"] = False
            subscores["longitude"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Display Flags (Ground: 10 pts, Atm: 10 pts, Const Lines: 8 pts, Const Names: 7 pts)
        flag_landscape = result.get('flag_landscape')
        if flag_landscape is False:
            score += 10
            subscores["landscape_off"] = True
            feedback_parts.append("Ground disabled")
        else:
            subscores["landscape_off"] = False
            feedback_parts.append("Ground still enabled")

        flag_atmosphere = result.get('flag_atmosphere')
        if flag_atmosphere is True:
            score += 10
            subscores["atmosphere_on"] = True
            feedback_parts.append("Atmosphere enabled")
        else:
            subscores["atmosphere_on"] = False
            feedback_parts.append("Atmosphere disabled")

        flag_const_lines = result.get('flag_constellation_drawing')
        if flag_const_lines is True:
            score += 8
            subscores["const_lines_on"] = True
            feedback_parts.append("Constellation lines enabled")
        else:
            subscores["const_lines_on"] = False
            feedback_parts.append("Constellation lines disabled")

        flag_const_names = result.get('flag_constellation_name')
        if flag_const_names is True:
            score += 7
            subscores["const_names_on"] = True
            feedback_parts.append("Constellation names enabled")
        else:
            subscores["const_names_on"] = False
            feedback_parts.append("Constellation names disabled")

        # ── Criterion 3: Screenshots (20 pts)
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} screenshots captured")
        elif new_ss >= 1:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append(f"Partial screenshots: {new_ss} (expected >= 3)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 4: Research Notes Exists (10 pts)
        notes_exists = result.get('notes_exists', False)
        notes_size = result.get('notes_size_bytes', 0)
        if notes_exists and notes_size > 10:
            score += 10
            subscores["notes_exist"] = True
            feedback_parts.append("Research notes written")
        else:
            subscores["notes_exist"] = False
            feedback_parts.append("Research notes missing or empty")

        # ── Criterion 5: Research Notes Content (10 pts)
        has_1912 = result.get('notes_has_1912', False)
        has_moon = result.get('notes_has_moon', False)
        
        if has_1912 and has_moon:
            score += 10
            subscores["notes_content"] = True
            feedback_parts.append("Notes contain required keywords ('1912', 'moon')")
        elif has_1912 or has_moon:
            score += 5
            subscores["notes_content"] = False
            feedback_parts.append("Notes missing some keywords (partial credit)")
        else:
            subscores["notes_content"] = False
            feedback_parts.append("Notes missing required keywords")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Error during verification: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }