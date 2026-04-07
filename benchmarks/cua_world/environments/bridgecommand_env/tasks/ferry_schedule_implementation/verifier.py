#!/usr/bin/env python3
import json
import math
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ferry_schedule(traj, env_info, task_info):
    """
    Verifies the Ferry Schedule task by parsing the created scenario files
    and calculating if the vessel starting positions result in the correct arrival times.
    """
    # 1. Setup & Data Extraction
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    # Load result from container
    import tempfile
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

    # 2. Basic Checks (20 pts)
    score = 0
    feedback = []
    
    if not result.get('scenario_exists'):
        return {"passed": False, "score": 0, "feedback": "Scenario directory not found."}
    
    files = result.get('files', {})
    if not files.get('environment.ini') or not files.get('othership.ini'):
        return {"passed": False, "score": 10, "feedback": "Missing required INI files."}
    
    if not result.get('othership_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Anti-gaming: File timestamps indicate pre-existing data."}

    score += 10 # Files exist
    feedback.append("Scenario files created.")

    # 3. Parse othership.ini
    # Bridge Command INI format is a bit weird, sometimes indexed: Type(1)=...
    othership_content = files['othership.ini']
    vessels = parse_bc_ini(othership_content)
    
    if len(vessels) != 4:
        feedback.append(f"Expected 4 vessels, found {len(vessels)}.")
        if len(vessels) == 0:
            return {"passed": False, "score": score, "feedback": "No vessels defined in othership.ini"}
    else:
        score += 10 # Correct count
        feedback.append("Correct number of vessels (4).")

    # 4. Verify Schedule Calculations (Physics Check)
    # Constants
    BERTH_LAT = 50.8000
    BERTH_LONG = -1.4000
    INTERSECT_LAT = 50.7500
    INTERSECT_LONG = -1.4000
    
    # Tolerances
    TIME_TOL_MIN = 1.5 # +/- 1.5 minutes
    DIST_TOL_NM = 0.3  # +/- 0.3 nm
    
    # Identify vessels by logic (closest match to expected speed/role)
    # We look for specific characteristics to identify which vessel is which agent intended
    
    # --- Vessel 1: Outbound Ferry ---
    # Should start near Berth
    v1 = find_best_match(vessels, target_lat=BERTH_LAT, target_long=BERTH_LONG, target_speed=12)
    if v1:
        dist = calc_dist(v1['lat'], v1['long'], BERTH_LAT, BERTH_LONG)
        if dist < DIST_TOL_NM:
            score += 10
            feedback.append("Vessel 1 (Outbound): Correct starting position at Berth.")
        else:
            feedback.append(f"Vessel 1: Starts {dist:.2f}nm from Berth (Expected 0).")
    else:
        feedback.append("Vessel 1: Could not identify outbound ferry (Speed 12, near Berth).")

    # --- Vessel 2: Inbound Ferry ---
    # Target: Arrive Berth 08:20. Start 08:00. Duration 20m. Speed 15kts.
    # Dist = 15 * (20/60) = 5.0 nm.
    # Must be 5.0 nm away.
    v2 = find_best_match(vessels, target_speed=15) # Identify by speed
    if v2:
        dist_start_to_berth = calc_dist(v2['lat'], v2['long'], BERTH_LAT, BERTH_LONG)
        time_to_arrive_hours = dist_start_to_berth / max(0.1, v2['speed'])
        time_to_arrive_min = time_to_arrive_hours * 60.0
        
        # Expected: 20 mins
        error = abs(time_to_arrive_min - 20.0)
        if error <= TIME_TOL_MIN:
            score += 30
            feedback.append(f"Vessel 2 (Inbound): Timing correct. Arrival in {time_to_arrive_min:.1f}m (Target 20m).")
        else:
            feedback.append(f"Vessel 2: Timing incorrect. Arrival in {time_to_arrive_min:.1f}m (Target 20m). Start pos error.")
    else:
        feedback.append("Vessel 2: Could not identify inbound ferry (Speed 15).")

    # --- Vessel 3: Crossing Hovercraft ---
    # Target: Cross Intersect 08:10. Start 08:00. Duration 10m. Speed 30kts.
    # Dist = 30 * (10/60) = 5.0 nm.
    v3 = find_best_match(vessels, target_speed=30)
    if v3:
        dist_start_to_int = calc_dist(v3['lat'], v3['long'], INTERSECT_LAT, INTERSECT_LONG)
        time_to_cross_min = (dist_start_to_int / max(0.1, v3['speed'])) * 60.0
        
        # Expected: 10 mins
        error = abs(time_to_cross_min - 10.0)
        if error <= TIME_TOL_MIN:
            score += 30
            feedback.append(f"Vessel 3 (Hovercraft): Timing correct. Crossing in {time_to_cross_min:.1f}m (Target 10m).")
        else:
            feedback.append(f"Vessel 3: Timing incorrect. Crossing in {time_to_cross_min:.1f}m (Target 10m).")
    else:
        feedback.append("Vessel 3: Could not identify hovercraft (Speed 30).")

    # --- Vessel 4: Escort Tug ---
    # Target: 1.0 nm behind Vessel 1. 
    # Since V1 is at Berth, V4 should be 1.0 nm away from Berth (in opposite direction of V1's movement, but simply checking distance to V1 is a good proxy if V1 is correct).
    v4 = find_best_match(vessels, target_speed=10)
    if v4:
        # Check distance to V1 (or Berth if V1 missing)
        ref_lat, ref_long = (v1['lat'], v1['long']) if v1 else (BERTH_LAT, BERTH_LONG)
        separation = calc_dist(v4['lat'], v4['long'], ref_lat, ref_long)
        
        if abs(separation - 1.0) <= DIST_TOL_NM:
            score += 20
            feedback.append(f"Vessel 4 (Escort): Correct station keeping ({separation:.2f}nm behind).")
        else:
            feedback.append(f"Vessel 4: Incorrect spacing. {separation:.2f}nm from lead (Target 1.0nm).")
    else:
        feedback.append("Vessel 4: Could not identify escort tug (Speed 10).")

    # 5. Final result
    passed = (score >= 70)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }

