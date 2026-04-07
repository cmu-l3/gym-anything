#!/usr/bin/env python3
import json
import re
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fog_radar_assessment(traj, env_info, task_info):
    """
    Verify the Fog Radar Rule 19 Assessment task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    # --- Criterion 1: Scenario Structure (10 pts) ---
    if result.get('scenario_exists') and result.get('files_created_during_task'):
        # Check basic file content presence
        if result['environment_ini'] and result['ownship_ini'] and result['othership_ini']:
            score += 10
            feedback.append("Scenario directory and INI files created.")
        else:
            score += 5
            feedback.append("Scenario directory exists but some INI files are empty.")
    else:
        return {"passed": False, "score": 0, "feedback": "Scenario not created or created before task start."}

    # --- Criterion 2: Environment Configuration (15 pts) ---
    env_content = result.get('environment_ini', '')
    
    # Parse INI-like content loosely
    def get_val(text, key):
        match = re.search(fr"{key}\s*=\s*([^\s]+)", text, re.IGNORECASE)
        if not match: # Try quoted
            match = re.search(fr'{key}\s*=\s*"([^"]+)"', text, re.IGNORECASE)
        return match.group(1) if match else None

    vis = get_val(env_content, 'VisibilityRange')
    setting = get_val(env_content, 'Setting')
    weather = get_val(env_content, 'Weather')
    
    # Visibility <= 0.5 (Dense Fog)
    if vis and float(vis) <= 0.5:
        score += 5
        feedback.append(f"Visibility correct ({vis}).")
    else:
        feedback.append(f"Visibility incorrect or missing ({vis}).")

    # Setting Solent
    if setting and 'solent' in setting.lower():
        score += 5
        feedback.append("Setting correct.")
    else:
        feedback.append(f"Setting incorrect ({setting}).")
        
    # Weather Calm/Clear checks (Weather <= 2.0)
    if weather and float(weather) <= 2.0:
        score += 5
        feedback.append("Weather correct.")
    else:
        feedback.append("Weather incorrect.")

    # --- Criterion 3: Own Ship Configuration (10 pts) ---
    own_content = result.get('ownship_ini', '')
    name = get_val(own_content, 'ShipName')
    lat = get_val(own_content, 'InitialLat')
    long = get_val(own_content, 'InitialLong')
    
    if name and 'sentinel' in name.lower():
        score += 5
        feedback.append("Ownship name correct.")
    
    # Check bounds (Solent: Lat 50.70-50.85, Long -1.30 to -1.05)
    valid_coords = False
    if lat and long:
        try:
            if 50.70 <= float(lat) <= 50.85 and -1.30 <= float(long) <= -1.05:
                valid_coords = True
        except: pass
    
    if valid_coords:
        score += 5
        feedback.append("Ownship position correct.")
    else:
        feedback.append(f"Ownship position invalid or missing ({lat}, {long}).")

    # --- Criterion 4: Traffic Vessels (25 pts) ---
    other_content = result.get('othership_ini', '')
    
    # Count vessels
    num_match = re.search(r"Number\s*=\s*(\d+)", other_content, re.IGNORECASE)
    vessel_count = int(num_match.group(1)) if num_match else 0
    
    if vessel_count == 5:
        score += 10
        feedback.append("Vessel count correct (5).")
    else:
        feedback.append(f"Vessel count incorrect ({vessel_count}).")
        
    # Check names
    expected_vessels = ["Baltic Merchant", "Solent Ferry", "Harvest Moon", "Oceanus", "Artemis"]
    found_vessels = 0
    for v in expected_vessels:
        if v.lower() in other_content.lower():
            found_vessels += 1
            
    if found_vessels == 5:
        score += 5
        feedback.append("All vessel names found.")
    elif found_vessels >= 3:
        score += 2
        feedback.append(f"Some vessel names found ({found_vessels}/5).")
        
    # Check legs (rudimentary check for 'Legs(N)=' > 1)
    # This is hard to parse perfectly with regex, checking simple existence of multiple legs
    if len(re.findall(r"Legs\(\d+\)\s*=\s*[2-9]", other_content)) >= 5:
        score += 10
        feedback.append("Waypoints configured for vessels.")
    else:
        feedback.append("Waypoint configuration may be incomplete.")

    # --- Criterion 5: Radar Configuration (15 pts) ---
    config_dump = result.get('config_dump', '')
    
    # Check for latest values in the dump (since dump concatenates multiple files, we look for presence)
    # Ideally we'd parse strict priority, but regex searching for the specific assignments is decent proxy
    # We look for the assignment appearing anywhere
    
    radar_score = 0
    if re.search(r"arpa_on\s*=\s*1", config_dump): radar_score += 3
    if re.search(r"full_radar\s*=\s*1", config_dump): radar_score += 3
    if re.search(r"radar_range_resolution\s*=\s*512", config_dump): radar_score += 3
    if re.search(r"max_radar_range\s*=\s*48", config_dump): radar_score += 3
    if re.search(r"hide_instruments\s*=\s*0", config_dump): radar_score += 3
    
    score += radar_score
    if radar_score == 15:
        feedback.append("Radar configuration correct.")
    else:
        feedback.append(f"Radar configuration partial ({radar_score}/15).")

    # --- Criterion 6: Documents (25 pts) ---
    # Worksheet
    ws = result.get('worksheet', {})
    ws_score = 0
    if ws.get('exists'):
        ws_content = ws.get('content', '').lower()
        if 'rule 19' in ws_content: ws_score += 3
        if 'rule 5' in ws_content: ws_score += 3
        if 'rule 6' in ws_content: ws_score += 3
        if 'fog signal' in ws_content or 'prolonged blast' in ws_content: ws_score += 3
        if 'baltic merchant' in ws_content: ws_score += 3 # Check at least one vessel name
    
    score += ws_score
    if ws_score > 0: feedback.append(f"Worksheet checked ({ws_score}/15).")

    # Answer Key
    ans = result.get('answers', {})
    ans_score = 0
    if ans.get('exists'):
        ans_content = ans.get('content', '').lower()
        if '19(d)' in ans_content or '19d' in ans_content: ans_score += 3
        if '19(e)' in ans_content or '19e' in ans_content: ans_score += 3
        if 'safe speed' in ans_content: ans_score += 2
        if 'prolonged' in ans_content: ans_score += 2
    
    score += ans_score
    if ans_score > 0: feedback.append(f"Answer key checked ({ans_score}/10).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }