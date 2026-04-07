#!/usr/bin/env python3
import json
import os
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_progressive_training_suite(traj, env_info, task_info):
    """
    Verifies the Progressive Cadet Training Suite task.
    """
    # 1. Setup and Copy
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata for validation bounds
    solent_lat = (50.65, 50.90)
    solent_long = (-1.50, -0.95)
    
    scenarios = result.get('scenarios', {})
    
    # --- LEVEL 1 VERIFICATION (Daytime, Calm, 2 vessels) ---
    l1 = scenarios.get('L1', {})
    if l1.get('exists'):
        score += 5
        env = l1.get('environment', {}) or {}
        own = l1.get('ownship', {}) or {}
        other = l1.get('othership', {}) or {}
        
        # L1 Config
        if 'solent' in str(env.get('setting', '')).lower(): score += 2
        else: feedback.append("L1: Setting is not Solent")
            
        vis = float(env.get('visibilityrange', 0))
        if vis >= 8.0: score += 3
        else: feedback.append(f"L1: Visibility {vis} too low (expected >= 8.0)")
            
        wx = float(env.get('weather', 99))
        if wx <= 1.0: score += 3
        else: feedback.append(f"L1: Weather {wx} too high (expected <= 1.0)")
            
        # L1 Traffic
        count = int(other.get('count', 0))
        if count == 2: score += 3
        else: feedback.append(f"L1: Vessel count {count} != 2")

        # Time check (Daytime)
        start_time = float(env.get('starttime', -1))
        if 8.0 <= start_time <= 17.0: score += 2
        else: feedback.append(f"L1: Time {start_time} not daytime")
    else:
        feedback.append("L1: Scenario directory missing")

    # --- LEVEL 2 VERIFICATION (Night, Moderate, 4 vessels) ---
    l2 = scenarios.get('L2', {})
    if l2.get('exists'):
        score += 5
        env = l2.get('environment', {}) or {}
        other = l2.get('othership', {}) or {}
        
        if 'solent' in str(env.get('setting', '')).lower(): score += 2
        
        vis = float(env.get('visibilityrange', 0))
        if 4.0 <= vis <= 9.0: score += 3
        else: feedback.append(f"L2: Visibility {vis} out of range (expected 4-9)")
            
        wx = float(env.get('weather', 0))
        if 2.0 <= wx <= 4.0: score += 3
        else: feedback.append(f"L2: Weather {wx} out of range (expected 2-4)")
            
        count = int(other.get('count', 0))
        if count == 4: score += 3
        else: feedback.append(f"L2: Vessel count {count} != 4")
        
        # Time check (Night)
        start_time = float(env.get('starttime', -1))
        if start_time >= 20.0 or start_time <= 5.0: score += 2
        else: feedback.append(f"L2: Time {start_time} not nighttime")
    else:
        feedback.append("L2: Scenario directory missing")

    # --- LEVEL 3 VERIFICATION (Dawn/Day, Poor Vis, Rough, 6 vessels) ---
    l3 = scenarios.get('L3', {})
    if l3.get('exists'):
        score += 5
        env = l3.get('environment', {}) or {}
        other = l3.get('othership', {}) or {}
        
        if 'solent' in str(env.get('setting', '')).lower(): score += 2
        
        vis = float(env.get('visibilityrange', 100))
        if vis <= 2.0: score += 3
        else: feedback.append(f"L3: Visibility {vis} too good (expected <= 2.0)")
            
        wx = float(env.get('weather', 0))
        if wx >= 4.5: score += 3
        else: feedback.append(f"L3: Weather {wx} too calm (expected >= 4.5)")
            
        count = int(other.get('count', 0))
        if count == 6: score += 3
        else: feedback.append(f"L3: Vessel count {count} != 6")
    else:
        feedback.append("L3: Scenario directory missing")

    # --- PROGRESSION CHECK (Monotonicity) ---
    # Check if L1 > L2 > L3 for visibility
    try:
        v1 = float(scenarios['L1']['environment'].get('visibilityrange', 0))
        v2 = float(scenarios['L2']['environment'].get('visibilityrange', 0))
        v3 = float(scenarios['L3']['environment'].get('visibilityrange', 0))
        
        if v1 > v2 > v3:
            score += 5
            feedback.append("Visibility progression correct")
        else:
            feedback.append("Visibility not strictly progressive")
    except:
        pass

    # --- GENERAL CHECKS (Validity) ---
    valid_coords = True
    legs_check = True
    
    for level, data in scenarios.items():
        if not data.get('exists'): continue
        
        # Ownship coords
        own = data.get('ownship', {})
        try:
            lat = float(own.get('initiallat', -999))
            lon = float(own.get('initiallong', -999))
            if not (solent_lat[0] <= lat <= solent_lat[1] and solent_long[0] <= lon <= solent_long[1]):
                valid_coords = False
                feedback.append(f"{level}: Ownship out of bounds ({lat}, {lon})")
        except:
            valid_coords = False

        # Othership legs
        other = data.get('othership', {})
        ships = other.get('ships', {})
        for _, ship in ships.items():
            legs = ship.get('legs', [])
            if len(legs) < 2:
                legs_check = False
                feedback.append(f"{level}: A ship has fewer than 2 legs")

    if valid_coords: score += 5
    if legs_check: score += 5

    # --- RADAR CONFIGURATION (bc5.ini) ---
    config = result.get('config', {})
    radar_score = 0
    if int(config.get('radar_range_resolution', 0)) == 256: radar_score += 2
    if int(config.get('max_radar_range', 0)) == 72: radar_score += 2
    if int(config.get('full_radar', 0)) == 1: radar_score += 2
    if int(config.get('arpa_on', 0)) == 1: radar_score += 2
    score += radar_score

    # --- SYLLABUS DOCUMENT ---
    syllabus = result.get('syllabus', {})
    if syllabus.get('exists'):
        score += 5
        if syllabus.get('word_count', 0) >= 500:
            score += 5
        else:
            feedback.append(f"Syllabus too short ({syllabus.get('word_count')} words)")
            
        content = syllabus.get('content_snippet', '').lower()
        # Check for keywords (COLREGS rules)
        # We need simpler regex or string matching
        rules_found = 0
        for rule in ['rule 5', 'rule 6', 'rule 7', 'rule 19']:
            if rule in content: rules_found += 1
        
        if rules_found >= 3: # Allow one miss
            score += 5
        else:
            feedback.append(f"Syllabus missing COLREGS references (found {rules_found}/4)")
    else:
        feedback.append("Syllabus document missing")

    # --- ANTI-GAMING ---
    # Check timestamps
    task_start = result.get('task_meta', {}).get('start_time', 0)
    files_created_during_task = True
    for level, data in scenarios.items():
        if data.get('exists'):
            ts = data.get('files_timestamp', 0)
            if ts <= task_start:
                files_created_during_task = False
                feedback.append(f"{level}: Files timestamp predates task start")

    if not files_created_during_task:
        score = 0
        feedback.append("FAIL: Anti-gaming check failed (files too old)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }