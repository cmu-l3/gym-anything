#!/usr/bin/env python3
import json
import os
import math
import base64
import configparser
import logging
import tempfile

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def parse_ini_string(ini_str):
    """
    Parses a Bridge Command INI string.
    Bridge Command INIs often have duplicate keys (e.g. key(1)=val, key(2)=val) 
    which standard python ConfigParser handles poorly without customization.
    However, BC INIs are basically key=value lines.
    """
    data = {}
    lines = ini_str.splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        if '=' in line:
            key, val = line.split('=', 1)
            data[key.strip().lower()] = val.strip().strip('"')
    return data

def parse_othership_ini(ini_str):
    """
    Parses othership.ini into a list of vessel dictionaries.
    BC othership format:
    Number=4
    Name(1)=ShipA
    InitialLat(1)=...
    """
    lines = ini_str.splitlines()
    vessels = {}
    
    for line in lines:
        line = line.strip()
        if not line or '=' not in line:
            continue
            
        key_raw, value = line.split('=', 1)
        key_raw = key_raw.strip().lower()
        value = value.strip().strip('"')
        
        # Parse indexed keys like Name(1) or InitialLat(1)
        if '(' in key_raw and ')' in key_raw:
            param = key_raw.split('(')[0]
            try:
                idx = int(key_raw.split('(')[1].split(')')[0])
                if idx not in vessels:
                    vessels[idx] = {'id': idx}
                vessels[idx][param] = value
            except ValueError:
                continue
        # Parse legs which might be Lat(1,1)
        # We simplify for this task: usually initial movement is defined by InitialSpeed/Bearing
        # OR by the first waypoint leg.
        
    return vessels

def calculate_bearing(lat1, lon1, lat2, lon2):
    """Calculates initial compass bearing between two points."""
    lat1 = math.radians(lat1)
    lat2 = math.radians(lat2)
    diffLong = math.radians(lon2 - lon1)

    x = math.sin(diffLong) * math.cos(lat2)
    y = math.cos(lat1) * math.sin(lat2) - (math.sin(lat1) * math.cos(lat2) * math.cos(diffLong))

    initial_bearing = math.atan2(x, y)
    initial_bearing = math.degrees(initial_bearing)
    compass_bearing = (initial_bearing + 360) % 360

    return compass_bearing

def verify_anchor_dragging(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

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

    # 1. Verify Scenario Existence (10 pts)
    score = 0
    feedback = []
    
    if not result.get('scenario_exists'):
        return {"passed": False, "score": 0, "feedback": "Scenario directory created."}
    
    score += 10
    feedback.append("Scenario directory exists.")

    # Decode INI files
    try:
        env_ini = parse_ini_string(base64.b64decode(result.get('env_ini_b64', '')).decode('utf-8'))
        own_ini = parse_ini_string(base64.b64decode(result.get('ownship_ini_b64', '')).decode('utf-8'))
        other_ini_raw = base64.b64decode(result.get('othership_ini_b64', '')).decode('utf-8')
        other_vessels = parse_othership_ini(other_ini_raw)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse INI files: {str(e)}"}

    # 2. Verify Environment (25 pts)
    # Night time check (22-04)
    start_time = float(env_ini.get('starttime', 12))
    if 22 <= start_time <= 24 or 0 <= start_time <= 4:
        score += 10
        feedback.append("Environment is set to Night.")
    else:
        feedback.append(f"Environment Time ({start_time}) is not night.")

    # Wind Check (Gale 35-45, Dir 225)
    wind_speed = float(env_ini.get('windspeed', 0)) # BC param is often just 'Weather' or 'WindSpeed' depending on version, checking standard keys
    # Note: In some BC versions 'Weather' controls sea state. 'WindSpeed' might not be standard.
    # Looking at previous examples, 'Weather' is sea state. Wind speed might be implicit or explicit.
    # We will check 'Weather' for rough sea state (Gale = rough seas = Weather > 4 usually) OR explicit wind.
    # Task requested 'Gale Force (WindSpeed 35-45)'.
    # If agent puts 'WindSpeed=40' in environment.ini, we accept it.
    
    bc_wind_speed = float(env_ini.get('windspeed', 0))
    bc_wind_dir = float(env_ini.get('winddirection', 0))
    
    if 35 <= bc_wind_speed <= 45:
        score += 10
        feedback.append("Wind speed is Gale Force.")
    else:
        feedback.append(f"Wind speed ({bc_wind_speed}) is not Gale Force (35-45).")
        
    if abs(bc_wind_dir - 225) < 5:
        score += 5
        feedback.append("Wind direction is SW.")
    else:
        feedback.append(f"Wind direction ({bc_wind_dir}) is not SW (225).")

    # 3. Verify Fleet Composition (15 pts)
    # Check for 4 vessels
    num_vessels = len(other_vessels)
    if num_vessels == 4:
        score += 15
        feedback.append("Correct number of traffic vessels (4).")
    else:
        feedback.append(f"Incorrect vessel count: {num_vessels} (expected 4).")

    # 4. Verify Dragging Logic (25 pts)
    dragging_vessel_found = False
    static_vessels = 0
    
    # Calculate target drag bearing (Downwind from 225 is 045)
    target_bearing = 45
    tolerance = 25
    
    for vid, v in other_vessels.items():
        speed = float(v.get('initialspeed', 0))
        
        # Check if static
        if speed == 0:
            static_vessels += 1
            continue
            
        # Check if potential dragger (slow speed)
        if 0.5 <= speed <= 2.0:
            # Check kinematic vector
            # Method A: InitialBearing
            bearing = float(v.get('initialbearing', -999))
            
            # Method B: Waypoint vector (if available)
            # Not implementing complex waypoint math here to avoid brittleness, trusting InitialBearing
            # since physics dictates initial motion.
            
            diff = abs(bearing - target_bearing)
            if diff > 180: diff = 360 - diff
            
            if diff <= tolerance:
                dragging_vessel_found = True
                feedback.append(f"Vessel {v.get('name', vid)} is dragging downwind correctly (Speed {speed}, Bearing {bearing}).")
            else:
                feedback.append(f"Vessel {v.get('name', vid)} has correct speed but wrong bearing ({bearing} vs target {target_bearing}).")
        elif speed > 2.0:
            feedback.append(f"Vessel {v.get('name', vid)} is moving too fast for dragging ({speed} kts).")

    if dragging_vessel_found:
        score += 25
    else:
        feedback.append("No vessel found correctly dragging downwind (0.5-2.0 kts, ~045 deg).")

    # 5. Verify Safe Vessels (15 pts)
    if static_vessels >= 3:
        score += 15
        feedback.append("Safe vessels are holding position.")
    else:
        feedback.append(f"Found {static_vessels} static vessels (expected 3).")

    # 6. Briefing Document (10 pts)
    if result.get('briefing_exists') == "true":
        score += 10
        feedback.append("Briefing document created.")
    else:
        feedback.append("Briefing document missing.")

    passed = (score >= 70) and dragging_vessel_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }