#!/usr/bin/env python3
"""
Verifier for Asymmetric Threat Intercept task.
Calculates the kinematic validity of the scenario created by the agent.
"""

import json
import math
import os
import sys
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_distance_nm(lat1, lon1, lat2, lon2):
    """Calculate distance in Nautical Miles between two lat/long points."""
    R = 3440.065  # Radius of Earth in NM
    
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c

def calculate_bearing(lat1, lon1, lat2, lon2):
    """Calculate bearing from point 1 to point 2."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dlambda = math.radians(lon2 - lon1)
    
    y = math.sin(dlambda) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlambda)
    theta = math.atan2(y, x)
    
    return (math.degrees(theta) + 360) % 360

def project_position(lat, lon, bearing, distance_nm):
    """Calculate new position given start, bearing, and distance."""
    R = 3440.065 # Earth radius in NM
    
    lat1 = math.radians(lat)
    lon1 = math.radians(lon)
    brng = math.radians(bearing)
    dr = distance_nm / R
    
    lat2 = math.asin(math.sin(lat1)*math.cos(dr) + math.cos(lat1)*math.sin(dr)*math.cos(brng))
    lon2 = lon1 + math.atan2(math.sin(brng)*math.sin(dr)*math.cos(lat1), 
                             math.cos(dr)-math.sin(lat1)*math.sin(lat2))
                             
    return math.degrees(lat2), math.degrees(lon2)

def verify_asymmetric_threat_intercept(traj, env_info, task_info):
    """
    Verification logic for the swarm intercept scenario.
    """
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
            
    # Basic Checks
    if not result.get('scenario_found'):
        return {"passed": False, "score": 0, "feedback": "Scenario directory not created."}
    
    if not result.get('created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Scenario files were not created/modified during the task."}

    ownship = result.get('ownship', {})
    skiffs = result.get('skiffs', [])
    
    score = 0
    feedback = []
    
    # --- Check 1: Ownship Configuration (10 pts) ---
    # Expected: 50.75, -1.3333, Heading 90, Speed 12
    # Tolerance: 0.001 deg, 1 deg heading, 0.5 kts speed
    
    own_lat_ok = abs(ownship.get('lat', 0) - 50.75) < 0.002
    own_long_ok = abs(ownship.get('long', 0) - (-1.3333)) < 0.002
    own_speed_ok = abs(ownship.get('speed', 0) - 12.0) < 0.5
    own_heading_ok = abs(ownship.get('bearing', 0) - 90.0) < 2.0
    
    if own_lat_ok and own_long_ok and own_speed_ok and own_heading_ok:
        score += 10
        feedback.append("Ownship configuration correct.")
    else:
        feedback.append(f"Ownship config mismatch. Got: {ownship}")
        
    # --- Check 2: Calculate True Intercept Point (15 pts) ---
    # Ownship travels 12 kts for 10 mins (0.1667 hrs) = 2.0 NM at 90 deg
    start_lat = 50.75
    start_lon = -1.3333
    intercept_lat, intercept_lon = project_position(start_lat, start_lon, 90.0, 2.0)
    
    # We don't score the calculation directly, we score if the skiffs target this point.
    # But we give points if the agent seems to have derived coordinates near here for skiff destinations?
    # Actually, BC uses "legs" for skiffs. The verification checks if skiff start + (speed*time) hits intercept.
    
    # --- Check 3: Skiff Count and Speed (15 pts) ---
    valid_skiffs = [s for s in skiffs if abs(s['speed'] - 25.0) < 1.0]
    if len(valid_skiffs) >= 4:
        score += 15
        feedback.append(f"Found {len(valid_skiffs)} skiffs with correct speed (25 kts).")
    else:
        feedback.append(f"Found {len(valid_skiffs)} valid skiffs (expected 4 at 25 kts).")
        
    # --- Check 4: Synchronization & Geometry (60 pts) ---
    # For each skiff, calculate:
    # 1. Time to intercept (Distance to Intercept Point / Speed)
    # 2. Bearing from Intercept Point (Back azimuth)
    
    synced_skiffs = 0
    correct_geometry_skiffs = 0
    target_bearings = {45, 135, 225, 315}
    matched_bearings = set()
    
    for skiff in valid_skiffs:
        dist = haversine_distance_nm(skiff['lat'], skiff['long'], intercept_lat, intercept_lon)
        time_minutes = (dist / skiff['speed']) * 60.0
        
        # Check Sync (Target 10 mins)
        if abs(time_minutes - 10.0) < 0.5: # 30 seconds tolerance
            synced_skiffs += 1
            
        # Check Geometry (Bearing FROM intercept TO skiff start should be one of the targets)
        # Note: If skiff approaches FROM 045, it is AT 045 relative to intercept.
        # Bearing FROM intercept TO skiff = 045.
        bearing_to_skiff = calculate_bearing(intercept_lat, intercept_lon, skiff['lat'], skiff['long'])
        
        # Find closest target bearing
        closest_bearing = min(target_bearings, key=lambda x: abs(x - bearing_to_skiff))
        if abs(closest_bearing - bearing_to_skiff) < 5.0: # 5 deg tolerance
            correct_geometry_skiffs += 1
            matched_bearings.add(closest_bearing)

    # Scoring Sync
    if synced_skiffs == 4:
        score += 25
        feedback.append("All 4 skiffs synchronized to T+10m intercept.")
    elif synced_skiffs >= 2:
        score += 10
        feedback.append(f"Only {synced_skiffs} skiffs synchronized.")
    else:
        feedback.append("Skiffs not synchronized to 10 minutes.")

    # Scoring Geometry
    if correct_geometry_skiffs == 4 and len(matched_bearings) == 4:
        score += 35
        feedback.append("All 4 skiffs have correct attack vectors.")
    elif correct_geometry_skiffs >= 2:
        score += 15
        feedback.append(f"Only {correct_geometry_skiffs} skiffs have correct geometry.")
    else:
        feedback.append("Skiff geometry incorrect.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "intercept_point": f"{intercept_lat:.4f}, {intercept_lon:.4f}",
            "synced_count": synced_skiffs,
            "geometry_count": correct_geometry_skiffs
        }
    }