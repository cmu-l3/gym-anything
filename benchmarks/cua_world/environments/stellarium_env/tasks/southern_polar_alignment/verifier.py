#!/usr/bin/env python3
"""
Verifier for southern_polar_alignment task.

Scoring (100 points):
- Location (Mount John, NZ): 20 pts
- Equatorial Grid Enabled: 15 pts
- Constellations (Lines & Names) Active: 15 pts
- Atmosphere Disabled: 10 pts
- Screenshots Captured (>= 2): 20 pts
- Reference Guide Content (keywords): 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Mount John Observatory
TARGET_LAT_RAD = -0.7677   # ~ -43.986 degrees
TARGET_LON_RAD = 2.9751    # ~ 170.465 degrees
LAT_TOLERANCE_RAD = 0.05
LON_TOLERANCE_RAD = 0.10

def verify_southern_polar_alignment(traj, env_info, task_info):
    """Verify Southern Hemisphere polar alignment reference task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "southern_polar_alignment"

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
        
        # ── 1. Location (20 pts) ────────────────────────────────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')
        location_passed = False

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - TARGET_LAT_RAD)
            lon_diff = abs(lon_rad - TARGET_LON_RAD)
            
            if lat_diff <= LAT_TOLERANCE_RAD and lon_diff <= LON_TOLERANCE_RAD:
                score += 20
                location_passed = True
                feedback_parts.append(
                    f"Location set to Mount John region (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° (expected ~-43.98° S, 170.46° E)"
                )
        else:
            feedback_parts.append("Location not found in config")

        # ── 2. Grid Enabled (15 pts) ─────────────────────────────────────────────
        if result.get('flag_equatorial_grid') is True:
            score += 15
            feedback_parts.append("Equatorial grid enabled")
        else:
            feedback_parts.append("Equatorial grid not enabled")

        # ── 3. Constellations Active (15 pts) ────────────────────────────────────
        lines_on = result.get('flag_constellation_drawing') is True
        names_on = result.get('flag_constellation_name') is True
        
        if lines_on and names_on:
            score += 15
            feedback_parts.append("Constellation lines and names enabled")
        elif lines_on:
            score += 7
            feedback_parts.append("Constellation lines enabled, but names missing")
        elif names_on:
            score += 7
            feedback_parts.append("Constellation names enabled, but lines missing")
        else:
            feedback_parts.append("Constellation overlays not enabled")

        # ── 4. Atmosphere Disabled (10 pts) ──────────────────────────────────────
        if result.get('flag_atmosphere') is False:
            score += 10
            feedback_parts.append("Atmosphere disabled")
        else:
            feedback_parts.append("Atmosphere still enabled")

        # ── 5. Screenshots Captured (20 pts) ─────────────────────────────────────
        ss_count = result.get('new_screenshot_count', 0)
        if ss_count >= 2:
            score += 20
            feedback_parts.append(f"{ss_count} screenshots captured")
        elif ss_count == 1:
            score += 10
            feedback_parts.append("Only 1 screenshot captured (expected 2)")
        else:
            feedback_parts.append("No screenshots captured")

        # ── 6. Reference Guide Content (20 pts) ──────────────────────────────────
        notes_exists = result.get('notes_exists', False)
        notes_content = result.get('notes_content', '').lower()
        notes_passed = False
        
        if notes_exists:
            keywords = ["john", "april", "sigma octantis", "crux"]
            # Accept alternate spelling for Sigma Octantis
            if "octans" in notes_content and "sigma" in notes_content:
                notes_content += " sigma octantis " 

            found_keywords = [kw for kw in keywords if kw in notes_content]
            
            if len(found_keywords) == len(keywords):
                score += 20
                notes_passed = True
                feedback_parts.append("Notes file contains all required keywords")
            else:
                pts = len(found_keywords) * 5
                score += pts
                missing = [kw for kw in keywords if kw not in found_keywords]
                feedback_parts.append(f"Notes file missing keywords: {', '.join(missing)} (+{pts} pts)")
        else:
            feedback_parts.append("Notes file not found")

        # ── Final assessment ────────────────────────────────────────────────────
        # Pass threshold is 70 points, AND must have gotten location + notes content
        passed = (score >= 70) and location_passed and notes_passed

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {str(e)}"}