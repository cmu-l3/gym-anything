#!/usr/bin/env python3
"""
Verifier for urban_canyon_high_passes task.

Task:
  1. Create Manhattan_Urban.qth (40.7580 N, 73.9855 W, 50m)
  2. Set Manhattan_Urban as default QTH in global preferences.
  3. Delete legacy Pittsburgh.qth and Amateur.mod
  4. Create High_Passes.mod
  5. Add satellites: SO-50 (27607), AO-73 (39444), AO-85 (40967), ISS (25544)
  6. Assign Manhattan_Urban.qth to High_Passes.mod
  7. Set Global Minimum Elevation to 45 degrees.

Scoring (100 points, pass >= 70 WITH min elevation = 45):
  - Manhattan QTH Creation (lat/lon/alt): 20 pts
  - Default QTH Update: 10 pts
  - Legacy Cleanup (deleted Pittsburgh & Amateur): 15 pts
  - Module Creation + 4 Sats: 20 pts
  - Module QTH Binding: 10 pts
  - Global Min Elevation set to 45: 25 pts
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_urban_canyon_high_passes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('manhattan_lat', 40.7580)
    expected_lon = metadata.get('manhattan_lon', -73.9855)
    expected_alt = metadata.get('manhattan_alt', 50)
    expected_min_el = metadata.get('min_elevation', 45)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/urban_canyon_high_passes_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)

    except (json.JSONDecodeError, FileNotFoundError) as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    
    # 1. Manhattan QTH Creation (20 pts)
    if result.get('manhattan_exists'):
        lat_ok = _close_enough(result.get('manhattan_lat', ''), expected_lat, 0.1)
        lon_ok = _close_enough(result.get('manhattan_lon', ''), expected_lon, 0.1)
        alt_ok = _close_enough(result.get('manhattan_alt', ''), expected_alt, 10)

        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Manhattan QTH correct")
        elif lat_ok and lon_ok:
            score += 15
            feedback_parts.append("Manhattan QTH coordinates OK, altitude wrong")
        else:
            score += 5
            feedback_parts.append("Manhattan QTH exists, but coordinates are off")
    else:
        feedback_parts.append("Manhattan QTH NOT FOUND")

    # 2. Default QTH Update (10 pts)
    cfg_content = result.get('gpredict_cfg_content', '')
    if re.search(r'DEFAULT_QTH=Manhattan_Urban\.qth', cfg_content, re.IGNORECASE):
        score += 10
        feedback_parts.append("Global default QTH updated to Manhattan_Urban")
    else:
        feedback_parts.append("Global default QTH NOT updated to Manhattan_Urban")

    # 3. Legacy Cleanup (15 pts)
    if not result.get('pittsburgh_exists') and not result.get('amateur_mod_exists'):
        score += 15
        feedback_parts.append("Legacy configs successfully deleted")
    else:
        if result.get('pittsburgh_exists'):
            feedback_parts.append("Pittsburgh.qth was NOT deleted")
        if result.get('amateur_mod_exists'):
            feedback_parts.append("Amateur.mod was NOT deleted")

    # 4. Module Creation + Sats (20 pts, 5 per sat)
    if result.get('high_passes_exists'):
        feedback_parts.append("High_Passes module exists")
        sat_count = sum([
            result.get('hp_has_so50', False),
            result.get('hp_has_ao73', False),
            result.get('hp_has_ao85', False),
            result.get('hp_has_iss', False)
        ])
        score += (sat_count * 5)
        if sat_count == 4:
            feedback_parts.append("High_Passes contains all 4 required satellites")
        else:
            feedback_parts.append(f"High_Passes contains {sat_count}/4 required satellites")
    else:
        feedback_parts.append("High_Passes module NOT FOUND")

    # 5. Module QTH Binding (10 pts)
    qthfile = result.get('high_passes_qthfile', '')
    if 'manhattan' in qthfile.lower():
        score += 10
        feedback_parts.append("High_Passes properly bound to Manhattan_Urban QTH")
    else:
        if result.get('high_passes_exists'):
            feedback_parts.append(f"High_Passes QTH binding is wrong: '{qthfile}'")

    # 6. Global Min Elevation (25 pts) - CRITICAL
    min_el_set = False
    # Look for MIN_EL=45 or min_el = 45 in the config string
    if re.search(r'MIN_EL\s*=\s*45', cfg_content, re.IGNORECASE):
        min_el_set = True
        score += 25
        feedback_parts.append("Global Min Elevation set to 45 degrees")
    else:
        # Check if they set it to something close or didn't set it
        match = re.search(r'MIN_EL\s*=\s*(\d+)', cfg_content, re.IGNORECASE)
        if match:
            feedback_parts.append(f"Global Min Elevation set to {match.group(1)} (expected 45)")
        else:
            feedback_parts.append("Global Min Elevation parameter not found / not updated")

    # Determine if passed
    # Must meet 70 point threshold AND have the critical min elevation successfully set
    passed = score >= 70 and min_el_set

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }