#!/usr/bin/env python3
import json
import math
import os
import sys

def verify_landfall_rising_range_setup(traj, env_info, task_info):
    """
    Verify the Landfall Rising Range Setup task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result from container
    import tempfile
    temp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    metadata = task_info.get('metadata', {})
    
    # --- Ground Truth Calculation ---
    
    def calculate_dipping_range(H, h):
        return 2.03 * (math.sqrt(H) + math.sqrt(h))

    def dms_to_dd(deg, min_dec):
        return deg + (min_dec / 60.0)

    # 1. St. Catherine's Point (Own Ship)
    stc = metadata['st_catherines']
    stc_lat = dms_to_dd(stc['lat_deg'], stc['lat_min']) # 50.57583
    stc_long = -dms_to_dd(stc['long_deg'], stc['long_min']) # -1.29333 (West is negative)
    
    range_stc = calculate_dipping_range(stc['height_m'], metadata['ownship_eye_height_m'])
    
    # Own ship is 180 deg (South) from light
    # New Lat = Lat - (Distance / 60)
    # Longitude unchanged
    gt_own_lat = stc_lat - (range_stc / 60.0)
    gt_own_long = stc_long

    # 2. The Needles (Target Vessel)
    ndl = metadata['needles']
    ndl_lat = dms_to_dd(ndl['lat_deg'], ndl['lat_min']) # 50.66217
    ndl_long = -dms_to_dd(ndl['long_deg'], ndl['long_min']) # -1.59167
    
    range_ndl = calculate_dipping_range(ndl['height_m'], metadata['target_eye_height_m'])
    
    # Target is 270 deg (West) from light
    # Latitude unchanged
    # Departure = dLong * cos(Lat) => dLong = Dist / cos(Lat)
    # Longitude increases (more West)
    lat_rad = math.radians(ndl_lat)
    d_long_deg = (range_ndl / math.cos(lat_rad)) / 60.0
    gt_target_lat = ndl_lat
    gt_target_long = ndl_long - d_long_deg # Moving West

    # --- Scoring ---
    
    score = 0
    feedback = []

    # Criterion 1: Structure (20 pts)
    if result.get('scenario_exists') and result.get('files_created_during_task'):
        score += 10
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory missing or not created during task.")
    
    if result['environment']['exists'] and result['ownship']['exists'] and result['othership']['exists']:
        score += 10
        feedback.append("All INI files present.")
    else:
        feedback.append("One or more INI files missing.")

    # Criterion 2: Environment (20 pts)
    env = result.get('environment', {})
    if 'solent' in env.get('setting', '').lower():
        score += 5
    else:
        feedback.append(f"Incorrect setting: {env.get('setting')}")
        
    try:
        vis = float(env.get('visibility', 0))
        if vis >= 25.0:
            score += 10
            feedback.append(f"Visibility good ({vis}nm).")
        else:
            feedback.append(f"Visibility too low ({vis}nm), horizon checks require clear vis.")
    except:
        feedback.append("Invalid visibility value.")

    # Night check (rough)
    try:
        time = float(env.get('start_time', 0))
        if time > 20 or time < 5:
            score += 5
        else:
            feedback.append(f"Time {time} is not clearly night.")
    except:
        pass

    # Criterion 3: Own Ship Position (30 pts)
    # Tolerance: +/- 0.02 degrees (~1.2nm)
    tol = 0.02
    
    try:
        agent_own_lat = float(result['ownship']['lat'])
        agent_own_long = float(result['ownship']['long'])
        
        lat_diff = abs(agent_own_lat - gt_own_lat)
        long_diff = abs(agent_own_long - gt_own_long)
        
        if lat_diff < tol and long_diff < tol:
            score += 30
            feedback.append(f"OwnShip pos correct (Lat diff: {lat_diff:.4f}, Long diff: {long_diff:.4f}).")
        else:
            feedback.append(f"OwnShip pos mismatch. Expected {gt_own_lat:.4f}, {gt_own_long:.4f}. Got {agent_own_lat}, {agent_own_long}.")
    except Exception as e:
        feedback.append(f"Failed to parse OwnShip coords: {e}")

    # Criterion 4: Target Ship Position (30 pts)
    try:
        agent_oth_lat = float(result['othership']['lat'])
        agent_oth_long = float(result['othership']['long'])
        
        lat_diff = abs(agent_oth_lat - gt_target_lat)
        long_diff = abs(agent_oth_long - gt_target_long)
        
        if lat_diff < tol and long_diff < tol:
            score += 30
            feedback.append(f"TargetShip pos correct (Lat diff: {lat_diff:.4f}, Long diff: {long_diff:.4f}).")
        else:
            feedback.append(f"TargetShip pos mismatch. Expected {gt_target_lat:.4f}, {gt_target_long:.4f}. Got {agent_oth_lat}, {agent_oth_long}.")
    except Exception as e:
        feedback.append(f"Failed to parse TargetShip coords: {e}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }