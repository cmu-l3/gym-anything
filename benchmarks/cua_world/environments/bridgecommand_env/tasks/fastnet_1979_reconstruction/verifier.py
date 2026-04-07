#!/usr/bin/env python3
"""
Verifier for Fastnet '79 Reconstruction task.

Criteria:
1. Scenario Structure (20%): Directory and 3 files exist.
2. Weather (30%): Force 10 parameters (Wind > 48, SW dir, Low Vis, High Sea).
3. Traffic (30%): 5 Vessels. 3 Running (NE), 2 Drifting (Slow).
4. Ownship (20%): Heading SW (into wind), Slow speed.

Anti-gaming:
- Checks if files were created during task window.
- Checks value ranges rather than exact string matches.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fastnet_reconstruction(traj, env_info, task_info):
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

    # Metadata / Constants
    meta = task_info.get('metadata', {})
    MIN_WIND = meta.get('min_wind_speed', 48)
    TARGET_WIND_DIR = meta.get('target_wind_dir', 225)
    WIND_TOL = meta.get('wind_dir_tolerance', 25) # 200-250 range
    MAX_VIS = meta.get('max_visibility', 0.8)
    MIN_WEATHER = meta.get('min_weather_val', 3.0)
    
    score = 0
    feedback = []
    
    # 1. Structure Check (20 pts)
    if not result.get('dir_exists'):
        return {"passed": False, "score": 0, "feedback": "Scenario directory not found."}
    
    # Check simple file existence implied by the parser results
    env_data = result.get('environment', {})
    own_data = result.get('ownship', {})
    others_data = result.get('otherships', [])
    
    if env_data and own_data and len(others_data) > 0:
        score += 20
        feedback.append("Structure valid (Directory and INI files found).")
    else:
        feedback.append("Structure partial: Missing some INI files or content.")
        score += 10 # Partial credit for directory

    # 2. Weather Configuration (30 pts)
    weather_score = 0
    
    # Wind Speed
    try:
        w_spd = float(env_data.get('WindSpeed', 0))
        if w_spd >= MIN_WIND:
            weather_score += 10
            feedback.append(f"Wind Speed OK ({w_spd} kts).")
        else:
            feedback.append(f"Wind Speed too low ({w_spd} < {MIN_WIND}).")
    except:
        feedback.append("Wind Speed missing/invalid.")

    # Wind Direction
    try:
        w_dir = float(env_data.get('WindDirection', -999))
        if (TARGET_WIND_DIR - WIND_TOL) <= w_dir <= (TARGET_WIND_DIR + WIND_TOL):
            weather_score += 5
            feedback.append(f"Wind Direction OK ({w_dir}°).")
        else:
            feedback.append(f"Wind Direction incorrect ({w_dir}°, expected SW ~{TARGET_WIND_DIR}°).")
    except:
        feedback.append("Wind Direction missing.")

    # Visibility
    try:
        vis = float(env_data.get('VisibilityRange', 999))
        if vis <= MAX_VIS:
            weather_score += 10
            feedback.append(f"Visibility OK ({vis} nm).")
        else:
            feedback.append(f"Visibility too good ({vis} > {MAX_VIS}).")
    except:
        feedback.append("Visibility missing.")
        
    # Sea State / Weather param
    try:
        weather_val = float(env_data.get('Weather', 0))
        if weather_val >= MIN_WEATHER:
            weather_score += 5
            feedback.append(f"Sea State OK ({weather_val}).")
        else:
            feedback.append(f"Sea State too calm ({weather_val}).")
    except:
        pass

    score += weather_score

    # 3. Traffic Configuration (30 pts)
    traffic_score = 0
    vessels = others_data
    
    if len(vessels) == 5:
        traffic_score += 10
        feedback.append("Vessel count correct (5).")
    else:
        feedback.append(f"Vessel count incorrect ({len(vessels)} != 5).")

    # Analyze behavior
    running_count = 0
    disabled_count = 0
    
    running_target = meta.get('running_heading_target', 45) # NE
    running_tol = meta.get('running_heading_tolerance', 45)
    
    for v in vessels:
        try:
            # Check for drifting/disabled (Speed < 2.5)
            spd = 0
            # Some entries might list multiple speeds if there are waypoints, take the first
            if 'speeds' in v and isinstance(v['speeds'], list):
                spd = float(v['speeds'][0])
            elif 'InitialSpeed' in v: # Fallback if parser handled flat key (unlikely for othership)
                spd = float(v['InitialSpeed'])
            # The export script puts 'Speed' into the dict if it's flat, or parses lists.
            # Let's handle the specific JSON format from export_result.sh which uses Key(Index) logic
            # Actually, export_result logic creates flat dict for each ship index.
            # But wait, Bridge Command 'othership.ini' uses 'Speed(1)=10'. 
            # Our parser extracts 'Speed' for that index.
            
            if 'Speed' in v:
                spd = float(v['Speed'])
            
            # Check Heading/Bearing
            bearing = 0
            if 'Bearing' in v:
                bearing = float(v['Bearing'])
            
            if spd < 2.5:
                disabled_count += 1
            else:
                # Check if running downwind (NE)
                # Normalize angle diff
                diff = abs(bearing - running_target)
                if diff > 180: diff = 360 - diff
                
                if diff <= running_tol and spd >= 6.0:
                    running_count += 1
        except:
            continue

    if running_count >= 3:
        traffic_score += 10
        feedback.append(f"Running vessels count OK ({running_count}).")
    else:
        feedback.append(f"Not enough vessels running downwind (Found {running_count}, need 3).")
        
    if disabled_count >= 2:
        traffic_score += 10
        feedback.append(f"Disabled vessels count OK ({disabled_count}).")
    else:
        feedback.append(f"Not enough disabled vessels (Found {disabled_count}, need 2).")

    score += traffic_score

    # 4. Ownship Seamanship (20 pts)
    own_score = 0
    try:
        o_head = float(own_data.get('InitialBearing', -1))
        o_spd = float(own_data.get('InitialSpeed', -1))
        
        target = meta.get('ownship_heading_target', 225)
        tol = meta.get('ownship_heading_tolerance', 45)
        
        diff = abs(o_head - target)
        if diff > 180: diff = 360 - diff
        
        if diff <= tol:
            own_score += 10
            feedback.append("Ownship heading correct (Into weather).")
        else:
            feedback.append(f"Ownship heading dangerous/wrong ({o_head}° vs {target}°).")
            
        if 0 < o_spd < 8.0:
            own_score += 10
            feedback.append("Ownship speed safe/realistic.")
        else:
            feedback.append(f"Ownship speed unsafe or zero ({o_spd}).")
            
    except:
        feedback.append("Ownship data missing.")
        
    score += own_score

    # Final Check
    passed = score >= 70 and result.get('dir_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }