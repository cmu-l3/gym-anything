#!/usr/bin/env python3
"""
Verifier for pilot_ufo_investigation task.

Scoring (100 points):
- Location latitude correct (±0.02 rad of 0.7854): 10 pts
- Location longitude correct (±0.02 rad of -0.6981): 10 pts
- Altitude set to ~11000m (±500m): 5 pts
- Ground/landscape disabled: 10 pts
- Atmosphere enabled: 5 pts
- Planet labels enabled: 5 pts
- Cardinal direction labels enabled: 5 pts
- ≥2 new screenshots taken: 20 pts
- Report file exists and >100 bytes: 5 pts
- Report identifies Venus: 20 pts
- Report contains date/location context: 5 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

TARGET_LAT_RAD = 0.7854   # 45.00 degrees N
TARGET_LON_RAD = -0.6981  # -40.00 degrees W
TARGET_ALT_M = 11000
LAT_LON_TOLERANCE_RAD = 0.02  # ~1.1 degrees tolerance
ALT_TOLERANCE_M = 500


def verify_pilot_ufo_investigation(traj, env_info, task_info):
    """
    Verify pilot UFO investigation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "pilot_ufo_investigation"

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

        # ── Criterion 1: Location & Altitude (25 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')
        alt_m = result.get('alt_m')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - TARGET_LAT_RAD)
            lon_diff = abs(lon_rad - TARGET_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD:
                score += 10
                subscores["lat"] = True
                feedback_parts.append(f"Latitude correct ({math.degrees(lat_rad):.2f}°N)")
            else:
                subscores["lat"] = False
                feedback_parts.append(f"Latitude incorrect ({math.degrees(lat_rad):.2f}°N, expected ~45°N)")

            if lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 10
                subscores["lon"] = True
                feedback_parts.append(f"Longitude correct ({math.degrees(lon_rad):.2f}°E/W)")
            else:
                subscores["lon"] = False
                feedback_parts.append(f"Longitude incorrect ({math.degrees(lon_rad):.2f}°, expected ~-40°W)")
        else:
            subscores["lat"] = False
            subscores["lon"] = False
            feedback_parts.append("Location not found in config")

        if alt_m is not None:
            if abs(alt_m - TARGET_ALT_M) <= ALT_TOLERANCE_M:
                score += 5
                subscores["alt"] = True
                feedback_parts.append(f"Altitude correct ({alt_m}m)")
            else:
                subscores["alt"] = False
                feedback_parts.append(f"Altitude incorrect ({alt_m}m, expected 11000m)")
        else:
            subscores["alt"] = False
            feedback_parts.append("Altitude not found")

        # ── Criterion 2: Display Settings (25 pts) ─────────────
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is True:
            score += 5
            subscores["atmosphere"] = True
            feedback_parts.append("Atmosphere enabled")
        else:
            subscores["atmosphere"] = False
            feedback_parts.append("Atmosphere not enabled")

        flag_land = result.get('flag_landscape')
        if flag_land is False:
            score += 10
            subscores["landscape"] = True
            feedback_parts.append("Landscape disabled")
        else:
            subscores["landscape"] = False
            feedback_parts.append("Landscape still enabled")

        flag_planets = result.get('flag_planets_labels')
        if flag_planets is True:
            score += 5
            subscores["planet_labels"] = True
            feedback_parts.append("Planet labels enabled")
        else:
            subscores["planet_labels"] = False
            feedback_parts.append("Planet labels not enabled")

        flag_card = result.get('flag_cardinal_points')
        if flag_card is True:
            score += 5
            subscores["cardinal"] = True
            feedback_parts.append("Cardinal points enabled")
        else:
            subscores["cardinal"] = False
            feedback_parts.append("Cardinal points not enabled")

        # ── Criterion 3: 2+ screenshots taken (20 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 2:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} reference screenshots captured")
        elif new_ss >= 1:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshot (partial; required: 2)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots taken")

        # ── Criterion 4: Report with Venus ID and context (30 pts) ────────
        report_exists = result.get('report_exists', False)
        report_has_venus = result.get('report_has_venus', False)
        report_has_context = result.get('report_has_date_loc', False)
        report_size = result.get('report_size', 0)

        if report_exists and report_size > 50:
            score += 5
            subscores["report_exists"] = True
            
            if report_has_venus:
                score += 20
                subscores["report_venus"] = True
                feedback_parts.append("Report identifies Venus")
            else:
                subscores["report_venus"] = False
                feedback_parts.append("Report does not identify Venus")

            if report_has_context:
                score += 5
                subscores["report_context"] = True
                feedback_parts.append("Report has date/location context")
            else:
                subscores["report_context"] = False
                feedback_parts.append("Report lacks date/location context")
        else:
            subscores["report_exists"] = False
            subscores["report_venus"] = False
            subscores["report_context"] = False
            feedback_parts.append("Report missing or too short")

        passed = score >= 70 and subscores.get("report_venus", False) and new_ss > 0

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Error in verify_pilot_ufo_investigation: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {str(e)}"
        }