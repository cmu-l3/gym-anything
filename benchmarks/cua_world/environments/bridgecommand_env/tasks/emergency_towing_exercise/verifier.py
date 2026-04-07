#!/usr/bin/env python3
import json
import os
import math
import logging
import re
from datetime import datetime

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def parse_ini(content):
    """
    Parses a flat INI file content (key=value) into a dictionary.
    Handles duplicate keys if necessary (though standard INI shouldn't have them).
    """
    data = {}
    if not content:
        return data
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('['):
            continue
        if '=' in line:
            key, val = line.split('=', 1)
            data[key.strip().lower()] = val.strip().strip('"')
    return data

def parse_indexed_ini(content):
    """
    Parses indexed INI files (like othership.ini) where keys are Name(index)=Value.
    Returns a dict of dicts: {index: {key: value}}.
    """
    data = {}
    if not content:
        return data
    
    # Regex to capture Key(Index)=Value
    pattern = re.compile(r'([A-Za-z0-9]+)\(([0-9]+)(?:,[0-9]+)?\)=(.*)')
    
    for line in content.split('\n'):
        line = line.strip()
        match = pattern.match(line)
        if match:
            key, index, value = match.groups()
            index = int(index)
            if index not in data:
                data[index] = {}
            data[index][key.lower()] = value.strip().strip('"')
        elif '=' in line:
            # Handle global keys like Number=5
            key, val = line.split('=', 1)
            data['global'] = data.get('global', {})
            data['global'][key.strip().lower()] = val.strip().strip('"')
            
    return data

