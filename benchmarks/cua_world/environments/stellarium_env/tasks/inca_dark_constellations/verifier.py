#!/usr/bin/env python3
"""
Verifier for inca_dark_constellations task.

Scoring (100 points):
- Location Accuracy (15 pts): lat/lon near Cusco
- Historical Date (10 pts): JD ~2250819 (or strongly indicated in notes)
- Sky Culture (20 pts): sky_culture = 'inca'
- View Settings (15 pts): atmosphere = False, landscape = False
- Cultural Rendering (15 pts): constellation_art = True, milky_way_intensity >= 4.0
- Screenshot Capture (10 pts): >= 1 screenshot taken
- Lecture Notes (15 pts): exists and contains required keywords

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Cusco ground truth
CUSCO_LAT_RAD = -0.2361   # -13.53 degrees N
CUSCO_LON_RAD = -1.2561   # -71.97 degrees W
LAT_LON_TOLERANCE_RAD = 0.05
TARGET_JD = 2250819       # June 21, 1450
JD_TOLERANCE = 30         # +/- 30 days


def verify_inca_dark_constellations(traj, env_info, task_info):
    """Verify Inca dark constellations task configuration and outputs."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "inca_dark_constellations"

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

        # ── Criterion 1: Location Accuracy (15 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - CUSCO_LAT_RAD)
            lon_diff = abs(lon_rad - CUSCO_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 15
                subscores["location"] = True
                feedback_parts.append("Location successfully set to Cusco")
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Location mismatch: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° (Expected ~-13.53°, ~-71.97°)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Historical Date (10 pts) ─────────────
        preset_sky_time = result.get('preset_sky_time')
        date_ok = False
        notes_content = result.get('notes_content', '').lower()
        
        # Check config JD
        if preset_sky_time is not None:
            if abs(preset_sky_time - TARGET_JD) <= JD_TOLERANCE:
                date_ok = True
                feedback_parts.append("Historical date (1450) saved in settings")
        
        # Fallback: check if 1450 is strongly referenced in notes, as Stellarium time saving is finicky
        if not date_ok and "1450" in notes_content:
            date_ok = True
            feedback_parts.append("Historical date (1450) documented in notes")

        if date_ok:
            score += 10
            subscores["date"] = True
        else:
            subscores["date"] = False
            feedback_parts.append("Historical date (1450) not saved in config or mentioned in notes")

        # ── Criterion 3: Sky Culture (20 pts) ─────────────────────
        sky_culture = result.get('sky_culture', '').lower()
        if sky_culture == 'inca':
            score += 20
            subscores["sky_culture"] = True
            feedback_parts.append("Sky culture set to Inca")
        else:
            subscores["sky_culture"] = False
            feedback_parts.append(f"Sky culture not set to Inca (current: {sky_culture})")

        # ── Criterion 4: View Settings (15 pts) ─────────────────────────
        flag_atm = result.get('flag_atmosphere')
        flag_land = result.get('flag_landscape')
        view_score = 0
        if flag_atm is False:
            view_score += 7.5
        if flag_land is False:
            view_score += 7.5
            
        score += int(view_score)
        subscores["view_settings"] = view_score == 15
        
        if view_score == 15:
            feedback_parts.append("Atmosphere and landscape disabled correctly")
        else:
            feedback_parts.append(f"View settings partial/incorrect (Atmosphere: {flag_atm}, Landscape: {flag_land})")

        # ── Criterion 5: Cultural Rendering (15 pts) ───────────────────────
        flag_art = result.get('flag_constellation_art')
        mw_intensity = result.get('milky_way_intensity', 1.0)
        
        rend_score = 0
        if flag_art is True:
            rend_score += 7.5
        if mw_intensity is not None and mw_intensity >= 3.9: # slight float tolerance
            rend_score += 7.5
            
        score += int(rend_score)
        subscores["rendering"] = rend_score == 15
        
        if rend_score == 15:
            feedback_parts.append(f"Art enabled and Milky Way enhanced (intensity={mw_intensity})")
        else:
            feedback_parts.append(f"Rendering settings partial/incorrect (Art: {flag_art}, MW_intensity: {mw_intensity})")

        # ── Criterion 6: Screenshot Capture (10 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 10
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} screenshot(s) captured")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 7: Lecture Notes (15 pts) ────────────────────────────
        notes_exists = result.get('notes_exists', False)
        if notes_exists:
            content = notes_content
            keywords_met = 0
            
            if "cusco" in content or "cuzco" in content or "peru" in content:
                keywords_met += 1
            if "inca" in content or "incan" in content:
                keywords_met += 1
            if "dark" in content:
                keywords_met += 1
            if "alpha centauri" in content or "llama" in content or "yacana" in content:
                keywords_met += 1
                
            if keywords_met >= 3:
                score += 15
                subscores["notes"] = True
                feedback_parts.append("Lecture notes file complete")
            elif keywords_met > 0:
                score += 5
                subscores["notes"] = False
                feedback_parts.append("Lecture notes file missing some required details")
            else:
                subscores["notes"] = False
                feedback_parts.append("Lecture notes file lacks relevant content")
        else:
            subscores["notes"] = False
            feedback_parts.append("Lecture notes file not found")

        # ── Final Evaluation ────────────────────────────────────────────────
        passed = score >= 70 and subscores.get("sky_culture", False) and notes_exists

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
            "feedback": f"Verification encountered an error: {e}"
        }