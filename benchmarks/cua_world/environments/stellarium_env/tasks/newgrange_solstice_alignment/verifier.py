#!/usr/bin/env python3
"""
Verifier for newgrange_solstice_alignment task.

Scoring (100 points):
- Location set to Newgrange (lat ~0.937 rad): 20 pts
- Azimuthal grid enabled: 10 pts
- Cardinal points enabled: 10 pts
- Atmosphere enabled: 5 pts
- Ground/landscape disabled: 5 pts
- 2+ screenshots taken: 25 pts
- Notes file exists: 5 pts
- Notes mention "Newgrange": 5 pts
- Notes mention "solstice": 5 pts
- Notes mention ancient date (3200/BCE): 5 pts
- Notes mention azimuth/direction: 5 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Newgrange ground truth
NEWGRANGE_LAT_RAD = 0.93717   # 53.6947 degrees N
NEWGRANGE_LON_RAD = -0.11302  # -6.4755 degrees W
LAT_LON_TOLERANCE_RAD = 0.05  # ~2.86 degrees tolerance


def verify_newgrange_alignment(traj, env_info, task_info):
    """
    Verify Archaeoastronomy Winter Solstice Alignment task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "newgrange_solstice_alignment"

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

        # ── Criterion 1: Location near Newgrange (20 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - NEWGRANGE_LAT_RAD)
            lon_diff = abs(lon_rad - NEWGRANGE_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"Newgrange location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~53.69°N, ~-6.48°W for Newgrange)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Azimuthal grid enabled (10 pts) ─────────────────────
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            score += 10
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal coordinate grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append("Azimuthal grid not enabled")

        # ── Criterion 3: Cardinal points enabled (10 pts) ────────────────────
        flag_card = result.get('flag_cardinal_points')
        if flag_card is True:
            score += 10
            subscores["cardinal_points"] = True
            feedback_parts.append("Cardinal points enabled")
        else:
            subscores["cardinal_points"] = False
            feedback_parts.append("Cardinal points not enabled")

        # ── Criterion 4: Atmosphere enabled (5 pts) ─────────────────────────
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is True:
            score += 5
            subscores["atmosphere_on"] = True
            feedback_parts.append("Atmosphere enabled")
        else:
            subscores["atmosphere_on"] = False
            feedback_parts.append("Atmosphere disabled (should be ON)")

        # ── Criterion 5: Landscape disabled (5 pts) ─────────────────────────
        flag_land = result.get('flag_landscape')
        if flag_land is False:
            score += 5
            subscores["landscape_off"] = True
            feedback_parts.append("Landscape/Ground disabled")
        else:
            subscores["landscape_off"] = False
            feedback_parts.append("Landscape/Ground enabled (should be OFF for clear horizon)")

        # ── Criterion 6: 2+ screenshots taken (25 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 2:
            score += 25
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} observation screenshots captured")
        elif new_ss == 1:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append("Only 1 screenshot captured (partial credit; required: 2)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No new screenshots captured")

        # ── Criterion 7: Notes file & content (25 pts) ───────────────────────
        notes_exists = result.get('notes_exists', False)
        if notes_exists:
            score += 5
            feedback_parts.append("Notes file exists")
            
            has_newg = result.get('notes_has_newgrange', False)
            if has_newg:
                score += 5
                
            has_sol = result.get('notes_has_solstice', False)
            if has_sol:
                score += 5
                
            has_anc = result.get('notes_has_ancient', False)
            if has_anc:
                score += 5
                
            has_az = result.get('notes_has_azimuth', False)
            if has_az:
                score += 5
                
            if has_newg and has_sol and has_anc and has_az:
                feedback_parts.append("Notes contain all required keywords")
            else:
                feedback_parts.append(f"Notes missing keywords: Newgrange={has_newg}, solstice={has_sol}, ancient={has_anc}, azimuth={has_az}")
        else:
            feedback_parts.append("Notes file missing")

        # ── Final Evaluation ───────────────────────────────────────────────────
        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {
                "score": score,
                "subscores": subscores,
                "result_data": result
            }
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification script error: {str(e)}"
        }