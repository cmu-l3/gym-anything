#!/usr/bin/env python3
"""
Verifier for RAS Kinematics Setup task.

This task is a math/physics word problem disguised as a configuration task.
The agent must calculate relative velocity to determine the geographic distance 
required for a fast ship to catch a slow ship.

Math Logic:
1. Approach Leg:
   - Ownship Speed (V_own) = 10 kts
   - Supply Speed (V_sup) = 14 kts
   - Initial Separation (D_sep) = 4 nm
   - Relative Speed (V_rel) = 14 - 10 = 4 kts
   - Time to close (T) = D_sep / V_rel = 4 / 4 = 1 hour
   - Geographic Distance (D_geo) = V_sup * T = 14 * 1 = 14.0 nm
   
2. Station Leg:
   - Speed = 10 kts
   - Time = 30 mins = 0.5 hours
   - Distance = 10 * 0.5 = 5.0 nm
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ras_kinematics_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Get metadata/expectations
    metadata = task_info.get('metadata', {})
    expected_app_dist = metadata.get('expected_approach_distance', 14.0)
    expected_sta_dist = metadata.get('expected_station_distance', 5.0)
    tolerance = metadata.get('tolerance', 0.2)

    score = 0
    feedback = []
    
    # 1. Check Scenario Structure (20 pts)
    if result.get('scenario_created') and result.get('files_exist', {}).get('othership') and result.get('files_exist', {}).get('ownship'):
        score += 20
        feedback.append("Scenario structure valid.")
    else:
        feedback.append("Scenario files missing.")
        return {"passed": False, "score": 0, "feedback": "Scenario not created."}

    # 2. Check Ownship Configuration (10 pts)
    try:
        own_speed = float(result.get('ownship_speed', 0))
        if abs(own_speed - 10.0) < 0.1:
            score += 10
            feedback.append("Ownship speed correct (10kts).")
        else:
            feedback.append(f"Ownship speed incorrect ({own_speed}kts).")
    except ValueError:
        feedback.append("Could not parse Ownship speed.")

    # 3. Check Supply Start Position (10 pts)
    try:
        start_lat = float(result.get('othership_start_lat', 0))
        # 4nm South of 50.00N. 1 deg = 60nm. 4nm = 4/60 deg = 0.0667 deg.
        # Target = 50.0 - 0.0667 = 49.9333
        target_lat = 49.9333
        if abs(start_lat - target_lat) < 0.002:
            score += 10
            feedback.append("Supply ship start position correct.")
        elif abs(start_lat - 46.0) < 0.1: # Common error: subtracting 4 degrees instead of minutes
            feedback.append("Supply ship start position wrong (subtracted degrees instead of minutes).")
        else:
            feedback.append(f"Supply ship start position incorrect (Lat {start_lat}).")
    except ValueError:
        feedback.append("Could not parse start latitude.")

    # 4. Check Approach Leg Math (CRITICAL - 30 pts)
    # This proves they understand relative vs geographic motion
    try:
        leg1_dist = float(result.get('leg1', {}).get('distance', 0))
        leg1_speed = float(result.get('leg1', {}).get('speed', 0))
        
        if abs(leg1_speed - 14.0) > 0.1:
             feedback.append(f"Leg 1 speed incorrect ({leg1_speed}kts).")
        
        if abs(leg1_dist - expected_app_dist) <= tolerance:
            score += 30
            feedback.append(f"Approach leg distance correct ({leg1_dist}nm).")
        elif abs(leg1_dist - 4.0) <= tolerance:
            feedback.append("FAILED MATH: You used 4.0nm (the relative gap) as the travel distance. Since both ships are moving, the chaser must travel 14nm to close a 4nm gap.")
        else:
            feedback.append(f"Approach leg distance incorrect ({leg1_dist}nm). Expected ~{expected_app_dist}nm.")
    except ValueError:
        feedback.append("Could not parse Leg 1 data.")

    # 5. Check Station Leg Math (20 pts)
    try:
        leg2_dist = float(result.get('leg2', {}).get('distance', 0))
        # 30 mins at 10 kts = 5nm
        if abs(leg2_dist - expected_sta_dist) <= tolerance:
            score += 20
            feedback.append(f"Station leg distance correct ({leg2_dist}nm).")
        else:
            feedback.append(f"Station leg distance incorrect ({leg2_dist}nm). Expected {expected_sta_dist}nm.")
    except ValueError:
        feedback.append("Could not parse Leg 2 data.")

    # 6. Check Calculation File (10 pts)
    if result.get('calc_file_exists'):
        score += 10
        feedback.append("Calculation file created.")

    passed = (score >= 70) and (abs(float(result.get('leg1', {}).get('distance', 0)) - expected_app_dist) <= tolerance)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }