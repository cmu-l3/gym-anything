#!/usr/bin/env python3
"""
Verifier for aviation_twilight_logging task.

Scoring (100 points):
- Location Configured (Anchorage, AK) - 15 points
- Display Configured (Atmosphere OFF, Landscape OFF) - 15 points
- Documentation Screenshots (>= 2 screenshots taken) - 15 points
- Log File Present (created during task, contains PANC) - 15 points
- Evening Twilight Time Correct (02:10 UTC +/- 5 mins) - 20 points
- Morning Twilight Time Correct (17:08 UTC +/- 5 mins) - 20 points

Pass threshold: 75 points
"""

import json
import tempfile
import os
import math
import re
import logging

logger = logging.getLogger(__name__)

# Anchorage, AK Target Info
TARGET_LAT_RAD = 1.0677
TARGET_LON_RAD = -2.6179
LAT_LON_TOLERANCE_RAD = 0.05

# Time Targets
# Evening ~02:10 (02:05 to 02:15)
EVENING_MINS_MIN = 2 * 60 + 5
EVENING_MINS_MAX = 2 * 60 + 15

# Morning ~17:08 (17:03 to 17:13)
MORNING_MINS_MIN = 17 * 60 + 3
MORNING_MINS_MAX = 17 * 60 + 13

def verify_aviation_twilight_logging(traj, env_info, task_info):
    """
    Verify the aviation twilight logging task metrics and values.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "aviation_twilight_logging"

    try:
        # Securely copy result JSON out of the container
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
        
        # 1. Evaluate Location (15 points)
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - TARGET_LAT_RAD)
            lon_diff = abs(lon_rad - TARGET_LON_RAD)
            
            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 15
                feedback_parts.append(f"Location set correctly to Anchorage (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°")
        else:
            feedback_parts.append("Location state not found in config")

        # 2. Evaluate Display State (15 points)
        flag_atm = result.get('flag_atmosphere')
        flag_land = result.get('flag_landscape')
        
        if flag_atm is False and flag_land is False:
            score += 15
            feedback_parts.append("Atmosphere and Landscape correctly disabled")
        else:
            feedback_parts.append(f"Display settings incorrect: Atmosphere={flag_atm}, Landscape={flag_land} (both should be False)")

        # 3. Evaluate Screenshot creation (15 points)
        new_ss_count = result.get('new_screenshot_count', 0)
        if new_ss_count >= 2:
            score += 15
            feedback_parts.append(f"{new_ss_count} screenshots captured")
        elif new_ss_count == 1:
            score += 7
            feedback_parts.append("Only 1 screenshot captured (expected 2)")
        else:
            feedback_parts.append("No screenshots captured")

        # 4. Evaluate Log File Integrity (15 points)
        log_exists = result.get('log_exists', False)
        log_mod = result.get('log_modified_during_task', False)
        log_text = result.get('log_content', '')

        if log_exists and log_mod:
            if re.search(r'anchorage|panc', log_text, re.IGNORECASE):
                score += 15
                feedback_parts.append("Log file exists, was created during task, and mentions Anchorage/PANC")
            else:
                score += 8
                feedback_parts.append("Log file exists but missing Anchorage/PANC mention")
        else:
            feedback_parts.append("Log file missing or not modified during task")

        # 5. Evaluate Twilight Calculations (20 + 20 points)
        # Extract all HH:MM formats from the text document
        found_evening = False
        found_morning = False
        
        time_matches = re.findall(r'\b([0-2]?[0-9]):([0-5][0-9])\b', log_text)
        
        for h_str, m_str in time_matches:
            time_mins = int(h_str) * 60 + int(m_str)
            
            if EVENING_MINS_MIN <= time_mins <= EVENING_MINS_MAX:
                found_evening = True
                
            if MORNING_MINS_MIN <= time_mins <= MORNING_MINS_MAX:
                found_morning = True

        if found_evening:
            score += 20
            feedback_parts.append("Correct Evening Twilight time logged (~02:10 UTC)")
        else:
            feedback_parts.append("Correct Evening Twilight time not found in log (Expected ~02:10 UTC)")

        if found_morning:
            score += 20
            feedback_parts.append("Correct Morning Twilight time logged (~17:08 UTC)")
        else:
            feedback_parts.append("Correct Morning Twilight time not found in log (Expected ~17:08 UTC)")

        # Final Verification Determination
        # Agent must at least succeed in the threshold and successfully find one of the times
        key_criteria_met = (found_evening or found_morning) and log_exists
        passed = score >= 75 and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification script error: {str(e)}"
        }