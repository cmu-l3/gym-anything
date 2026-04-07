#!/usr/bin/env python3
import json
import os
import logging
import tempfile
import math

logger = logging.getLogger(__name__)

def calculate_distance(lat1, lon1, lat2, lon2):
    """Haversine distance in nautical miles"""
    R = 3440.065  # Radius of Earth in nm
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2) * math.sin(dlat/2) + \
        math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * \
        math.sin(dlon/2) * math.sin(dlon/2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def verify_ais_traffic_conversion(traj, env_info, task_info):
    """
    Verify the conversion of AIS data to Bridge Command scenario.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vessels = metadata.get('expected_vessels', [])
    
    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Existence (20 pts)
    files = result.get('files', {})
    if result.get('scenario_dir_exists'):
        score += 5
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory missing.")

    if files.get('environment') and files.get('ownship') and files.get('othership'):
        score += 15
        feedback.append("All scenario INI files present.")
    else:
        feedback.append("Missing one or more scenario INI files.")

    # 2. Scenario Content (40 pts)
    othership = result.get('othership', {})
    
    # Count vessels
    try:
        num_vessels = int(othership.get('Number', 0))
    except:
        num_vessels = 0
        
    if num_vessels == 8:
        score += 10
        feedback.append("Correct number of vessels (8).")
    else:
        feedback.append(f"Incorrect vessel count: {num_vessels} (expected 8).")

    # Check validity of vessels (Locations)
    # We check if InitLat/InitLong are within Solent bounds and unique
    valid_locs = 0
    init_lats = othership.get('InitLat', {})
    init_longs = othership.get('InitLong', {})
    
    # Known Solent bounds
    min_lat, max_lat = 50.70, 50.90
    min_long, max_long = -1.45, -1.00
    
    for i in range(1, num_vessels + 1):
        idx = str(i)
        try:
            lat = float(init_lats.get(idx, 0))
            lon = float(init_longs.get(idx, 0))
            if min_lat < lat < max_lat and min_long < lon < max_long:
                valid_locs += 1
        except:
            pass

    if valid_locs >= 6:
        score += 10
        feedback.append(f"Vessel locations valid ({valid_locs}/8).")
    else:
        feedback.append(f"Many vessel locations invalid or out of bounds ({valid_locs}/8).")

    # Check for waypoint legs
    # Just check if 'Legs' or 'Leg' keys exist
    has_legs = 0
    legs_dict = othership.get('Legs', {}) # might be 'Legs(1)'
    leg_entries = othership.get('Leg', {}) # Leg(1,1)
    
    # Bridge command uses Leg(ship,leg)=...
    # The parser puts this in result['othership']['Leg'][ship,leg] - actually parser puts in '1,1' key
    
    # Check if there are reasonable number of leg entries
    if len(leg_entries) >= 16: # 8 vessels * 2 legs
        score += 20
        feedback.append("Waypoint legs detected.")
    else:
        feedback.append(f"Insufficient waypoint legs detected ({len(leg_entries)} found).")

    # 3. Environment & Ownship (15 pts)
    env = result.get('environment', {})
    own = result.get('ownship', {})
    
    if 'solent' in env.get('Setting', '').lower():
        score += 5
    if float(env.get('VisibilityRange', 0)) >= 8.0:
        score += 5
    if 'dorado' in own.get('ShipName', '').lower():
        score += 5

    # 4. Config (15 pts)
    config = result.get('config', {})
    if config.get('arpa_on') == '1': score += 5
    if config.get('full_radar') == '1': score += 5
    if config.get('max_radar_range') == '72': score += 5

    # 5. Report (10 pts)
    if files.get('report') and len(result.get('report_content', '')) > 50:
        score += 10
        feedback.append("Report exists and has content.")
    else:
        feedback.append("Report missing or empty.")

    # Anti-gaming check
    timestamps = result.get('timestamps', {})
    if not timestamps.get('othership', False):
        score = 0
        feedback = ["Anti-gaming: othership.ini not created during task."]
    
    passed = score >= 60 and num_vessels >= 6
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }