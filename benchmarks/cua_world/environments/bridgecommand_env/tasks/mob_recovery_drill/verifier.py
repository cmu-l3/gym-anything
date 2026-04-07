#!/usr/bin/env python3
import json
import os
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_bearing_distance(lat1, lon1, lat2, lon2):
    """
    Calculate bearing and distance (in nm) between two coordinates.
    """
    R = 3440.065  # Radius of Earth in nautical miles
    
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)
    
    dlon = lon2_rad - lon1_rad
    dlat = lat2_rad - lat1_rad
    
    # Haversine distance
    a = math.sin(dlat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    distance = R * c
    
    # Bearing
    y = math.sin(dlon) * math.cos(lat2_rad)
    x = math.cos(lat1_rad) * math.sin(lat2_rad) - math.sin(lat1_rad) * math.cos(lat2_rad) * math.cos(dlon)
    bearing = math.degrees(math.atan2(y, x))
    bearing = (bearing + 360) % 360
    
    return bearing, distance

def verify_mob_recovery_drill(traj, env_info, task_info):
    """
    Verify the Man Overboard Recovery Drill task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Copy result JSON from container
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
    
    # 1. Scenario Structure (10 pts)
    if result.get("scenario_exists"):
        score += 5
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory NOT found.")
        return {"passed": False, "score": 0, "feedback": "Failed: Scenario directory not created."}
        
    if result.get("files_created_during_task"):
        score += 5
    else:
        feedback.append("Warning: Files have old timestamps (pre-task).")

    # 2. Environment Configuration (15 pts)
    env = result.get("environment", {})
    env_points = 0
    if "Solent" in env.get("Setting", ""): env_points += 5
    try:
        if 9.0 <= float(env.get("StartTime", -1)) <= 15.0: env_points += 3
        if float(env.get("VisibilityRange", 0)) >= 5.0: env_points += 4
        if 1.0 <= float(env.get("Weather", 0)) <= 5.0: env_points += 3
    except: pass
    
    score += env_points
    if env_points < 15: feedback.append(f"Environment config issues ({env_points}/15 pts).")
    
    # 3. Own Ship Configuration (10 pts)
    own = result.get("ownship", {})
    own_points = 0
    if "Celtic" in own.get("ShipName", ""): own_points += 3
    
    own_lat = 0
    own_long = 0
    own_head = 0
    
    try:
        own_lat = float(own.get("InitialLat", 0))
        own_long = float(own.get("InitialLong", 0))
        own_head = float(own.get("InitialBearing", 0))
        
        # Check location (South of IOW)
        if 50.5 <= own_lat <= 50.7 and -1.3 <= own_long <= -1.0:
            own_points += 4
        
        # Check speed
        if 10.0 <= float(own.get("InitialSpeed", 0)) <= 15.0:
            own_points += 3
    except: pass
    
    score += own_points
    if own_points < 10: feedback.append(f"Own ship config issues ({own_points}/10 pts).")

    # 4. MOB Marker Vessel - Geometry Check (20 pts)
    # Must be Vessel 0, stationary, close, and astern
    otherships = result.get("otherships", [])
    mob_points = 0
    mob_vessel = None
    
    if len(otherships) > 0:
        mob_vessel = otherships[0] # Typically index 0
        try:
            mob_lat = float(mob_vessel.get("InitialLat", 0))
            mob_long = float(mob_vessel.get("InitialLong", 0))
            mob_speed = float(mob_vessel.get("InitialSpeed", 100))
            
            # Check stationary
            if mob_speed <= 1.0:
                mob_points += 5
            else:
                feedback.append(f"MOB vessel moving at {mob_speed} kts (should be stationary).")
                
            # Geometry
            bearing, distance = calculate_bearing_distance(own_lat, own_long, mob_lat, mob_long)
            
            # Distance check (should be close, e.g. < 0.8nm)
            if 0.05 <= distance <= 0.8:
                mob_points += 5
                feedback.append(f"MOB distance good: {distance:.2f} nm.")
            else:
                feedback.append(f"MOB distance incorrect: {distance:.2f} nm (target 0.4).")
                
            # Bearing check (Astern means roughly reciprocal to heading)
            # Relative bearing
            rel_bearing = (bearing - own_head) % 360
            # Astern is 180. Allow 120-240
            if 120 <= rel_bearing <= 240:
                mob_points += 10
                feedback.append(f"MOB bearing good: {rel_bearing:.0f} deg relative.")
            else:
                feedback.append(f"MOB bearing incorrect: {rel_bearing:.0f} deg relative (should be astern).")
                
        except Exception as e:
            feedback.append(f"Error calculating MOB geometry: {e}")
    else:
        feedback.append("No otherships found.")
        
    score += mob_points

    # 5. Traffic Vessels (20 pts)
    traffic_points = 0
    if len(otherships) >= 3:
        traffic_points += 5 # Count correct
        
        # Check for activity (waypoints)
        legs_count = sum(1 for s in otherships if "Legs" in str(s))
        if legs_count >= 2:
            traffic_points += 5
            
        # Check speeds of traffic (should not be 0)
        moving_count = sum(1 for s in otherships[1:] if float(s.get("InitialSpeed", 0)) > 5)
        if moving_count >= 2:
            traffic_points += 10
    else:
        feedback.append(f"Insufficient vessels: {len(otherships)} (target 3).")
        
    score += traffic_points

    # 6. Config Settings (10 pts)
    cfg = result.get("config", {})
    cfg_points = 0
    try:
        if int(cfg.get("arpa_on", 0)) == 1: cfg_points += 2
        if int(cfg.get("full_radar", 0)) == 1: cfg_points += 2
        if int(cfg.get("radar_range_resolution", 0)) >= 128: cfg_points += 2
        if int(cfg.get("max_radar_range", 0)) >= 48: cfg_points += 2
        if int(cfg.get("hide_instruments", 1)) == 0: cfg_points += 2
    except: pass
    
    score += cfg_points
    if cfg_points < 10: feedback.append("bc5.ini settings incorrect.")

    # 7. Drill Document (15 pts)
    doc = result.get("document", {})
    doc_points = 0
    if doc.get("exists"):
        doc_points += 5
        content = doc.get("content", "").lower()
        keywords = ["williamson", "pan pan", "immediate", "recovery"]
        found = sum(1 for k in keywords if k in content)
        if found >= 3:
            doc_points += 10
        else:
            feedback.append(f"Document missing keywords (found {found}/4).")
    else:
        feedback.append("Drill document not created.")
        
    score += doc_points

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }