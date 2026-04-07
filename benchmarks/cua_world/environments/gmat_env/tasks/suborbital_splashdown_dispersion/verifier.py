#!/usr/bin/env python3
"""
Verifier for suborbital_splashdown_dispersion@1

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script created during task window
  - earth_fixed_frame (15): EarthFixed/BodyFixed used in script
  - drag_modeled (10): Drag included in script
  - stopping_condition (15): Altitude = 0 (or < 1) used for stopping
  - report_formatted (10): Report contains all 3 cases
  - nominal_lat_valid (15): Case 1 Latitude is [25.0, 36.0]
  - nominal_lon_valid (15): Case 1 Longitude is [-73.0, -60.0] or [287.0, 300.0]
  - tof_valid (10): Case 1 TOF is [5.0, 25.0]

Pass condition: score >= 70 AND at least one valid coordinate (lat or lon)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_suborbital_splashdown_dispersion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    lat_min = metadata.get('lat_min', 25.0)
    lat_max = metadata.get('lat_max', 36.0)
    lon_min = metadata.get('lon_min', -73.0)
    lon_max = metadata.get('lon_max', -60.0)
    lon_min_e = metadata.get('lon_min_east', 287.0)
    lon_max_e = metadata.get('lon_max_east', 300.0)
    tof_min = metadata.get('tof_min', 5.0)
    tof_max = metadata.get('tof_max', 25.0)

    scores = {
        "script_created": 10,
        "earth_fixed_frame": 15,
        "drag_modeled": 10,
        "stopping_condition": 15,
        "report_formatted": 10,
        "nominal_lat_valid": 15,
        "nominal_lon_valid": 15,
        "tof_valid": 10,
    }

    total_score = 0
    feedback = []
    lat_ok = False
    lon_ok = False

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Analyze script content
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/splashdown_sim.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
            
            # Check EarthFixed or BodyFixed
            if re.search(r'EarthFixed|BodyFixed', script_content, re.IGNORECASE):
                total_score += scores["earth_fixed_frame"]
                feedback.append("EarthFixed/BodyFixed frame found in script.")
            else:
                feedback.append("EarthFixed/BodyFixed frame NOT found in script.")
                
            # Check drag
            if re.search(r'AtmosphereModel|Drag', script_content, re.IGNORECASE):
                total_score += scores["drag_modeled"]
                feedback.append("Atmospheric drag configured.")
            else:
                feedback.append("Atmospheric drag NOT found.")
                
            # Check stopping condition (Altitude = 0 or similar)
            if re.search(r'\.Altitude\s*<|Altitude\s*=\s*[0-1]', script_content, re.IGNORECASE):
                total_score += scores["stopping_condition"]
                feedback.append("Altitude stopping condition found.")
            else:
                feedback.append("Altitude stopping condition NOT found.")
                
        except Exception as e:
            feedback.append(f"Error analyzing script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Report format and cases
    has_case2 = task_result.get('has_case2', False)
    has_case3 = task_result.get('has_case3', False)
    
    if has_case2 and has_case3:
        total_score += scores["report_formatted"]
        feedback.append("Report contains all 3 cases.")
    else:
        feedback.append("Report missing Case 2 and/or Case 3.")

    # 4. Extract values
    try:
        case1_lat = float(task_result.get('case1_lat', 0))
    except (ValueError, TypeError):
        case1_lat = 0.0
        
    try:
        case1_lon = float(task_result.get('case1_lon', 0))
    except (ValueError, TypeError):
        case1_lon = 0.0
        
    try:
        case1_tof = float(task_result.get('case1_tof', 0))
    except (ValueError, TypeError):
        case1_tof = 0.0

    # 5. Verify latitude
    if lat_min <= case1_lat <= lat_max:
        total_score += scores["nominal_lat_valid"]
        lat_ok = True
        feedback.append(f"Case 1 Latitude valid: {case1_lat} (expected [{lat_min}, {lat_max}]).")
    else:
        feedback.append(f"Case 1 Latitude invalid: {case1_lat} (expected [{lat_min}, {lat_max}]).")

    # 6. Verify longitude
    lon_is_valid = (lon_min <= case1_lon <= lon_max) or (lon_min_e <= case1_lon <= lon_max_e)
    if lon_is_valid:
        total_score += scores["nominal_lon_valid"]
        lon_ok = True
        feedback.append(f"Case 1 Longitude valid: {case1_lon}.")
    else:
        feedback.append(f"Case 1 Longitude invalid: {case1_lon}.")

    # 7. Verify TOF
    if tof_min <= case1_tof <= tof_max:
        total_score += scores["tof_valid"]
        feedback.append(f"Case 1 Time of Flight valid: {case1_tof} min (expected [{tof_min}, {tof_max}]).")
    else:
        feedback.append(f"Case 1 Time of Flight invalid: {case1_tof} min (expected [{tof_min}, {tof_max}]).")

    passed = (total_score >= 70) and (lat_ok or lon_ok)
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }