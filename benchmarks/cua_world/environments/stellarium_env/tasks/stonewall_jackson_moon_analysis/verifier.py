#!/usr/bin/env python3
"""
Verifier for stonewall_jackson_moon_analysis task.

Scoring (100 points):
- Location set to Chancellorsville (Lat/Lon within 0.05 rad of 38.31°N, 77.636°W): 20 pts
- Time set to May 3, 1863 ~02:10 UTC (JD within 0.1 of 2401628.59): 20 pts
- Azimuthal grid enabled (flag_azimuthal_grid = true): 15 pts
- Atmosphere ON and Landscape ON (10 pts)
- 1+ screenshots taken: 15 pts
- Notes file written with phase (Full/Gibbous) and direction (Southeast): 20 pts

Pass threshold: 70 points, requiring location, time, and notes.
"""

import json
import tempfile
import os
import math
import re
import logging

logger = logging.getLogger(__name__)

# Ground truth values
EXPECTED_LAT_RAD = 0.6686   # 38.310 degrees N
EXPECTED_LON_RAD = -1.3550  # -77.636 degrees W
EXPECTED_JD = 2401628.59    # May 3, 1863 02:10 UTC
LAT_LON_TOLERANCE_RAD = 0.05
JD_TOLERANCE = 0.1

def verify_stonewall_moon_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "stonewall_jackson_moon_analysis"

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

        # ── Criterion 1: Location (20 pts) ───────────────────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - EXPECTED_LAT_RAD)
            lon_diff = abs(lon_rad - EXPECTED_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"Location correct (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~38.31°N, ~77.64°W)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Time / Julian Date (20 pts) ─────────────────────────
        preset_jd = result.get('preset_sky_time')
        if preset_jd is not None:
            jd_diff = abs(preset_jd - EXPECTED_JD)
            if jd_diff <= JD_TOLERANCE:
                score += 20
                subscores["time"] = True
                feedback_parts.append(f"Time correct (JD={preset_jd:.2f})")
            else:
                subscores["time"] = False
                feedback_parts.append(f"Wrong time: JD={preset_jd:.2f} (expected ~{EXPECTED_JD:.2f})")
        else:
            subscores["time"] = False
            feedback_parts.append("Simulation time not found in config")

        # ── Criterion 3: Azimuthal Grid (15 pts) ─────────────────────────────
        flag_azimuthal = result.get('flag_azimuthal_grid')
        if flag_azimuthal is True:
            score += 15
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append("Azimuthal grid not enabled")

        # ── Criterion 4: Atmosphere and Landscape ON (10 pts) ────────────────
        flag_atm = result.get('flag_atmosphere')
        flag_land = result.get('flag_landscape')
        if flag_atm is True and flag_land is True:
            score += 10
            subscores["environment_settings"] = True
            feedback_parts.append("Atmosphere and Landscape enabled")
        else:
            subscores["environment_settings"] = False
            feedback_parts.append("Atmosphere or Landscape missing (need both enabled for realism)")

        # ── Criterion 5: Screenshots (15 pts) ────────────────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 15
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} screenshot(s) captured")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 6: Research Notes Content (20 pts) ─────────────────────
        notes_exists = result.get('notes_exists', False)
        notes_content = result.get('notes_content', "")
        
        if notes_exists:
            has_phase = bool(re.search(r'(?i)\b(gibbous|full)\b', notes_content))
            has_direction = bool(re.search(r'(?i)\b(south[- ]?east|se)\b', notes_content))
            
            if has_phase and has_direction:
                score += 20
                subscores["notes"] = True
                feedback_parts.append("Research notes correctly document phase (Full/Gibbous) and direction (Southeast)")
            elif has_phase:
                score += 10
                subscores["notes"] = False
                feedback_parts.append("Notes have correct phase, missing correct direction (Southeast)")
            elif has_direction:
                score += 10
                subscores["notes"] = False
                feedback_parts.append("Notes have correct direction, missing correct phase (Full/Gibbous)")
            else:
                subscores["notes"] = False
                feedback_parts.append("Notes exist but missing expected phase/direction keywords")
        else:
            subscores["notes"] = False
            feedback_parts.append("Research notes file not found")

        # ── Final Assessment ─────────────────────────────────────────────────
        key_criteria_met = subscores["location"] and subscores["time"] and subscores["notes"]
        passed = (score >= 70) and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification failed with exception: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {str(e)}"}