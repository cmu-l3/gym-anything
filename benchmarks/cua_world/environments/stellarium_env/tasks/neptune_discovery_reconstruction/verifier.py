#!/usr/bin/env python3
"""
Verifier for neptune_discovery_reconstruction task.
"""

import json
import tempfile
import os
import math
import re
import logging

logger = logging.getLogger(__name__)

TARGET_LAT_RAD = 0.91635
TARGET_LON_RAD = 0.23375
LAT_LON_TOLERANCE_RAD = 0.1  # ~5.7 degrees tolerance

def verify_neptune_reconstruction(traj, env_info, task_info):
    """
    Verify Neptune reconstruction task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "neptune_reconstruction"

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
        
        # ── Criterion 1: Location Configuration (15 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - TARGET_LAT_RAD)
            lon_diff = abs(lon_rad - TARGET_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 15
                feedback_parts.append(f"Berlin location set (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}° (expected ~52.5°N, ~13.4°E)")
        else:
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Chart Display Flags (20 pts) ─────────────
        flag_atm = result.get('flag_atmosphere')
        flag_land = result.get('flag_landscape')
        flag_const = result.get('flag_constellation_drawing')
        
        display_score = 0
        if flag_atm is False and flag_land is False:
            display_score += 10
            feedback_parts.append("Atmosphere and landscape disabled")
        else:
            feedback_parts.append("Atmosphere/landscape not fully disabled")
            
        if flag_const is True:
            display_score += 10
            feedback_parts.append("Constellation drawing enabled")
        else:
            feedback_parts.append("Constellation drawing not enabled")
            
        score += display_score

        # ── Criterion 3: Advanced Markings (15 pts) ─────────────────────
        flag_eq = result.get('flag_equatorial_grid')
        flag_bound = result.get('flag_constellation_boundaries')
        
        markings_score = 0
        if flag_eq is True:
            markings_score += 7
        if flag_bound is True:
            markings_score += 8
            
        score += markings_score
        if markings_score == 15:
            feedback_parts.append("Equatorial grid and constellation boundaries enabled")
        else:
            feedback_parts.append("Advanced markings missing (equatorial grid or constellation boundaries)")

        # ── Criterion 4: Screenshot Captured (15 pts) ─────────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 15
            feedback_parts.append(f"{new_ss} screenshot(s) captured")
        else:
            feedback_parts.append("No screenshots captured")

        # ── Criterion 5: Epoch Constellation (20 pts) ───────────────────────
        notes_exists = result.get('notes_exists', False)
        notes_content = result.get('notes_content', "").lower()
        
        has_aquarius = False
        has_correct_ra = False
        
        if notes_exists:
            if "aquarius" in notes_content or "aqr" in notes_content:
                score += 20
                has_aquarius = True
                feedback_parts.append("Constellation correctly identified as Aquarius")
            elif "pisces" in notes_content:
                feedback_parts.append("Constellation identified as Pisces - WRONG EPOCH (failed time travel)")
            else:
                feedback_parts.append("Constellation not correctly identified as Aquarius in notes")
                
            # ── Criterion 6: Epoch Coordinates (15 pts) ───────────────────────
            # Look for 21h, 21 h, 21:, or just 21 followed by some minutes
            if re.search(r'21\s*[h:]', notes_content):
                score += 15
                has_correct_ra = True
                feedback_parts.append("RA correctly identified around 21h")
            elif re.search(r'23\s*[h:]', notes_content):
                feedback_parts.append("RA identified around 23h - WRONG EPOCH (present day)")
            else:
                feedback_parts.append("RA ~21h not found in notes")
        else:
            feedback_parts.append("Notes file not found")

        # Key criteria: Must have successfully navigated to 1846 (proven by Aquarius or 21h RA)
        time_travel_proven = has_aquarius or has_correct_ra
        passed = score >= 75 and time_travel_proven

        if passed and not time_travel_proven:
            passed = False
            feedback_parts.append("FAILED: Did not prove navigation to 1846 epoch (missing Aquarius / 21h RA)")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}