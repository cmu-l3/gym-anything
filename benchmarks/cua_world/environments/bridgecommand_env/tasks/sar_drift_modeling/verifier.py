#!/usr/bin/env python3
"""
Verifier for SAR Drift Modeling Task.
Calculates ground truth drift vector and compares with agent's result.
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def ddm_to_dd(degrees, minutes, direction=None):
    """Convert Degrees Decimal Minutes to Decimal Degrees."""
    dd = float(degrees) + float(minutes)/60.0
    if direction in ['S', 'W']:
        dd = -dd
    return dd

def calculate_ground_truth():
    """
    Perform the vector mathematics to find the correct Datum.
    
    Inputs (from Task Description):
    - LKP: 50° 46.5' N, 001° 18.0' W
    - Duration: 2.0 hours
    - Wind: From 315° @ 20 kts
    - Current: Set 100° @ 1.5 kts
    - Leeway: 3% of wind
    """
    # Initial Position
    start_lat = 50.0 + 46.5/60.0
    start_long = -(1.0 + 18.0/60.0)
    
    duration = 2.0
    
    # 1. Leeway Vector
    # Wind FROM 315 -> Blows TOWARDS 135 (315 - 180)
    wind_speed = 20.0
    leeway_factor = 0.03
    leeway_speed = wind_speed * leeway_factor # 0.6 kts
    leeway_dir_deg = 135.0
    leeway_dir_rad = math.radians(leeway_dir_deg)
    
    lw_x = leeway_speed * math.sin(leeway_dir_rad) # East component
    lw_y = leeway_speed * math.cos(leeway_dir_rad) # North component
    
    # 2. Current Vector
    # Set 100 (Flows TOWARDS 100)
    current_speed = 1.5
    current_dir_deg = 100.0
    current_dir_rad = math.radians(current_dir_deg)
    
    curr_x = current_speed * math.sin(current_dir_rad)
    curr_y = current_speed * math.cos(current_dir_rad)
    
    # 3. Total Drift Vector (Velocity)
    total_x = lw_x + curr_x
    total_y = lw_y + curr_y
    
    drift_speed = math.sqrt(total_x**2 + total_y**2)
    # math.atan2(y, x) normally returns angle from East (mathematical)
    # We want navigation bearing (0 = North, 90 = East)
    # Nav angle = atan2(x, y)
    drift_dir_rad = math.atan2(total_x, total_y)
    drift_dir_deg = math.degrees(drift_dir_rad)
    if drift_dir_deg < 0:
        drift_dir_deg += 360.0
        
    # 4. Total Displacement
    dist_nm = drift_speed * duration
    
    # 5. New Position (Rhumb line approximation is sufficient for short distance)
    # dLat = distance * cos(bearing)
    # dLong = distance * sin(bearing) / cos(mean_lat)
    
    delta_lat_min = dist_nm * math.cos(drift_dir_rad)
    final_lat = start_lat + (delta_lat_min / 60.0)
    
    mean_lat_rad = math.radians((start_lat + final_lat) / 2.0)
    departure = dist_nm * math.sin(drift_dir_rad)
    delta_long_min = departure / math.cos(mean_lat_rad)
    final_long = start_long + (delta_long_min / 60.0)
    
    return {
        "lat": final_lat,
        "long": final_long,
        "drift_course": drift_dir_deg,
        "drift_speed": drift_speed,
        "total_dist": dist_nm
    }

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance in NM between two decimal degree coordinates."""
    R = 3440.065 # Radius of Earth in NM
    
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2.0)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2.0)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c

