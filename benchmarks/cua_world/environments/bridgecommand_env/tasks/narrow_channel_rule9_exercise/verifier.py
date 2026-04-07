#!/usr/bin/env python3
import json
import os
import sys
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_narrow_channel_rule9_exercise(traj, env_info, task_info):
    """
    Verifies the narrow_channel_rule9_exercise task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Verify Scenario Structure (10 pts)
    if result.get('scenario_dir_exists'):
        score += 4
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory missing.")
    
    files = result.get('files', {})
    if files.get('environment.ini', {}).get('exists'): score += 2
    if files.get('ownship.ini', {}).get('exists'): score += 2
    if files.get('othership.ini', {}).get('exists'): score += 2

    # 3. Verify Environment (10 pts)
    env = result.get('environment') or {}
    if 'Solent' in env.get('Setting', ''):
        score += 2
        feedback.append("Correct setting (Solent).")
    
    try:
        start_time = float(env.get('StartTime', 0))
        if 8.0 <= start_time <= 11.0:
            score += 2
        else:
            feedback.append(f"Start time {start_time} out of morning range (8-11).")
            
        vis = float(env.get('VisibilityRange', 0))
        if vis >= 5.0:
            score += 2
            
        weather = float(env.get('Weather', 99))
        if weather <= 2.0:
            score += 2
            
        if int(env.get('StartMonth', 0)) == 9:
            score += 2
    except:
        feedback.append("Error parsing environment values.")

    # 4. Verify Own Ship (10 pts)
    own = result.get('ownship') or {}
    if 'Solent Chemist' in own.get('ShipName', ''):
        score += 2
    
    try:
        lat = float(own.get('InitialLat', 0))
        lon = float(own.get('InitialLong', 0))
        # Southampton Water entrance area
        if 50.80 <= lat <= 50.83 and -1.32 <= lon <= -1.29:
            score += 4
            feedback.append("Own ship position correct.")
        else:
            feedback.append(f"Own ship pos ({lat},{lon}) out of bounds.")
            
        heading = float(own.get('InitialBearing', 0))
        if 330 <= heading <= 350:
            score += 2
            
        speed = float(own.get('InitialSpeed', 0))
        if 6.0 <= speed <= 10.0:
            score += 2
    except:
        feedback.append("Error parsing ownship values.")

    # 5. Verify Traffic Vessels (20 pts)
    other = result.get('othership') or {}
    # Count vessels (keys that are digits)
    vessel_indices = [k for k in other.keys() if k.isdigit()]
    vessel_count = len(vessel_indices)
    
    if vessel_count == 5:
        score += 10
        feedback.append("Correct number of traffic vessels (5).")
    elif vessel_count > 0:
        score += 5
        feedback.append(f"Incorrect vessel count ({vessel_count}), expected 5.")
    else:
        feedback.append("No traffic vessels found.")

    # Check for valid legs/waypoints
    valid_legs = 0
    for idx in vessel_indices:
        legs = other.get(idx, {}).get('legs', [])
        if legs and len(legs) >= 1:
            valid_legs += 1
    
    if valid_legs == 5:
        score += 10
    else:
        score += (valid_legs * 2)
        feedback.append(f"Only {valid_legs}/5 vessels have valid waypoints.")

    # 6. Verify Traffic Diversity (5 pts)
    # Check for diverse headings (approximate check based on description)
    # We can't easily calculate headings from waypoints without complex math here,
    # so we'll check if descriptions/types vary.
    types = [other.get(idx, {}).get('Type', '').lower() for idx in vessel_indices]
    unique_types = len(set(types))
    if unique_types >= 3:
        score += 5
        feedback.append("Good variety of vessel types.")
    else:
        feedback.append("Low diversity in vessel types.")

    # 7. Verify Radar Config (10 pts)
    conf = result.get('bc5_config') or {}
    if str(conf.get('arpa_on')) == '1': score += 2
    if str(conf.get('full_radar')) == '1': score += 2
    if int(conf.get('max_radar_range', 0)) == 48: score += 2
    if int(conf.get('radar_range_resolution', 0)) >= 128: score += 2
    if int(conf.get('radar_angular_resolution', 0)) >= 360: score += 2

    # 8. Verify Briefing Document (35 pts)
    briefing = result.get('briefing') or {}
    if briefing.get('exists'):
        score += 10
        feedback.append("Briefing document exists.")
        
        wc = briefing.get('word_count', 0)
        if wc >= 600:
            score += 10
            feedback.append(f"Briefing length good ({wc} words).")
        elif wc > 200:
            score += 5
            feedback.append(f"Briefing too short ({wc} words, expected 600).")
            
        keys = briefing.get('keywords_found', [])
        if len(keys) >= 3:
            score += 10
            feedback.append(f"Found keywords: {keys}")
        else:
            score += (len(keys) * 3)
            feedback.append(f"Missing key terms, found: {keys}")
            
        q_marks = briefing.get('question_mark_count', 0)
        if q_marks >= 3:
            score += 5
            feedback.append("Assessment questions present.")
    else:
        feedback.append("Briefing document missing.")

    # Final tally
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }