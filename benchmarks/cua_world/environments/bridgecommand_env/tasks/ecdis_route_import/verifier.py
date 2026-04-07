#!/usr/bin/env python3
import json
import math
import os
import tempfile

def verify_ecdis_route_import(traj, env_info, task_info):
    """
    Verifies that the agent correctly converted the RTZ XML route to Bridge Command INI format.
    
    Criteria:
    1. Directory and files exist (20 pts)
    2. Start Position matches RTZ Waypoint 1 (20 pts)
    3. Initial Bearing is correctly calculated from WP1 -> WP2 (30 pts)
    4. Legs (WP2, WP3, WP4) are correctly mapped to Leg(1), Leg(2), Leg(3) (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_wps = metadata.get('expected_waypoints', [])
    exp_bearing = metadata.get('expected_initial_bearing', 316.2)
    bearing_tol = metadata.get('bearing_tolerance', 2.0)
    coord_tol = metadata.get('coordinate_tolerance', 0.0005)

    # Load result
    temp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    score = 0
    feedback = []
    
    # 1. Check Existence & Structure (20 pts)
    if result.get('dir_exists') and result.get('newly_created'):
        if result['files']['ownship'] and result['files']['environment']:
            score += 20
            feedback.append("Scenario structure created successfully.")
        else:
            score += 10
            feedback.append("Directory created but missing required INI files.")
    else:
        return {"passed": False, "score": 0, "feedback": "Scenario directory not found or not created during task."}

    data = result.get('ownship_data', {})
    
    # Helper to safe float
    def safe_float(val):
        try:
            return float(val)
        except (TypeError, ValueError):
            return None

    # 2. Check Start Position (WP1) (20 pts)
    lat = safe_float(data.get('initial_lat'))
    long_ = safe_float(data.get('initial_long'))
    
    target_start = expected_wps[0]
    
    if lat is not None and long_ is not None:
        if abs(lat - target_start['lat']) < coord_tol and abs(long_ - target_start['long']) < coord_tol:
            score += 20
            feedback.append("Start position correct.")
        else:
            feedback.append(f"Start position mismatch. Got ({lat}, {long_}), expected ({target_start['lat']}, {target_start['long']}).")
    else:
        feedback.append("Could not parse start position.")

    # 3. Check Initial Bearing (Calculation) (30 pts)
    bearing = safe_float(data.get('initial_bearing'))
    
    if bearing is not None:
        diff = abs(bearing - exp_bearing)
        # Handle 360 wrap-around
        if diff > 180:
            diff = 360 - diff
            
        if diff <= bearing_tol:
            score += 30
            feedback.append(f"Initial bearing calculated correctly ({bearing}).")
        else:
            feedback.append(f"Initial bearing incorrect. Got {bearing}, expected ~{exp_bearing} (True Bearing WP1->WP2).")
    else:
        feedback.append("Initial bearing missing or invalid.")

    # 4. Check Legs (WP2 -> Leg 1, WP3 -> Leg 2, etc) (30 pts)
    # expected_wps[1] corresponds to leg1
    legs_correct = 0
    total_legs = 3 # WP2, WP3, WP4
    
    # Check Leg 1 (WP2)
    l1_lat = safe_float(data.get('leg1', {}).get('lat'))
    l1_long = safe_float(data.get('leg1', {}).get('long'))
    if l1_lat and l1_long and abs(l1_lat - expected_wps[1]['lat']) < coord_tol and abs(l1_long - expected_wps[1]['long']) < coord_tol:
        legs_correct += 1
        
    # Check Leg 2 (WP3)
    l2_lat = safe_float(data.get('leg2', {}).get('lat'))
    l2_long = safe_float(data.get('leg2', {}).get('long'))
    if l2_lat and l2_long and abs(l2_lat - expected_wps[2]['lat']) < coord_tol and abs(l2_long - expected_wps[2]['long']) < coord_tol:
        legs_correct += 1
        
    # Check Leg 3 (WP4/End)
    l3_lat = safe_float(data.get('leg3', {}).get('lat'))
    l3_long = safe_float(data.get('leg3', {}).get('long'))
    if l3_lat and l3_long and abs(l3_lat - expected_wps[3]['lat']) < coord_tol and abs(l3_long - expected_wps[3]['long']) < coord_tol:
        legs_correct += 1
        
    score += (legs_correct * 10)
    if legs_correct == total_legs:
        feedback.append("All route legs configured correctly.")
    else:
        feedback.append(f"Route legs partially correct ({legs_correct}/{total_legs}). Check indexing (RTZ WP2 -> Bridge Command Leg 1).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }