#!/usr/bin/env python3
"""
Verifier for eddington_eclipse_1919 task.

Scoring (100 points):
- Geographic Location (~1.66° N, ~7.40° E): 20 pts
- Historical Date & Time (JD near 2422114.1): 20 pts
- Display Configuration (atmosphere OFF, landscape OFF, star names ON, constellation drawing ON): 20 pts
- Visual Evidence (1+ screenshots): 20 pts
- Expedition Report (Contains required keywords): 20 pts

Pass threshold: 70 points with Date & Time and Expedition Report substantially met.
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Príncipe ground truth coordinates
PRINCIPE_LAT_RAD = 1.66 * math.pi / 180.0
PRINCIPE_LON_RAD = 7.40 * math.pi / 180.0
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees tolerance

# May 29, 1919 14:15 UTC
JD_MIN = 2422114.05
JD_MAX = 2422114.15

def verify_eddington_eclipse_1919(traj, env_info, task_info):
    """Verify historical eclipse reconstruction task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "eddington_eclipse_1919"

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
            if abs(lat_rad - PRINCIPE_LAT_RAD) <= LAT_LON_TOLERANCE_RAD and abs(lon_rad - PRINCIPE_LON_RAD) <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(f"Location set to Príncipe (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                subscores["location"] = False
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°")
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # 2. Historical Date & Time (20 pts)
        jd = result.get('preset_sky_time')
        if jd is not None:
            if JD_MIN <= jd <= JD_MAX:
                score += 20
                subscores["date_time"] = True
                feedback_parts.append("Date/time correctly set to May 29, 1919 totality window")
            else:
                subscores["date_time"] = False
                feedback_parts.append(f"Wrong date/time (JD: {jd:.2f}, expected ~2422114.1)")
        else:
            subscores["date_time"] = False
            feedback_parts.append("Date/time not found in config")

        # 3. Display Configuration (20 pts)
        disp_score = 0
        if result.get('flag_atmosphere') is False: disp_score += 5
        if result.get('flag_landscape') is False: disp_score += 5
        if result.get('flag_star_name') is True: disp_score += 5
        if result.get('flag_constellation_drawing') is True: disp_score += 5
        
        score += disp_score
        subscores["display"] = (disp_score == 20)
        feedback_parts.append(f"Display config: {disp_score}/20 pts")

        # 4. Visual Evidence (20 pts)
        if result.get('new_screenshot_count', 0) >= 1:
            score += 20
            subscores["screenshot"] = True
            feedback_parts.append("Screenshot captured")
        else:
            subscores["screenshot"] = False
            feedback_parts.append("No screenshot found")

        # 5. Expedition Report (20 pts)
        if result.get('report_exists'):
            content = result.get('report_content', '').lower()
            keywords_found = 0
            if '1919' in content: 
                keywords_found += 1
            if 'principe' in content or 'príncipe' in content: 
                keywords_found += 1
            if 'taurus' in content: 
                keywords_found += 1
            if 'aldebaran' in content or 'hyades' in content: 
                keywords_found += 1
            
            report_score = keywords_found * 5
            score += report_score
            subscores["report"] = (report_score == 20)
            feedback_parts.append(f"Report check: {report_score}/20 pts")
        else:
            subscores["report"] = False
            feedback_parts.append("Report file not found")

        # Pass criteria: score >= 70, must have time setting mostly correct and some report output
        passed = score >= 70 and subscores.get("date_time", False) and (subscores.get("report", False) or result.get('report_exists'))
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}