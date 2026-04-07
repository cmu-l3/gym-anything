#!/usr/bin/env python3
"""
Verifier for variable_star_finder_chart task.

Scoring (100 points):
- Location configured to Boston (lat within 0.10 rad of 0.7393 rad): 20 pts
- Atmosphere disabled: 15 pts
- Grid/Lines Enabled (Constellation lines, labels, eq grid): 20 pts
- Chart Captured (new screenshot): 25 pts
- Observation Plan Written with Algol, Perseus, Boston: 20 pts

Pass threshold: 75 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Boston ground truth
BOSTON_LAT_RAD = 0.7393
BOSTON_LON_RAD = -1.2400
LAT_LON_TOLERANCE_RAD = 0.10


def verify_variable_star_finder_chart(traj, env_info, task_info):
    """
    Verify variable star finder chart task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "variable_star_finder_chart"

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

        # ── Criterion 1: Location (20 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - BOSTON_LAT_RAD)
            lon_diff = abs(lon_rad - BOSTON_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"Boston location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~42.36°N, ~-71.05°W for Boston)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Atmosphere Disabled (15 pts) ─────────────
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is False:
            score += 15
            subscores["atmosphere_off"] = True
            feedback_parts.append("Atmosphere disabled")
        else:
            subscores["atmosphere_off"] = False
            feedback_parts.append(f"Atmosphere not disabled (flag_atmosphere={flag_atm})")

        # ── Criterion 3: Grid/Lines Enabled (20 pts) ─────────────────────
        flag_lines = result.get('flag_constellation_drawing')
        flag_names = result.get('flag_constellation_name')
        flag_eq = result.get('flag_equatorial_grid')
        
        flags_correct = 0
        if flag_lines: flags_correct += 1
        if flag_names: flags_correct += 1
        if flag_eq: flags_correct += 1
        
        if flags_correct == 3:
            score += 20
            subscores["display_flags"] = True
            feedback_parts.append("Constellation lines, names, and equatorial grid enabled")
        else:
            partial_points = flags_correct * 6
            score += partial_points
            subscores["display_flags"] = False
            feedback_parts.append(f"Display flags partial ({flags_correct}/3 correct)")

        # ── Criterion 4: Chart Captured (25 pts) ─────────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 25
            subscores["screenshots"] = True
            feedback_parts.append(f"Chart captured ({new_ss} screenshots)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 5: Observation Plan Written (20 pts) ───────────────────────
        plan_exists = result.get('plan_exists', False)
        plan_has_algol = result.get('plan_has_algol', False)
        plan_has_perseus = result.get('plan_has_perseus', False)
        plan_has_boston = result.get('plan_has_boston', False)
        
        if plan_exists:
            matches = sum([plan_has_algol, plan_has_perseus, plan_has_boston])
            if matches == 3:
                score += 20
                subscores["plan"] = True
                feedback_parts.append("Observation plan written with all keywords")
            else:
                score += matches * 6
                subscores["plan"] = False
                feedback_parts.append(f"Observation plan missing some keywords ({matches}/3 found)")
        else:
            subscores["plan"] = False
            feedback_parts.append("Observation plan file not created")

        passed = score >= 75
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    except Exception as e:
        logger.error(f"Error during verification: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }