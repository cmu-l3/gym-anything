#!/usr/bin/env python3
import json
import os
import logging
import tempfile
import re

logger = logging.getLogger(__name__)

def verify_emergency_anchorage_exercise(traj, env_info, task_info):
    """
    Verifies the Emergency Anchorage Exercise task.
    
    Grading (Total 100):
    1. Scenario Structure (10): Directory and INI files exist.
    2. Environment (15): Solent, Nighttime, Weather 5-7, Visibility 2-5nm.
    3. Own Ship (10): Positioned East Solent, Name correct.
    4. Anchored Vessels (15): 2 vessels, Speed 0, Correct location (Cowes Roads).
    5. Underway Vessels (15): 2 vessels, Speed > 0, Types correct.
    6. Radar Config (15): ARPA, Full Radar, Range Res 128, Max Range 24.
    7. Document (20): Content analysis (waypoints, VHF, etc).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    anchorage_lat = metadata.get('anchorage_area', {}).get('lat_min', 50.755) # Simplified range checks
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- 1. Scenario Structure (10 pts) ---
    if result.get('scenario_found') and all(result.get('files', {}).values()):
        score += 10
        feedback.append("Scenario files created successfully.")
    else:
        feedback.append("Missing scenario directory or required INI files.")
        # If files are missing, we can't really check much else, but we continue for partials if some exist
    
    env_data = result.get('env_data', {})
    own_data = result.get('ownship_data', {})
    vessels = result.get('vessels_parsed', [])
    
    # Merge config data (user config takes precedence usually, but check both)
    bc5 = {**result.get('bc5_data', {}), **result.get('bc5_user', {})}

    # --- 2. Environment (15 pts) ---
    # Setting=Solent
    if 'solent' in env_data.get('Setting', '').lower():
        score += 3
    else:
        feedback.append("Wrong setting (expected Solent).")

    # Time/Date
    try:
        start_time = float(env_data.get('StartTime', 0))
        if 14.0 <= start_time <= 15.5:
            score += 3
        else:
            feedback.append(f"Start time {start_time} out of range (14.0-15.5).")
        
        # Weather/Vis
        weather = float(env_data.get('Weather', 0))
        vis = float(env_data.get('VisibilityRange', 0))
        
        if 5.0 <= weather <= 7.0:
            score += 3
        else:
            feedback.append(f"Weather {weather} not in heavy range (5-7).")
            
        if 2.0 <= vis <= 5.0:
            score += 3
        else:
            feedback.append(f"Visibility {vis} not in range (2.0-5.0).")
            
        if env_data.get('Rain') == '1':
            score += 3
    except:
        feedback.append("Environment numeric parsing error.")

    # --- 3. Own Ship (10 pts) ---
    if 'doris' in own_data.get('ShipName', '').lower():
        score += 5
    else:
        feedback.append("Own ship name incorrect.")

    try:
        lat = float(own_data.get('InitialLat', 0))
        long = float(own_data.get('InitialLong', 0))
        # Eastern Solent Approach check
        if 50.74 <= lat <= 50.78 and -1.18 <= long <= -1.05:
            score += 5
        else:
            feedback.append(f"Own ship pos ({lat}, {long}) not in Eastern Solent approach.")
    except:
        pass

    # --- 4 & 5. Vessels (30 pts) ---
    anchored_count = 0
    underway_count = 0
    
    if len(vessels) == 4:
        score += 5 # Correct count
        for v in vessels:
            speed = v.get('speed', -1)
            lat = v.get('lat', 0)
            
            # Check for anchored vessels
            if speed == 0:
                # Check location (Cowes Roads approx)
                if 50.755 <= lat <= 50.780:
                    anchored_count += 1
            elif speed > 5:
                underway_count += 1
        
        if anchored_count >= 2:
            score += 15
            feedback.append("Found valid anchored vessels in Cowes Roads.")
        else:
            feedback.append(f"Found {anchored_count} anchored vessels (expected 2 in Cowes Roads).")
            
        if underway_count >= 2:
            score += 10
            feedback.append("Found valid underway vessels.")
        else:
            feedback.append("Underway vessel requirements not met.")
    else:
        feedback.append(f"Vessel count {len(vessels)} incorrect (expected 4).")

    # --- 6. Radar Config (15 pts) ---
    radar_score = 0
    if bc5.get('arpa_on') == '1': radar_score += 3
    if bc5.get('full_radar') == '1': radar_score += 4
    if bc5.get('radar_range_resolution') == '128': radar_score += 4
    if bc5.get('max_radar_range') == '24': radar_score += 4
    
    score += radar_score
    if radar_score < 15:
        feedback.append("Radar configuration incomplete.")

    # --- 7. Documentation (20 pts) ---
    doc = result.get('document', {})
    if doc.get('exists') and doc.get('created_during_task'):
        doc_score = 5
        content = doc.get('content', '').lower()
        
        # Keywords check
        keywords = ['waypoint', 'anchor', '12', '69', 'southampton']
        found = sum(1 for k in keywords if k in content)
        if found >= 3:
            doc_score += 10
        
        # Coordinate check (regex for Lat/Long pattern)
        if re.search(r'\d{2}[\.\,]\d+', content):
            doc_score += 5
            
        score += doc_score
        feedback.append("Plan document verified.")
    else:
        feedback.append("Approach plan document missing or not created during task.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }