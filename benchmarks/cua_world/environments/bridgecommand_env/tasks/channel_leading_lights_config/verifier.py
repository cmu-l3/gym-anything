#!/usr/bin/env python3
"""
Verifier for channel_leading_lights_config task.
Calculates geodetic distance/bearing between agent-placed objects to verify accuracy.
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_distance_bearing(lat1, lon1, lat2, lon2):
    """
    Calculate distance (nm) and initial bearing (degrees) between two points.
    """
    R = 3440.065  # Earth radius in nautical miles

    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    # Distance calculation
    a = math.sin(delta_phi / 2.0)**2 + \
        math.cos(phi1) * math.cos(phi2) * \
        math.sin(delta_lambda / 2.0)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    distance = R * c

    # Bearing calculation
    y = math.sin(delta_lambda) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - \
        math.sin(phi1) * math.cos(phi2) * math.cos(delta_lambda)
    theta = math.atan2(y, x)
    bearing = (math.degrees(theta) + 360) % 360

    return distance, bearing

def verify_channel_leading_lights_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata parameters
    metadata = task_info.get('metadata', {})
    start_lat = metadata.get('start_lat', 50.7000)
    start_long = metadata.get('start_long', -1.1000)
    target_bearing = metadata.get('bearing', 315.0)
    target_dist_front = metadata.get('dist_front_nm', 1.0)
    target_dist_rear = metadata.get('dist_rear_nm', 1.5)
    tol_dist = metadata.get('tolerance_nm', 0.05)
    tol_brg = metadata.get('tolerance_bearing_deg', 0.5)

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

    # Scoring
    score = 0
    feedback = []
    
    # 1. Scenario Existence (20 pts)
    if result.get("scenario_exists") and result.get("othership_exists"):
        score += 20
        feedback.append("Scenario and othership.ini created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Scenario or configuration file missing."}

    objects = result.get("objects", [])
    if len(objects) < 2:
        return {"passed": False, "score": score, "feedback": f"Found {len(objects)} objects, expected at least 2 (Front/Rear lights)."}

    # Identify Front and Rear lights based on distance from start
    # We calculate distance for all objects and sort them
    obj_metrics = []
    for i, obj in enumerate(objects):
        lat = obj.get("InitialLat")
        long_ = obj.get("InitialLong")
        
        if lat is None or long_ is None:
            continue
            
        dist, bearing = haversine_distance_bearing(start_lat, start_long, lat, long_)
        obj_metrics.append({
            "index": i,
            "dist": dist,
            "bearing": bearing,
            "lat": lat,
            "long": long_
        })

    # Sort by distance
    obj_metrics.sort(key=lambda x: x["dist"])
    
    if len(obj_metrics) < 2:
         return {"passed": False, "score": score, "feedback": "Could not parse coordinates for at least 2 objects."}

    # Assume closest is Front, next closest is Rear (if they are roughly correct)
    front = obj_metrics[0]
    rear = obj_metrics[1]

    # 2. Front Light Accuracy (25 pts)
    front_dist_err = abs(front["dist"] - target_dist_front)
    # Bearing calculation can be tricky with periodicity, but we expect ~315
    front_brg_err = abs(front["bearing"] - target_bearing)
    if front_brg_err > 180: front_brg_err = 360 - front_brg_err

    if front_dist_err <= tol_dist and front_brg_err <= tol_brg:
        score += 25
        feedback.append(f"Front Light placement perfect ({front['dist']:.3f}nm @ {front['bearing']:.1f}°).")
    elif front_dist_err <= tol_dist * 2 and front_brg_err <= tol_brg * 5:
        score += 10
        feedback.append(f"Front Light placement acceptable ({front['dist']:.3f}nm @ {front['bearing']:.1f}°).")
    else:
        feedback.append(f"Front Light misplaced: {front['dist']:.3f}nm (target {target_dist_front}) @ {front['bearing']:.1f}° (target {target_bearing}).")

    # 3. Rear Light Accuracy (25 pts)
    rear_dist_err = abs(rear["dist"] - target_dist_rear)
    rear_brg_err = abs(rear["bearing"] - target_bearing)
    if rear_brg_err > 180: rear_brg_err = 360 - rear_brg_err

    if rear_dist_err <= tol_dist and rear_brg_err <= tol_brg:
        score += 25
        feedback.append(f"Rear Light placement perfect ({rear['dist']:.3f}nm @ {rear['bearing']:.1f}°).")
    elif rear_dist_err <= tol_dist * 2 and rear_brg_err <= tol_brg * 5:
        score += 10
        feedback.append(f"Rear Light placement acceptable ({rear['dist']:.3f}nm @ {rear['bearing']:.1f}°).")
    else:
        feedback.append(f"Rear Light misplaced: {rear['dist']:.3f}nm (target {target_dist_rear}) @ {rear['bearing']:.1f}° (target {target_bearing}).")

    # 4. Alignment / Transit Accuracy (30 pts)
    # This is the most critical part: The bearing from Front to Rear MUST match the channel bearing
    # Otherwise the lights don't line up
    
    transit_dist, transit_bearing = haversine_distance_bearing(front["lat"], front["long"], rear["lat"], rear["long"])
    transit_brg_err = abs(transit_bearing - target_bearing)
    if transit_brg_err > 180: transit_brg_err = 360 - transit_brg_err
    
    if transit_brg_err <= tol_brg:
        score += 30
        feedback.append(f"Leading Line Alignment Perfect (Front->Rear Bearing: {transit_bearing:.2f}°).")
    elif transit_brg_err <= 2.0:
        score += 15
        feedback.append(f"Leading Line Alignment OK (Front->Rear Bearing: {transit_bearing:.2f}°).")
    else:
        feedback.append(f"Leading Line Misaligned: {transit_bearing:.2f}° (Should be {target_bearing}°). The lights do not guide the ship correctly.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "front_metrics": front,
            "rear_metrics": rear,
            "transit_bearing": transit_bearing
        }
    }