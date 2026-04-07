#!/usr/bin/env python3
"""
Verifier for orbital_mechanics_lab_setup task.

Verification Metrics:
1. Amateur module deleted: 15 points
2. Crewed_Stations module correctly populated: 20 points
3. Polar_Weather module correctly populated: 30 points
4. MIT Ground Station correctly configured: 15 points
5. Minimum Elevation configured to 10 degrees: 10 points
6. UTC time display enabled: 10 points

Pass Threshold: 60 points (with Amateur deleted and at least one module generated)
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

def check_min_el(content):
    """Check if min elevation is set to 10 in GPredict config file."""
    if not content:
        return False
    # Matches min_el=10, MIN_EL=10, PRED_MIN_EL=10
    match = re.search(r'(?:MIN_EL|PRED_MIN_EL)\s*=\s*10', content, re.IGNORECASE)
    return bool(match)

def check_utc(content):
    """Check if UTC time display is enabled in GPredict config file."""
    if not content:
        return False
    return bool(re.search(r'utc\s*=\s*1', content, re.IGNORECASE) or 
                re.search(r'TIME_FORMAT\s*=\s*0', content, re.IGNORECASE) or
                re.search(r'USE_LOCAL_TIME\s*=\s*FALSE', content, re.IGNORECASE))

def verify_orbital_mechanics_lab(traj, env_info, task_info):
    """Verify that GPredict was properly reconfigured for the educational lab."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Extract JSON result safely
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/orbital_mechanics_lab_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    # 1. Check Amateur module deletion (15 pts)
    amateur_deleted = result.get('amateur_deleted', False)
    if amateur_deleted:
        score += 15
        feedback_parts.append("[PASS] Amateur module deleted")
    else:
        feedback_parts.append("[FAIL] Amateur module not deleted")

    # 2. Check Crewed_Stations module (20 pts, 10 per satellite)
    cs_exists = result.get('cs_exists', False)
    cs_sats = result.get('cs_sats', '')
    if cs_exists:
        if "25544" in cs_sats:
            score += 10
            feedback_parts.append("[PASS] ISS (25544) in Crewed_Stations")
        else:
            feedback_parts.append("[FAIL] ISS (25544) missing from Crewed_Stations")
            
        if "48274" in cs_sats:
            score += 10
            feedback_parts.append("[PASS] CSS TIANHE (48274) in Crewed_Stations")
        else:
            feedback_parts.append("[FAIL] CSS TIANHE (48274) missing from Crewed_Stations")
    else:
        feedback_parts.append("[FAIL] Crewed_Stations module not found")

    # 3. Check Polar_Weather module (30 pts, 10 per satellite)
    pw_exists = result.get('pw_exists', False)
    pw_sats = result.get('pw_sats', '')
    if pw_exists:
        for norad, name in [(33591, "NOAA 19"), (37849, "SUOMI NPP"), (37214, "FENGYUN 3B")]:
            if str(norad) in pw_sats:
                score += 10
                feedback_parts.append(f"[PASS] {name} ({norad}) in Polar_Weather")
            else:
                feedback_parts.append(f"[FAIL] {name} ({norad}) missing from Polar_Weather")
    else:
        feedback_parts.append("[FAIL] Polar_Weather module not found")

    # 4. Check MIT Ground Station (15 pts: 10 for coords, 5 for alt)
    if result.get('mit_exists', False):
        lat_ok = _close_enough(result.get('mit_lat', ''), metadata.get('mit_lat', 42.3601), 0.05)
        lon_ok = _close_enough(result.get('mit_lon', ''), metadata.get('mit_lon', -71.0942), 0.05)
        alt_ok = _close_enough(result.get('mit_alt', ''), metadata.get('mit_alt', 12), 5)
        
        if lat_ok and lon_ok:
            score += 10
            feedback_parts.append("[PASS] MIT Ground Station coordinates correct")
            if alt_ok:
                score += 5
                feedback_parts.append("[PASS] MIT Ground Station altitude correct")
            else:
                feedback_parts.append(f"[FAIL] MIT altitude incorrect ({result.get('mit_alt')}m)")
        else:
            feedback_parts.append(f"[FAIL] MIT coordinates incorrect (Lat: {result.get('mit_lat')}, Lon: {result.get('mit_lon')})")
    else:
        feedback_parts.append("[FAIL] MIT Ground Station not found")

    # 5. Check Minimum Elevation (10 pts)
    cfg_content = result.get('gpredict_cfg_content', '')
    if check_min_el(cfg_content):
        score += 10
        feedback_parts.append("[PASS] Minimum Elevation set to 10 degrees")
    else:
        feedback_parts.append("[FAIL] Minimum Elevation not set to 10 degrees")

    # 6. Check UTC time display (10 pts)
    if check_utc(cfg_content):
        score += 10
        feedback_parts.append("[PASS] UTC time display enabled")
    else:
        feedback_parts.append("[FAIL] UTC time display not enabled")

    # Determine final passage
    key_criteria_met = amateur_deleted and (cs_exists or pw_exists)
    passed = score >= 60 and key_criteria_met

    if not key_criteria_met:
        feedback_parts.append("[CRITICAL] Must delete Amateur module and create at least one new module to pass.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }