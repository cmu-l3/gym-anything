#!/usr/bin/env python3
"""
Verifier for chelyabinsk_solar_blindspot task.

Scoring (100 points):
- Location set to Chelyabinsk (lat 0.9625, lon 1.0716 rad): 20 pts
- Date & Time set to ~2456338.6389 JD (Feb 15 2013): 20 pts
- Atmosphere enabled: 15 pts
- Azimuthal grid & cardinal points enabled: 15 pts
- Screenshot captured: 15 pts
- Analysis notes written with required keywords: 15 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

# Chelyabinsk, Russia ground truth
CHELYABINSK_LAT_RAD = 0.9625
CHELYABINSK_LON_RAD = 1.0716
LAT_LON_TOLERANCE_RAD = 0.05  # ~2.8 degrees tolerance

# Feb 15, 2013 03:20 UTC in Julian Days
TARGET_JD = 2456338.6389
JD_TOLERANCE = 0.1  # ~2.4 hours tolerance

def verify_chelyabinsk_solar_blindspot(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """Verify Chelyabinsk Solar Blind Spot task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "chelyabinsk_solar_blindspot"

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

        # ── Criterion 1: Location set to Chelyabinsk (20 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - CHELYABINSK_LAT_RAD)
            lon_diff = abs(lon_rad - CHELYABINSK_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(f"Chelyabinsk location set (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                subscores["location"] = False
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}° (expected ~55.15°N, ~61.40°E)")
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Date & Time set to Feb 15 2013 (20 pts) ───────────
        jd = result.get('preset_sky_time')
        if jd is not None and jd > 0:
            if abs(jd - TARGET_JD) <= JD_TOLERANCE:
                score += 20
                subscores["date_time"] = True
                feedback_parts.append(f"Date/Time accurately set (JD {jd:.4f})")
            else:
                subscores["date_time"] = False
                feedback_parts.append(f"Wrong Date/Time: JD {jd:.4f} (expected ~{TARGET_JD:.4f})")
        else:
            subscores["date_time"] = False
            feedback_parts.append("Date/Time not found in config")

        # ── Criterion 3: Atmosphere enabled (15 pts) ───────────────────────
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is True:
            score += 15
            subscores["atmosphere"] = True
            feedback_parts.append("Atmosphere enabled (solar glare visible)")
        else:
            subscores["atmosphere"] = False
            feedback_parts.append(f"Atmosphere disabled (flag_atmosphere={flag_atm})")

        # ── Criterion 4: Azimuthal Grid & Cardinal Points (15 pts) ─────────
        flag_az = result.get('flag_azimuthal_grid')
        flag_card = result.get('flag_cardinal_points')
        
        if flag_az is True and flag_card is True:
            score += 15
            subscores["grids"] = True
            feedback_parts.append("Azimuthal grid and cardinal points enabled")
        elif flag_az is True or flag_card is True:
            score += 7
            subscores["grids"] = False
            feedback_parts.append("Azimuthal grid OR cardinal points enabled (partial credit)")
        else:
            subscores["grids"] = False
            feedback_parts.append("Azimuthal grid and cardinal points disabled")

        # ── Criterion 5: Screenshot captured (15 pts) ──────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 15
            subscores["screenshot"] = True
            feedback_parts.append(f"{new_ss} screenshot(s) captured")
        else:
            subscores["screenshot"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 6: Analysis Notes (15 pts) ───────────────────────────
        notes_exists = result.get('analysis_notes_exists', False)
        notes_has_chely = result.get('notes_has_chelyabinsk', False)
        notes_has_sun = result.get('notes_has_sun', False)
        notes_has_year = result.get('notes_has_year', False)

        if notes_exists and (notes_has_chely and notes_has_sun and notes_has_year):
            score += 15
            subscores["notes"] = True
            feedback_parts.append("Analysis notes written with required keywords")
        elif notes_exists:
            score += 7
            subscores["notes"] = False
            feedback_parts.append("Analysis notes exist but missing some required keywords (partial credit)")
        else:
            subscores["notes"] = False
            feedback_parts.append("Analysis notes not found")

        # ── Final Evaluation ───────────────────────────────────────────────
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
            "feedback": f"Error during verification: {str(e)}"
        }