# --- Helper Functions ---

def parse_bc_ini(content):
    """
    Parses Bridge Command othership.ini format.
    Handles indexed keys like Type(1)=... or flat keys if only 1 vessel.
    Returns list of dicts: [{'lat': float, 'long': float, 'speed': float}, ...]
    """
    vessels = {}
    lines = content.splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith('//') or '=' not in line:
            continue
            
        key, val = line.split('=', 1)
        key = key.strip()
        val = val.strip().strip('"')
        
        # Extract index if present, e.g., InitialLat(2) -> 2
        index = 1
        param = key
        if '(' in key and key.endswith(')'):
            param = key.split('(')[0]
            try:
                index = int(key.split('(')[1].rstrip(')'))
            except:
                pass
        
        if index not in vessels:
            vessels[index] = {'lat': 0, 'long': 0, 'speed': 0}
            
        try:
            if param == 'InitialLat' or param == 'InitLat':
                vessels[index]['lat'] = float(val)
            elif param == 'InitialLong' or param == 'InitLong':
                vessels[index]['long'] = float(val)
            elif param == 'InitialSpeed' or param == 'InitSpeed' or param == 'Speed':
                vessels[index]['speed'] = float(val)
        except ValueError:
            pass
            
    return list(vessels.values())

def calc_dist(lat1, lon1, lat2, lon2):
    """
    Calculates distance in Nautical Miles between two lat/long points.
    Using simple spherical approximation (1 deg lat = 60nm).
    """
    # Average latitude for longitude scaling
    avg_lat_rad = math.radians((lat1 + lat2) / 2.0)
    
    dy = (lat2 - lat1) * 60.0
    dx = (lon2 - lon1) * 60.0 * math.cos(avg_lat_rad)
    
    return math.sqrt(dx*dx + dy*dy)

def find_best_match(vessels, target_lat=None, target_long=None, target_speed=None):
    """
    Finds the vessel from the list that best matches criteria.
    Simple greedy matching.
    """
    best_v = None
    best_score = float('inf')
    
    for v in vessels:
        score = 0
        if target_speed is not None:
            score += abs(v['speed'] - target_speed) * 10 # Speed is strong indicator
        if target_lat is not None and target_long is not None:
            dist = calc_dist(v['lat'], v['long'], target_lat, target_long)
            score += dist
            
        if score < best_score:
            best_score = score
            best_v = v
            
    # Threshold for "found"
    if best_score > 50: # Arbitrary high threshold if nothing matches well
        return None
    return best_v