def verify_sar_drift_modeling(traj, env_info, task_info):
    """
    Verify the SAR task.
    
    Criteria:
    1. Drift Vector Accuracy (25pts): Verified implicitly by final position, but good to check doc.
    2. Datum Position Accuracy (35pts): Target vessel within 0.5 NM of ground truth.
    3. Environment Config (15pts): Correct wind/time.
    4. Ownship Placement (10pts): At LKP.
    5. Documentation (15pts): Analysis file exists.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
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
            
    score = 0
    feedback = []
    
    # --- Check 1: Scenario Existence (Prerequisite) ---
    if not result.get("scenario_exists"):
        return {"passed": False, "score": 0, "feedback": "Scenario directory not created."}
    
    # --- Check 2: Datum Position (35 pts) ---
    ground_truth = calculate_ground_truth()
    
    try:
        agent_lat = float(result["data"].get("target_lat", -999))
        agent_long = float(result["data"].get("target_long", -999))
        
        # Validate coordinates are valid numbers
        if agent_lat == -999 or agent_long == -999:
             feedback.append("Could not parse target vessel coordinates.")
             pos_error = 999
        else:
            pos_error = haversine_distance(ground_truth["lat"], ground_truth["long"], agent_lat, agent_long)
            
            if pos_error <= 0.2:
                score += 35
                feedback.append(f"Position perfect! Error: {pos_error:.2f} NM")
            elif pos_error <= 0.5:
                score += 25
                feedback.append(f"Position good. Error: {pos_error:.2f} NM")
            elif pos_error <= 1.0:
                score += 10
                feedback.append(f"Position acceptable. Error: {pos_error:.2f} NM")
            else:
                feedback.append(f"Position off by {pos_error:.2f} NM (Limit 0.5 NM)")
                
    except Exception as e:
        feedback.append(f"Error parsing coordinates: {e}")
        pos_error = 999

    # --- Check 3: Environment Config (15 pts) ---
    data = result.get("data", {})
    
    # Time (Should be 15.0 or 15:00)
    agent_time = str(data.get("env_start_time", ""))
    if "15" in agent_time:
        score += 5
    else:
        feedback.append(f"Wrong StartTime: {agent_time} (Expected 15:00)")
        
    # Wind Dir (315)
    try:
        if abs(float(data.get("env_wind_dir", 0)) - 315) < 5:
            score += 5
    except:
        pass
        
    # Wind Speed (20)
    try:
        if abs(float(data.get("env_wind_speed", 0)) - 20) < 2:
            score += 5
    except:
        pass

    # --- Check 4: Ownship Placement (10 pts) ---
    # Should be at LKP: 50° 46.5' N, 001° 18.0' W
    # LKP Decimal: 50.775, -1.300
    lkp_lat = 50.0 + 46.5/60.0
    lkp_long = -(1.0 + 18.0/60.0)
    
    try:
        own_lat = float(data.get("own_lat", -999))
        own_long = float(data.get("own_long", -999))
        
        dist_from_lkp = haversine_distance(lkp_lat, lkp_long, own_lat, own_long)
        if dist_from_lkp < 0.1:
            score += 10
            feedback.append("Rescue vessel correctly placed at LKP.")
        else:
            feedback.append(f"Rescue vessel not at LKP (Dist: {dist_from_lkp:.2f} NM)")
    except:
        feedback.append("Could not parse ownship coordinates.")

    # --- Check 5: Documentation (15 pts) ---
    if result.get("doc_exists") and result.get("doc_created_during_task"):
        score += 15
        feedback.append("Drift analysis document created.")
    else:
        feedback.append("Drift analysis document missing or old.")

    # --- Check 6: Drift Vector Accuracy (25 pts - inferred) ---
    # We infer vector accuracy from the final position. 
    # If final pos score was high (>=25), we award these points too.
    # Otherwise, we check if the document contains numbers close to truth.
    
    if pos_error <= 0.5:
        score += 25
    elif result.get("doc_content"):
        # scan content for ~2.0 knots or ~110 degrees
        content = result["doc_content"]
        if "2.0" in content or "110" in content or "4.0" in content:
            score += 10
            feedback.append("Calculations appear partially correct in document despite position error.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "pos_error_nm": pos_error,
            "ground_truth": ground_truth,
            "agent_pos": {"lat": agent_lat, "long": agent_long}
        }
    }