#!/usr/bin/env python3
"""
Verifier for ilrs_laser_ranging_setup task.

Verification Strategy:
  1. Matera SLR QTH: Correct Lat (40.6496), Lon (16.7046), Alt (536). (15 points)
  2. Yarragadee SLR QTH: Correct Lat (-29.0465 - MUST be negative!), Lon (115.347), Alt (248). (20 points)
  3. ILRS_Targets Module exists. (10 points)
  4. ILRS_Targets Module contains 5 specific geodetic sats. (25 points total, 5 per sat)
  5. Minimum Elevation parameter set to 30. (20 points)
  6. Metric Units enabled. (10 points)

Pass threshold: 75 points. The agent must successfully recognize and apply the Southern Hemisphere parameter (Yarragadee negative latitude) and enforce the laser elevation constraint.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    """Safely cast string to float and check tolerance."""
    try:
        if value_str == "" or value_str is None:
            return False
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_ilrs_laser_ranging_setup(traj, env_info, task_info):
    """
    Evaluates the JSON payload exported from the GPredict container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    # Defaults from metadata config if available
    expected_matera_lat = metadata.get('matera_lat', 40.6496)
    expected_matera_lon = metadata.get('matera_lon', 16.7046)
    expected_yarr_lat = metadata.get('yarragadee_lat', -29.0465)
    expected_yarr_lon = metadata.get('yarragadee_lon', 115.347)
    expected_min_el = metadata.get('min_elevation', 30)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/ilrs_laser_ranging_setup_result.json", temp_path)
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
    
    # 1. Matera Ground Station (15 pts)
    if result.get('matera_exists'):
        lat_ok = _close_enough(result.get('matera_lat'), expected_matera_lat, 0.1)
        lon_ok = _close_enough(result.get('matera_lon'), expected_matera_lon, 0.1)
        
        if lat_ok and lon_ok:
            score += 15
            feedback_parts.append("Matera ground station created correctly")
        else:
            score += 5
            feedback_parts.append(f"Matera coordinates incorrect (Lat: {result.get('matera_lat')}, Lon: {result.get('matera_lon')})")
    else:
        feedback_parts.append("Matera ground station NOT found")

    # 2. Yarragadee Ground Station (20 pts) -> Strict Negative Check
    yarragadee_is_negative = False
    if result.get('yarragadee_exists'):
        raw_lat = result.get('yarragadee_lat', '')
        raw_lon = result.get('yarragadee_lon', '')
        
        # Determine if they successfully applied the Southern hemisphere correctly
        yarragadee_is_negative = raw_lat.startswith('-') or _close_enough(raw_lat, expected_yarr_lat, 0.1)
        lon_ok = _close_enough(raw_lon, expected_yarr_lon, 0.1)

        if yarragadee_is_negative and lon_ok:
            score += 20
            feedback_parts.append("Yarragadee ground station created correctly (properly handling Southern Hemisphere)")
        elif not yarragadee_is_negative and lon_ok:
            # They put it in the Northern Hemisphere
            score += 5
            feedback_parts.append("WARNING: Yarragadee latitude is POSITIVE. Failed to handle Southern Hemisphere parameter.")
        else:
            score += 5
            feedback_parts.append(f"Yarragadee coordinates incorrect (Lat: {raw_lat}, Lon: {raw_lon})")
    else:
        feedback_parts.append("Yarragadee ground station NOT found")

    # 3. Module Existence (10 pts)
    if result.get('ilrs_exists'):
        score += 10
        feedback_parts.append("ILRS tracking module exists")
        
        # 4. Satellites (25 pts -> 5 per satellite)
        satellites_present = []
        satellites_missing = []
        
        checks = [
            ('ilrs_has_lageos1', 'LAGEOS-1 (8820)'),
            ('ilrs_has_lageos2', 'LAGEOS-2 (22195)'),
            ('ilrs_has_starlette', 'STARLETTE (7646)'),
            ('ilrs_has_stella', 'STELLA (22823)'),
            ('ilrs_has_lares', 'LARES (38077)')
        ]
        
        for key, name in checks:
            if result.get(key, False):
                score += 5
                satellites_present.append(name)
            else:
                satellites_missing.append(name)
                
        if satellites_present:
            feedback_parts.append(f"ILRS Module contains: {', '.join(satellites_present)}")
        if satellites_missing:
            feedback_parts.append(f"ILRS Module MISSING: {', '.join(satellites_missing)}")
            
    else:
        feedback_parts.append("ILRS tracking module NOT found")

    # 5. Min Elevation Parameter (20 pts)
    actual_min_el = result.get('min_el', '0')
    if _close_enough(actual_min_el, expected_min_el, 0.5):
        score += 20
        feedback_parts.append(f"Minimum elevation successfully constrained to {expected_min_el} degrees")
    else:
        feedback_parts.append(f"Minimum elevation is {actual_min_el} (expected {expected_min_el})")

    # 6. Metric Units (10 pts)
    if result.get('metric_units_enabled'):
        score += 10
        feedback_parts.append("Metric units successfully enabled")
    else:
        feedback_parts.append("Metric units NOT enabled")

    # Define Passing constraints
    # - Must reach total score threshold
    # - Must have correctly created Yarragadee with negative latitude
    # - Must have constrained the minimum elevation
    passed = score >= 75 and yarragadee_is_negative

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }