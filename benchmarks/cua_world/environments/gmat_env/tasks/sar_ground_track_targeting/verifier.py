#!/usr/bin/env python3
"""
Verifier for sar_ground_track_targeting@1

Scoring (total 100 pts, pass >= 70):
  - script_modified (10): Script was created/modified during task
  - report_exists (10): Analysis report written
  - latitude_achieved (20): Final latitude is 40.0 +/- 0.05
  - longitude_achieved (30): Final longitude is -75.0 +/- 0.05
  - deltav_valid (30): Maneuver DV is non-zero and within [-50, 50] m/s

Pass condition: score >= 70 AND longitude_achieved AND deltav_valid
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sar_ground_track_targeting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_latitude', 40.0)
    target_lon = metadata.get('target_longitude', -75.0)
    lat_tol = metadata.get('latitude_tolerance', 0.05)
    lon_tol = metadata.get('longitude_tolerance', 0.05)
    max_dv = metadata.get('max_dv_mps', 50.0)

    scores = {
        "script_modified": 10,
        "report_exists": 10,
        "latitude_achieved": 20,
        "longitude_achieved": 30,
        "deltav_valid": 30,
    }

    total_score = 0
    feedback = []
    lon_ok = False
    dv_ok = False

    # Load task result JSON
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

    # 1. Check script
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_modified"]
        feedback.append("Script saved/modified during task window.")
        
        # Check if DC was used in script
        if task_result.get('dc_used_in_script'):
            feedback.append("DifferentialCorrector sequence detected in script.")
        else:
            feedback.append("WARNING: DifferentialCorrector not detected in script.")
    else:
        feedback.append("Script not saved/modified during task window.")

    # 2. Check report
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('created_during_task'):
        total_score += scores["report_exists"]
        feedback.append("Overflight report created.")
    else:
        feedback.append("Overflight report not created or modified during task.")

    # 3. Parse and validate report values
    try:
        lat_val = float(task_result.get('final_latitude_deg', 0))
    except (ValueError, TypeError):
        lat_val = -999.0

    try:
        lon_val = float(task_result.get('final_longitude_deg', 0))
    except (ValueError, TypeError):
        lon_val = -999.0

    try:
        dv_val = float(task_result.get('maneuver_dv_m_s', 0))
    except (ValueError, TypeError):
        dv_val = 0.0

    # Evaluate Latitude
    if abs(lat_val - target_lat) <= lat_tol:
        total_score += scores["latitude_achieved"]
        feedback.append(f"Latitude achieved: {lat_val:.3f} deg (Target: {target_lat}).")
    else:
        feedback.append(f"Latitude incorrect: {lat_val:.3f} deg (Target: {target_lat}).")

    # Evaluate Longitude
    if abs(lon_val - target_lon) <= lon_tol:
        total_score += scores["longitude_achieved"]
        lon_ok = True
        feedback.append(f"Longitude achieved: {lon_val:.3f} deg (Target: {target_lon}).")
    else:
        feedback.append(f"Longitude incorrect: {lon_val:.3f} deg (Target: {target_lon}).")

    # Evaluate DeltaV
    # Delta-V must be non-zero (greater than 0.0001) but physically realistic (<= 50 m/s)
    abs_dv = abs(dv_val)
    if 0.0001 < abs_dv <= max_dv:
        total_score += scores["deltav_valid"]
        dv_ok = True
        feedback.append(f"DeltaV is physically realistic: {dv_val:.4f} m/s.")
    elif abs_dv > max_dv:
        feedback.append(f"DeltaV too large/incorrect unit: {dv_val:.4f} m/s (Expected <= {max_dv} m/s).")
    else:
        feedback.append(f"DeltaV is zero or near-zero: {dv_val:.4f} m/s.")

    # Final pass conditions
    passed = (total_score >= 70) and lon_ok and dv_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "reported_latitude": lat_val,
            "reported_longitude": lon_val,
            "reported_dv": dv_val
        }
    }