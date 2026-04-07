#!/usr/bin/env python3
"""
Verifier for IMO Ship Maneuverability Trials Setup task.
"""

import json
import os
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_imo_maneuvering_trials_setup(traj, env_info, task_info):
    """
    Verifies that the agent correctly set up the 3 scenario folders, 
    configured the environment and vessel parameters, enabled track history,
    and calculated the correct IMO criteria values.
    """
    
    # 1. Setup and Load Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    scenarios_root = result.get('scenarios_root_exists', False)
    dirs = result.get('dirs', {})
    data = result.get('data', {})
    config = result.get('config', {})
    plan = result.get('plan', {})
    
    score = 0
    feedback_log = []
    
    # --- Criterion 1: Scenario Structure (15 pts) ---
    # 5 pts per correct folder
    if dirs.get('turning'): score += 5
    else: feedback_log.append("Missing 'Turning Circle Test' folder.")
    
    if dirs.get('zigzag'): score += 5
    else: feedback_log.append("Missing 'Zig-Zag Test' folder.")
    
    if dirs.get('stopping'): score += 5
    else: feedback_log.append("Missing 'Crash Stop Test' folder.")

    # --- Criterion 2: Zero Traffic (15 pts) ---
    # 5 pts per scenario
    traffic_score = 0
    for key in ['turning', 'zigzag', 'stopping']:
        if not dirs.get(key): continue
        
        # Check if traffic count is explicitly 0
        t_val = data[key].get('traffic', 'unknown')
        try:
            if int(t_val) == 0:
                traffic_score += 5
            else:
                feedback_log.append(f"Scenario {key} has {t_val} ships (expected 0).")
        except ValueError:
            feedback_log.append(f"Scenario {key} invalid traffic count: {t_val}")
            
    score += traffic_score

    # --- Criterion 3: Environmental Conditions (15 pts) ---
    # Weather=0 in all scenarios
    weather_score = 0
    for key in ['turning', 'zigzag', 'stopping']:
        if not dirs.get(key): continue
        w_val = data[key].get('weather', '99')
        try:
            if float(w_val) == 0:
                weather_score += 5
            else:
                feedback_log.append(f"Scenario {key} weather is {w_val} (expected 0).")
        except ValueError:
             feedback_log.append(f"Scenario {key} invalid weather: {w_val}")
    score += weather_score

    # --- Criterion 4: Safe Location (15 pts) ---
    # Lat < 50.65
    lat_score = 0
    for key in ['turning', 'zigzag', 'stopping']:
        if not dirs.get(key): continue
        l_val = data[key].get('lat', '99')
        try:
            if float(l_val) < 50.65:
                lat_score += 5
            else:
                feedback_log.append(f"Scenario {key} Lat {l_val} is too far North (expected < 50.65).")
        except ValueError:
             feedback_log.append(f"Scenario {key} invalid Lat: {l_val}")
    score += lat_score

    # --- Criterion 5: Config Setup (10 pts) ---
    if str(config.get('track_history')) == "1":
        score += 10
    else:
        feedback_log.append("bc5.ini 'track_history' not enabled.")

    # --- Criterion 6: Calculations (30 pts) ---
    # Check plan content for computed values
    # Tactical Diameter: 1125
    # Advance: 1012.5
    # Stopping: 3375
    
    plan_text = plan.get('content', '')
    plan_score = 0
    
    if plan.get('exists'):
        # Normalize text for searching
        text_norm = plan_text.replace(',', '')
        
        # Check Tactical Diameter (1125)
        if re.search(r"1125(\.0)?", text_norm):
            plan_score += 10
        else:
            feedback_log.append("Plan missing/incorrect Tactical Diameter (1125m).")

        # Check Advance (1012.5 or 1013)
        if re.search(r"1012\.5|1013", text_norm):
            plan_score += 10
        else:
            feedback_log.append("Plan missing/incorrect Advance (1012.5m).")

        # Check Stopping (3375)
        if re.search(r"3375(\.0)?", text_norm):
            plan_score += 10
        else:
            feedback_log.append("Plan missing/incorrect Stopping Distance (3375m).")
    else:
        feedback_log.append("Trials Plan document not found.")
    
    score += plan_score

    # Final Result
    passed = score >= 70 and plan_score > 0 # Require at least some calc correctness
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_log) if feedback_log else "All criteria met."
    }