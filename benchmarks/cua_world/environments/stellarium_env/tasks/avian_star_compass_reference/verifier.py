#!/usr/bin/env python3
"""
Verifier for avian_star_compass_reference task.

Scoring (100 points):
- Location Setup (20 pts): Lat ~0.5163 rad, Lon ~-1.6473 rad (High Island)
- Date/Time Setup (10 pts): JD ~ 2460431.7 (May 1, 2024)
- Sky Geometry Display (15 pts): Equatorial Grid ON, Constellation Boundaries ON
- Distractions Removed (15 pts): Atmosphere OFF, Landscape OFF
- Constellation Lines (10 pts): Constellation drawing ON
- Screenshot Evidence (15 pts): 1+ new files created
- Research Notes File (15 pts): Text file contains required keywords

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Ground truth values
HIGH_ISLAND_LAT_RAD = 0.5163   # 29.5833 degrees N
HIGH_ISLAND_LON_RAD = -1.6473  # -94.3833 degrees W
LAT_LON_TOLERANCE_RAD = 0.05   # ~2.8 degrees

MAY_1_2024_JD = 2460431.708
JD_TOLERANCE = 2.0  # Allow +/- 2 days for the simulation time


def verify_avian_star_compass(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "avian_star_compass_reference"

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

        # ── 1. Location Setup (20 pts) ───────────────────────────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        location_pass = False
        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - HIGH_ISLAND_LAT_RAD)
            lon_diff = abs(lon_rad - HIGH_ISLAND_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                location_pass = True
                feedback_parts.append(f"Location correct (High Island: {math.degrees(lat_rad):.2f}°N, {math.degrees(lon_rad):.2f}°W)")
            else:
                feedback_parts.append(f"Location wrong (Got: {math.degrees(lat_rad):.2f}°N, {math.degrees(lon_rad):.2f}°W)")
        else:
            feedback_parts.append("Location not found in config")

        # ── 2. Date/Time Setup (10 pts) ──────────────────────────────────────────
        preset_sky_time = result.get('preset_sky_time')
        if preset_sky_time is not None:
            jd_diff = abs(preset_sky_time - MAY_1_2024_JD)
            if jd_diff <= JD_TOLERANCE:
                score += 10
                feedback_parts.append("Date/Time correct (May 2024)")
            else:
                feedback_parts.append(f"Date/Time wrong (JD {preset_sky_time:.1f} vs expected {MAY_1_2024_JD:.1f})")
        else:
            feedback_parts.append("Date/Time not found in config")

        # ── 3. Sky Geometry Display (15 pts) ─────────────────────────────────────
        flag_eq_grid = result.get('flag_equatorial_grid', False)
        flag_boundaries = result.get('flag_constellation_boundaries', False)
        
        geometry_pass_count = 0
        if flag_eq_grid: geometry_pass_count += 1
        if flag_boundaries: geometry_pass_count += 1
        
        if geometry_pass_count == 2:
            score += 15
            feedback_parts.append("Geometry display correct (Grid ON, Boundaries ON)")
        elif geometry_pass_count == 1:
            score += 7
            feedback_parts.append("Geometry display partial")
        else:
            feedback_parts.append("Geometry display incorrect")

        # ── 4. Distractions Removed (15 pts) ─────────────────────────────────────
        flag_atmosphere = result.get('flag_atmosphere', True)
        flag_landscape = result.get('flag_landscape', True)
        
        distraction_pass_count = 0
        if not flag_atmosphere: distraction_pass_count += 1
        if not flag_landscape: distraction_pass_count += 1
        
        if distraction_pass_count == 2:
            score += 15
            feedback_parts.append("Distractions removed (Atmosphere OFF, Landscape OFF)")
        elif distraction_pass_count == 1:
            score += 7
            feedback_parts.append("Distractions partial (only one disabled)")
        else:
            feedback_parts.append("Distractions present (Atmosphere and Landscape still ON)")

        # ── 5. Constellation Lines (10 pts) ──────────────────────────────────────
        flag_drawing = result.get('flag_constellation_drawing', False)
        if flag_drawing:
            score += 10
            feedback_parts.append("Constellation drawing ON")
        else:
            feedback_parts.append("Constellation drawing OFF")

        # ── 6. Screenshot Evidence (15 pts) ──────────────────────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 15
            feedback_parts.append(f"Screenshot taken ({new_ss} new files)")
        else:
            feedback_parts.append("No screenshot taken")

        # ── 7. Research Notes File (15 pts) ──────────────────────────────────────
        notes_exists = result.get('notes_exists', False)
        if notes_exists:
            k_island = result.get('has_high_island', False)
            k_polaris = result.get('has_polaris', False)
            k_may = result.get('has_may', False)
            k_boundar = result.get('has_boundar', False)
            
            keywords_matched = sum([k_island, k_polaris, k_may, k_boundar])
            
            if keywords_matched == 4:
                score += 15
                feedback_parts.append("Notes correct (All keywords found)")
            elif keywords_matched >= 2:
                score += 7
                feedback_parts.append(f"Notes partial ({keywords_matched}/4 keywords found)")
            else:
                feedback_parts.append(f"Notes poor ({keywords_matched}/4 keywords found)")
        else:
            feedback_parts.append("Notes file missing")

        # ── Final Evaluation ─────────────────────────────────────────────────────
        display_criteria_met = (geometry_pass_count >= 1) or (distraction_pass_count >= 1) or flag_drawing
        key_criteria_met = location_pass and display_criteria_met

        passed = score >= 70 and key_criteria_met
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with exception: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during verification: {str(e)}"
        }