def calculate_distance(lat1, lon1, lat2, lon2):
    """Calculates Haversine distance in Nautical Miles."""
    R = 3440.065  # Radius of Earth in NM
    
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2) * math.sin(dlat/2) + \
        math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * \
        math.sin(dlon/2) * math.sin(dlon/2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def verify_emergency_towing(traj, env_info, task_info):
    """
    Verifies the Emergency Towing Arrangement Exercise task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    import tempfile
    temp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    score = 0
    max_score = 100
    feedback = []
    
    task_start = result.get('task_start_time', 0)
    scenario_data = result.get('scenario', {})
    config_data = result.get('config', {})
    doc_data = result.get('document', {})

    # =======================
    # CRITERION 1: Scenario Structure (10 pts)
    # =======================
    if scenario_data.get('exists'):
        score += 3
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory missing.")
    
    # Anti-gaming: Check timestamp
    if scenario_data.get('created_timestamp', 0) > task_start:
        score += 2
        feedback.append("Scenario created during task.")
    elif scenario_data.get('exists'):
        feedback.append("Scenario files pre-dated task (Anti-gaming fail).")
        
    env_ini = parse_ini(scenario_data.get('environment_ini', ''))
    own_ini = parse_ini(scenario_data.get('ownship_ini', ''))
    other_ini = parse_indexed_ini(scenario_data.get('othership_ini', ''))
    
    if env_ini and own_ini and other_ini:
        score += 5
        feedback.append("All required INI files present.")
    else:
        feedback.append("Missing one or more INI files.")

    # =======================
    # CRITERION 2: Environment Config (10 pts)
    # =======================
    # Setting: English Channel
    setting = env_ini.get('setting', '').lower()
    if 'english channel' in setting or 'channel' in setting:
        score += 2
    else:
        feedback.append(f"Wrong environment: {setting}")

    # Weather: Force 5-6 (roughly 5.0 in BC scale)
    try:
        weather = float(env_ini.get('weather', 0))
        if 4.5 <= weather <= 6.5:
            score += 2
        else:
            feedback.append(f"Weather not rough enough (expected ~5-6, got {weather})")
    except: pass
    
    # Time/Month
    try:
        start_time = float(env_ini.get('starttime', 0))
        start_month = int(env_ini.get('startmonth', 0))
        if 9.0 <= start_time <= 11.0:
            score += 2
        else:
            feedback.append(f"Start time {start_time} outside 09:00-11:00")
            
        if start_month in [11, 12, 1, 2]:
            score += 2
        else:
            feedback.append("Month is not winter")
            
        # Visibility
        vis = float(env_ini.get('visibilityrange', 0))
        if vis >= 5.0:
            score += 2
        else:
            feedback.append("Visibility too low")
    except:
        feedback.append("Error parsing environment numerical values")

    # =======================
    # CRITERION 3: Own Ship (ETV) (10 pts)
    # =======================
    if 'anglian' in own_ini.get('shipname', '').lower() or 'etv' in own_ini.get('shipname', '').lower():
        score += 3
    else:
        feedback.append("Ownship name incorrect")
        
    try:
        own_lat = float(own_ini.get('initiallat', 0))
        own_long = float(own_ini.get('initiallong', 0))
        own_spd = float(own_ini.get('initialspeed', 0))
        
        if 10.0 <= own_spd <= 16.0:
            score += 2
    except:
        feedback.append("Error parsing ownship data")
        own_lat, own_long = 0, 0

    # =======================
    # CRITERION 4: Other Ships (Traffic) (20 pts)
    # =======================
    vessels = [v for k, v in other_ini.items() if k != 'global']
    
    if len(vessels) >= 5:
        score += 5
        feedback.append(f"Vessel count correct ({len(vessels)})")
    else:
        feedback.append(f"Insufficient vessels: {len(vessels)}")
        
    # Identify disabled vessel (low speed)
    disabled_vessel = None
    for v in vessels:
        try:
            spd = float(v.get('initialspeed', 99))
            if spd <= 1.5:
                disabled_vessel = v
                break
        except: continue
        
    if disabled_vessel:
        score += 5
        feedback.append("Disabled vessel identified.")
        
        # Check position (Dover Strait SW lane)
        try:
            dis_lat = float(disabled_vessel.get('initlat', 0))
            dis_long = float(disabled_vessel.get('initlong', 0))
            
            # Simple bounds check for Dover Strait area
            if 50.90 <= dis_lat <= 51.20 and 1.10 <= dis_long <= 1.60:
                score += 5
                feedback.append("Disabled vessel in target area.")
            else:
                feedback.append("Disabled vessel outside target area.")
                
            # Check distance from ETV
            dist = calculate_distance(own_lat, own_long, dis_lat, dis_long)
            if 1.0 <= dist <= 4.0:
                score += 5
                feedback.append(f"ETV correctly positioned {dist:.1f}nm from casualty.")
            else:
                feedback.append(f"ETV distance incorrect: {dist:.1f}nm (expected 2-3nm).")
                
        except: pass
    else:
        feedback.append("No drifting/disabled vessel found.")

    # =======================
    # CRITERION 5: Radar Config (10 pts)
    # =======================
    bc5 = parse_ini(config_data.get('bc5_ini', ''))
    
    if bc5.get('arpa_on') == '1': score += 3
    if bc5.get('full_radar') == '1': score += 3
    
    try:
        rng = int(bc5.get('max_radar_range', 0))
        res = int(bc5.get('radar_range_resolution', 0))
        if rng >= 48: score += 2
        if res >= 128: score += 2
    except: pass

    # =======================
    # CRITERION 6: Realism (Drift Logic) (10 pts)
    # =======================
    # Check if disabled vessel heading is perpendicular to wind
    try:
        wind_dir = float(env_ini.get('winddirection', 0))
        ship_hdg = float(disabled_vessel.get('initialbearing', 0))
        
        # Drift heading is usually wind_dir +/- 90 degrees (beam on)
        diff = abs(wind_dir - ship_hdg) % 360
        # Normalize to 0-180
        if diff > 180: diff = 360 - diff
        
        # Expecting around 90 degrees diff
        if 45 <= diff <= 135:
            score += 10
            feedback.append("Physics check passed: Vessel drifting beam-to-wind.")
        else:
            feedback.append(f"Physics check failed: Wind {wind_dir}, Hdg {ship_hdg}. Not beam-to-wind.")
    except:
        feedback.append("Could not calculate drift physics (missing data).")

    # =======================
    # CRITERION 7: Document (30 pts)
    # =======================
    if doc_data.get('exists'):
        score += 5
        content = doc_data.get('content', '').lower()
        word_count = doc_data.get('word_count', 0)
        
        if word_count >= 600: # Allowing slight leniency from 800
            score += 5
            feedback.append("Document length adequate.")
        else:
            feedback.append(f"Document too short ({word_count} words).")
            
        keywords = ['messenger', 'pennant', 'ch 16', 'imo', 'resolution', 'lee', 'drift']
        found_kw = sum(1 for k in keywords if k in content)
        
        kw_score = min(20, found_kw * 3)
        score += kw_score
        feedback.append(f"Keywords found: {found_kw}/7")
    else:
        feedback.append("Document not found.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }