#!/usr/bin/env python3
"""
Verifier for config_audit_cleanup task.

Task: Audit and correct a messy GPredict configuration:
  1. Delete Bogus_Test ground station
  2. Correct Houston altitude to 14m (keep Lat/Lon intact)
  3. Clean Research.mod: keep ISS (25544, 36086, 49044), remove weather (37849, 32958)
  4. Delete Old_Demo module
  5. Add Svalbard ground station (78.2297N, 15.3888E, 458m)
  6. Set Svalbard as default ground station
  7. Leave Amateur.mod alone

Scoring (100 points, pass >= 60):
  - Bogus_Test deleted: 10 pts
  - Houston altitude corrected (14m): 15 pts
  - Houston other fields intact: 5 pts
  - Research.mod weather sats removed (2): 15 pts (7.5 each)
  - Research.mod ISS sats retained (3): 15 pts (5 each)
  - Old_Demo deleted: 10 pts
  - Svalbard station created (coords correct): 15 pts (10 for existence/approx, 5 for exact+alt)
  - Default QTH set to Svalbard: 10 pts
  - Amateur.mod exists/untouched: 5 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_config_audit_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/config_audit_cleanup_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

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

    # 1. Bogus_Test deleted (10 pts)
    if not result.get('bogus_exists', True):
        score += 10
        feedback_parts.append("Bogus_Test.qth deleted")
    else:
        feedback_parts.append("Bogus_Test.qth still exists")

    # 2. Houston corrected (15 pts alt, 5 pts intact lat/lon)
    if result.get('houston_exists', False):
        alt_str = result.get('houston_alt', '')
        if _close_enough(alt_str, 14, 2):
            score += 15
            feedback_parts.append("Houston altitude corrected to 14m")
        else:
            feedback_parts.append(f"Houston altitude incorrect ({alt_str}m, expected 14m)")

        lat_ok = _close_enough(result.get('houston_lat', ''), 29.5502, 0.05)
        lon_ok = _close_enough(result.get('houston_lon', ''), -95.0970, 0.05)
        if lat_ok and lon_ok:
            score += 5
            feedback_parts.append("Houston lat/lon kept intact")
        else:
            feedback_parts.append("Houston lat/lon were erroneously changed")
    else:
        feedback_parts.append("Houston.qth was erroneously deleted")

    # 3. Research.mod cleaned (15 pts removal, 15 pts retention)
    if result.get('research_exists', False):
        sats = result.get('research_sats', '')
        
        # Weather sats removed
        weather_removed = 0
        if "37849" not in sats: weather_removed += 1
        if "32958" not in sats: weather_removed += 1
        score += int(weather_removed * 7.5) # 7 or 15
        if weather_removed == 2:
            feedback_parts.append("Weather satellites correctly removed from Research.mod")
        elif weather_removed == 1:
            feedback_parts.append("1 of 2 weather satellites removed from Research.mod")
        else:
            feedback_parts.append("Weather satellites still present in Research.mod")

        # ISS sats retained
        iss_retained = 0
        for norad in ["25544", "36086", "49044"]:
            if norad in sats:
                iss_retained += 1
        score += (iss_retained * 5)
        if iss_retained == 3:
            feedback_parts.append("All 3 ISS satellites correctly retained in Research.mod")
        else:
            feedback_parts.append(f"Only {iss_retained}/3 ISS satellites retained in Research.mod")
    else:
        feedback_parts.append("Research.mod was erroneously deleted (lost 30 pts)")

    # 4. Old_Demo deleted (10 pts)
    if not result.get('old_demo_exists', True):
        score += 10
        feedback_parts.append("Old_Demo.mod deleted")
    else:
        feedback_parts.append("Old_Demo.mod still exists")

    # 5. Svalbard created (15 pts)
    if result.get('svalbard_exists', False):
        lat_ok = _close_enough(result.get('svalbard_lat', ''), 78.2297, 0.1)
        lon_ok = _close_enough(result.get('svalbard_lon', ''), 15.3888, 0.1)
        alt_ok = _close_enough(result.get('svalbard_alt', ''), 458, 20)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Svalbard station perfectly configured")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append(f"Svalbard coordinates OK, but alt off ({result.get('svalbard_alt')}m)")
        else:
            score += 5
            feedback_parts.append("Svalbard station exists but coordinates are significantly wrong")
    else:
        feedback_parts.append("Svalbard station not created")

    # 6. Default QTH (10 pts)
    default_qth = result.get('default_qth', '').lower()
    if 'svalbard' in default_qth:
        score += 10
        feedback_parts.append("Default QTH set to Svalbard")
    else:
        feedback_parts.append(f"Default QTH not set to Svalbard (current: {default_qth})")

    # 7. Amateur.mod exists (5 pts)
    if result.get('amateur_exists', False):
        score += 5
        feedback_parts.append("Amateur.mod properly retained")
    else:
        feedback_parts.append("Amateur.mod was erroneously deleted")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }