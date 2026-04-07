#!/usr/bin/env python3
"""
Verifier for geo_weather_ring_setup task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    """Safely compare string-encoded float coordinates."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_geo_weather_ring_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env("/tmp/geo_weather_ring_setup_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    # 1. Ground Stations (30 pts, 10 pts each)
    # Wallops Island
    if result.get('wallops_exists'):
        lat_ok = _close_enough(result.get('wallops_lat'), metadata.get('wallops_lat', 37.94), 0.1)
        lon_ok = _close_enough(result.get('wallops_lon'), metadata.get('wallops_lon', -75.46), 0.1)
        if lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Wallops Island QTH correct")
        else:
            score += 5
            feedback_parts.append(f"Wallops Island QTH found but coordinates off (Lat: {result.get('wallops_lat')}, Lon: {result.get('wallops_lon')})")
    else:
        feedback_parts.append("Wallops Island QTH missing")

    # Darmstadt
    if result.get('darmstadt_exists'):
        lat_ok = _close_enough(result.get('darmstadt_lat'), metadata.get('darmstadt_lat', 49.87), 0.1)
        lon_ok = _close_enough(result.get('darmstadt_lon'), metadata.get('darmstadt_lon', 8.65), 0.1)
        if lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Darmstadt QTH correct")
        else:
            score += 5
            feedback_parts.append(f"Darmstadt QTH found but coordinates off (Lat: {result.get('darmstadt_lat')}, Lon: {result.get('darmstadt_lon')})")
    else:
        feedback_parts.append("Darmstadt QTH missing")

    # Melbourne
    if result.get('melbourne_exists'):
        lat_str = result.get('melbourne_lat', '')
        # Determine if the hemisphere dropdown was used correctly (translates to negative Lat)
        try:
            is_south = float(lat_str) < 0
        except:
            is_south = False
            
        lat_ok = _close_enough(lat_str, metadata.get('melbourne_lat', -37.81), 0.1)
        lon_ok = _close_enough(result.get('melbourne_lon'), metadata.get('melbourne_lon', 144.96), 0.1)
        
        if lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Melbourne QTH correct (South hemisphere handled properly)")
        elif lon_ok and not is_south:
            score += 5
            feedback_parts.append("Melbourne QTH exists but Latitude was left as North instead of South!")
        else:
            score += 5
            feedback_parts.append(f"Melbourne QTH found but coordinates off (Lat: {result.get('melbourne_lat')}, Lon: {result.get('melbourne_lon')})")
    else:
        feedback_parts.append("Melbourne QTH missing")

    # 2. GEO Weather Module (20 pts)
    geo_sats = metadata.get('geo_satellites', [41866, 51850, 40732, 41816])
    if result.get('geo_weather_exists'):
        sat_str = result.get('geo_weather_sats', '')
        found_sats = sum([1 for sat in geo_sats if str(sat) in sat_str])
        
        if found_sats == 4:
            score += 20
            feedback_parts.append("GEO_Weather module contains all 4 correct satellites")
        elif found_sats > 0:
            pts = found_sats * 5
            score += pts
            feedback_parts.append(f"GEO_Weather module missing some satellites ({found_sats}/4 found)")
        else:
            feedback_parts.append("GEO_Weather module exists but lacks the requested satellites")
    else:
        feedback_parts.append("GEO_Weather module missing")

    # 3. Module QTH Binding (20 pts)
    if result.get('geo_weather_exists') and result.get('wallops_exists'):
        bound_qth = result.get('geo_weather_qth', '').lower()
        wallops_name = result.get('wallops_qth_name', '').lower()
        
        # Ensure it actually bound properly, handling standard ".qth" extensions
        if bound_qth == wallops_name or 'wallops' in bound_qth:
            score += 20
            feedback_parts.append("GEO_Weather module successfully bound to Wallops Island QTH")
        else:
            feedback_parts.append(f"GEO_Weather module bound to '{bound_qth}' instead of Wallops Island")
    else:
        feedback_parts.append("Could not verify module QTH binding (GEO module or Wallops QTH missing)")

    # 4. Default QTH (15 pts)
    default_qth = result.get('default_qth', '').lower()
    darmstadt_name = result.get('darmstadt_qth_name', '').lower()
    if default_qth == darmstadt_name or 'darmstadt' in default_qth:
        score += 15
        feedback_parts.append("Global default QTH successfully changed to Darmstadt")
    else:
        feedback_parts.append(f"Global default QTH is '{default_qth}' (expected Darmstadt)")

    # 5. Delete Pittsburgh (15 pts)
    if not result.get('pittsburgh_exists'):
        score += 15
        feedback_parts.append("Pittsburgh QTH successfully deleted")
    else:
        feedback_parts.append("Pittsburgh QTH was not deleted")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }