#!/usr/bin/env python3
"""
Verifier for synchronized_collision_setup task.
Calculates vector intersections to verify scenario setup.
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def project_position(lat, lon, speed_kts, heading_deg, time_hours):
    """
    Project a lat/long position forward in time.
    Uses flat-earth approximation suitable for short distances (<60nm).
    1 deg Lat = 60 nm
    1 deg Lon = 60 * cos(Lat) nm
    """
    dist_nm = speed_kts * time_hours
    heading_rad = math.radians(heading_deg)
    
    delta_lat_deg = (dist_nm * math.cos(heading_rad)) / 60.0
    
    mean_lat_rad = math.radians(lat + delta_lat_deg/2.0)
    delta_lon_deg = (dist_nm * math.sin(heading_rad)) / (60.0 * math.cos(mean_lat_rad))
    
    return lat + delta_lat_deg, lon + delta_lon_deg

def haversine_distance_nm(lat1, lon1, lat2, lon2):
    """Calculate distance in nautical miles between two points."""
    R = 3440.065  # Radius of Earth in nm
    
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c

def verify_synchronized_collision(traj, env_info, task_info):
    """
    Verifies that the agent has set up the scenario such that all vessels
    collide at T+12 minutes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy functionality missing"}

    metadata = task_info.get('metadata', {})
    target_time = metadata.get('target_time_hours', 0.2)
    threshold = metadata.get('collision_threshold_nm', 0.1)
    
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
            
    score = 0
    feedback = []
    
    # 1. Check Scenario Existence (10 pts)
    if not result.get('scenario_found'):
        return {"passed": False, "score": 0, "feedback": "Scenario directory not found."}
    score += 10
    feedback.append("Scenario directory created.")
    
    # 2. Check Own Ship Config (10 pts)
    own = result.get('ownship', {})
    target_own = metadata.get('ownship', {})
    
    # Tolerances
    own_ok = True
    if abs(own.get('lat', 0) - target_own['lat']) > 0.001: own_ok = False
    if abs(own.get('long', 0) - target_own['long']) > 0.001: own_ok = False
    if abs(own.get('speed', 0) - target_own['speed']) > 0.1: own_ok = False
    if abs(own.get('heading', 0) - target_own['heading']) > 1.0: own_ok = False
    
    if own_ok:
        score += 10
        feedback.append("Own ship configured correctly.")
    else:
        feedback.append(f"Own ship config incorrect. Found: {own}")
        
    # Calculate Collision Point (Where Own Ship will be at T+12m)
    # Even if agent configures own ship wrong, we calculate the collision point 
    # based on *their* own ship config to see if they synced the others to it?
    # No, strict requirement: Own ship must be as specified. 
    # But for partial credit, let's calculate based on specified Own Ship.
    
    # Specified Collision Point
    coll_lat, coll_lon = project_position(
        target_own['lat'], target_own['long'], 
        target_own['speed'], target_own['heading'], 
        target_time
    )
    
    # 3. Check Traffic Vessels (80 pts split)
    others = result.get('otherships', [])
    if len(others) != 3:
        feedback.append(f"Expected 3 traffic vessels, found {len(others)}")
    
    # We need to map found vessels to expected roles based on Heading/Speed
    # Roles:
    # - Head-on: Heading ~180, Speed ~18
    # - Crossing: Heading ~270, Speed ~12
    # - Overtaking: Heading ~000, Speed ~17
    
    roles_found = {
        'head_on': False,
        'crossing': False,
        'overtaking': False
    }
    
    for vessel in others:
        v_speed = vessel.get('speed', 0)
        v_head = vessel.get('heading', 0)
        v_lat = vessel.get('lat', 0)
        v_lon = vessel.get('long', 0)
        
        # Identify Role
        role = None
        if abs(v_head - 180) < 5 and abs(v_speed - 18) < 1:
            role = 'head_on'
            points = 25
        elif abs(v_head - 270) < 5 and abs(v_speed - 12) < 1:
            role = 'crossing'
            points = 30 # Slightly harder calculation (longitudinal)
        elif abs(v_head - 0) < 5 and abs(v_speed - 17) < 1:
            role = 'overtaking'
            points = 25
            
        if role:
            roles_found[role] = True
            
            # Verify Position
            # Project this vessel forward 12 minutes
            final_lat, final_lon = project_position(v_lat, v_lon, v_speed, v_head, target_time)
            
            # Calculate miss distance
            miss_dist = haversine_distance_nm(final_lat, final_lon, coll_lat, coll_lon)
            
            if miss_dist <= threshold:
                score += points
                feedback.append(f"{role.title()} vessel: PERFECT COLLISION (Miss: {miss_dist:.3f}nm)")
            elif miss_dist <= 0.5:
                score += int(points / 2)
                feedback.append(f"{role.title()} vessel: NEAR MISS (Miss: {miss_dist:.3f}nm)")
            else:
                feedback.append(f"{role.title()} vessel: MISS (Dist: {miss_dist:.3f}nm)")
                # Debug info
                feedback.append(f"  Start: {v_lat:.4f}, {v_lon:.4f} -> End: {final_lat:.4f}, {final_lon:.4f}")
                feedback.append(f"  Target End: {coll_lat:.4f}, {coll_lon:.4f}")
        else:
            feedback.append(f"Found unidentified vessel (Spd: {v_speed}, Hdg: {v_head})")

    # Check for missing roles
    for role, found in roles_found.items():
        if not found:
            feedback.append(f"Missing {role} vessel configuration")

    passed = (score >= 80)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }