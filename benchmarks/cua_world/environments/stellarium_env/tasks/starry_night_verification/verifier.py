#!/usr/bin/env python3
"""
Verifier for starry_night_verification task.

Scoring (100 points):
- Location set correctly (lat within 0.05 rad of 0.7643 rad): 20 pts
- Atmosphere enabled: 10 pts
- Ground/landscape disabled: 10 pts
- Constellation lines enabled: 10 pts
- Planet labels enabled: 10 pts
- 3+ screenshots taken: 20 pts
- Analysis report written with Venus content: 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Saint-Rémy-de-Provence ground truth
SAINT_REMY_LAT_RAD = 0.76426   # 43.789 degrees N
SAINT_REMY_LON_RAD = 0.08431   # 4.831 degrees E
LAT_LON_TOLERANCE_RAD = 0.05  # Generous tolerance


def verify_starry_night_verification(traj, env_info, task_info):
    """
    Verify Starry Night astronomy task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "starry_night_verification"

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

        # 1. Location (20 pts)
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - SAINT_REMY_LAT_RAD)
            lon_diff = abs(lon_rad - SAINT_REMY_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(f"Location set correctly (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                subscores["location"] = False
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°. Expected ~43.79°N, 4.83°E.")
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # 2. Atmosphere enabled (10 pts)
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is True:
            score += 10
            subscores["atmosphere"] = True
            feedback_parts.append("Atmosphere enabled")
        else:
            subscores["atmosphere"] = False
            feedback_parts.append("Atmosphere disabled (should be ON for dawn simulation)")

        # 3. Landscape disabled (10 pts)
        flag_ls = result.get('flag_landscape')
        if flag_ls is False:
            score += 10
            subscores["landscape"] = True
            feedback_parts.append("Landscape disabled")
        else:
            subscores["landscape"] = False
            feedback_parts.append("Landscape enabled (should be OFF for full dome view)")

        # 4. Constellation lines enabled (10 pts)
        flag_const = result.get('flag_constellation_drawing')
        if flag_const is True:
            score += 10
            subscores["constellation"] = True
            feedback_parts.append("Constellation lines enabled")
        else:
            subscores["constellation"] = False
            feedback_parts.append("Constellation lines disabled")

        # 5. Planet labels enabled (10 pts)
        planet_flags = [
            result.get('flag_planet_names'),
            result.get('flag_planets_labels'),
            result.get('flag_planets')
        ]
        if any(flag is True for flag in planet_flags):
            score += 10
            subscores["planets"] = True
            feedback_parts.append("Planet labels enabled")
        else:
            subscores["planets"] = False
            feedback_parts.append("Planet labels disabled")

        # 6. Screenshots (20 pts)
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} screenshots taken")
        elif new_ss >= 1:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshot(s) taken (partial credit)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots taken")

        # 7. Report file (20 pts)
        rep_exists = result.get('report_exists', False)
        rep_size = result.get('report_size', 0)
        rep_has_v = result.get('report_has_venus', False)
        rep_has_vg = result.get('report_has_van_gogh', False)

        if rep_exists and rep_size > 10:
            if rep_has_v and rep_has_vg:
                score += 20
                subscores["report"] = True
                feedback_parts.append("Report written with correct keywords (Venus, Van Gogh)")
            elif rep_has_v or rep_has_vg:
                score += 10
                subscores["report"] = False
                feedback_parts.append("Report missing some expected keywords")
            else:
                score += 5
                subscores["report"] = False
                feedback_parts.append("Report exists but missing required astronomical keywords")
        else:
            subscores["report"] = False
            feedback_parts.append("Analysis report not found or empty")

        passed = score >= 70
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }