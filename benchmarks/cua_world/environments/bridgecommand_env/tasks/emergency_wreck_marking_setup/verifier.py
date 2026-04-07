#!/usr/bin/env python3
import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate Great Circle distance in Nautical Miles."""
    R = 3440.065  # Radius of Earth in NM
    
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c

def calculate_bearing(lat1, lon1, lat2, lon2):
    """Calculate initial bearing from point 1 to point 2 in degrees."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dlambda = math.radians(lon2 - lon1)
    
    y = math.sin(dlambda) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlambda)
    
    theta = math.atan2(y, x)
    bearing = (math.degrees(theta) + 360) % 360
    return bearing

def verify_emergency_wreck_marking_setup(traj, env_info, task_info):
    """
    Verify the emergency wreck marking scenario.
    
    Criteria:
    1. Scenario files exist (10 pts)
    2. Wreck placed at datum (20 pts)
    3. 4 Buoys placed at 0.5nm (±0.05nm) (40 pts)
    4. Buoys in correct cardinal directions (±5 deg) (20 pts)
    5. Correct models used (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    datum_lat = metadata.get('datum_lat', 50.7000)
    datum_long = metadata.get('datum_long', -1.3000)
    target_range = metadata.get('target_range_nm', 0.5)
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: Files Exist (10 pts)
    if result.get("directory_exists") and result.get("file_exists"):
        score += 10
        feedback.append("Scenario files created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Scenario directory or files not found."}

    # Anti-gaming check
    if not result.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Scenario files were not created during the task session."}

    vessels = result.get("vessels", [])
    if len(vessels) < 5:
        feedback.append(f"Found {len(vessels)} objects, expected 5.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Identify objects
    wreck = None
    buoys = []
    
    # Strategy: Find object closest to datum as wreck, others are buoys
    closest_dist = float('inf')
    
    for v in vessels:
        dist = haversine_distance(datum_lat, datum_long, v['lat'], v['long'])
        v['dist_from_datum'] = dist
        
        # Calculate bearing from datum to object
        v['bearing_from_datum'] = calculate_bearing(datum_lat, datum_long, v['lat'], v['long'])
        
        if dist < closest_dist:
            closest_dist = dist
            wreck = v
            
    # Remove wreck from list to get buoys
    buoys = [v for v in vessels if v != wreck]
    
    # Check 2: Wreck Position (20 pts)
    if wreck['dist_from_datum'] < 0.01: # Allow small tolerance
        score += 20
        feedback.append("Wreck placed correctly at datum.")
    else:
        feedback.append(f"Wreck misplaced by {wreck['dist_from_datum']:.3f} NM.")

    # Check 3 & 4: Buoy Placement (Range & Bearing)
    # We expect buoys at 000, 090, 180, 270 deg, distance 0.5 NM
    
    cardinals_found = {"N": False, "E": False, "S": False, "W": False}
    
    valid_buoys = 0
    correct_models = 0
    
    for b in buoys:
        dist = b['dist_from_datum']
        bearing = b['bearing_from_datum']
        model = b['type'].lower()
        
        # Check range (10 pts per buoy)
        range_ok = abs(dist - target_range) < 0.05
        
        # Determine direction
        direction = ""
        if 355 <= bearing or bearing <= 5: direction = "N"
        elif 85 <= bearing <= 95: direction = "E"
        elif 175 <= bearing <= 185: direction = "S"
        elif 265 <= bearing <= 275: direction = "W"
        
        # Check model name matches direction (5 pts per correct model usage)
        model_ok = False
        if direction == "N" and ("north" in model or "_n" in model): model_ok = True
        if direction == "E" and ("east" in model or "_e" in model): model_ok = True
        if direction == "S" and ("south" in model or "_s" in model): model_ok = True
        if direction == "W" and ("west" in model or "_w" in model): model_ok = True
        
        if direction:
            cardinals_found[direction] = True
            if range_ok:
                score += 10 # 4 buoys * 10 = 40 pts max for position
                valid_buoys += 1
            else:
                feedback.append(f"{direction} buoy range error ({dist:.3f} NM)")
            
            if model_ok:
                score += 2.5 # 4 buoys * 2.5 = 10 pts max for models
                correct_models += 1
        
        # Score bearing accuracy (20 pts total, 5 per buoy)
        # If we successfully mapped it to a direction above, it's within +/- 5 deg
        if direction:
            score += 5
    
    feedback.append(f"Valid Buoys: {valid_buoys}/4. Directions found: {json.dumps(cardinals_found)}.")

    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": {
            "wreck_error": wreck['dist_from_datum'],
            "valid_buoy_count": valid_buoys,
            "cardinals_found": cardinals_found
        }
    }