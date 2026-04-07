#!/usr/bin/env python3
import json
import os
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vts_traffic_density_exercise(traj, env_info, task_info):
    """
    Verify the VTS Traffic Density Exercise.
    
    Scoring Criteria (100 pts total):
    1. Scenario Structure (10 pts): Directory and 3 INI files exist.
    2. Environment Config (10 pts): Solent, daytime, good vis, calm weather.
    3. Own Ship Placement (8 pts): Positioned at Calshot Spit, low speed.
    4. Vessel Count (8 pts): Exactly 8 traffic vessels.
    5. Vessel Diversity (10 pts): Check for keywords (container, tanker, ferry, etc).
    6. Vessel Position Validity (8 pts): All within Solent bounds.
    7. Vessel Speed Realism (6 pts): 3-20 knots.
    8. Waypoint Legs (10 pts): All vessels have >1 leg.
    9. Watch Log Existence (5 pts): File exists.
    10. Watch Log Content (20 pts): Specific maritime keywords and vessel summaries.
    11. Spatial Deconfliction (5 pts): No vessels stacked on top of each other.
    """
    
    # 1. Setup & Data Loading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

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
    feedback_details = []
    
    # --- Criterion 1: Scenario Structure (10 pts) ---
    files = result.get('files', {})
    if (files.get('environment_ini') == 'true' and 
        files.get('ownship_ini') == 'true' and 
        files.get('othership_ini') == 'true'):
        score += 10
        feedback_details.append("Structure: OK (All files created)")
    else:
        feedback_details.append(f"Structure: FAIL (Missing files: {files})")
        # If files missing, critical failure
        if score == 0:
             return {"passed": False, "score": 0, "feedback": "Critical: Scenario files not created."}

    # --- Criterion 2: Environment Configuration (10 pts) ---
    env = result.get('environment', {})
    env_score = 0
    
    # Setting = Solent
    if 'solent' in env.get('Setting', '').lower():
        env_score += 3
    else:
        feedback_details.append(f"Env: Setting mismatch ({env.get('Setting')})")

    # Time (Daytime 08-14)
    try:
        st = float(env.get('StartTime', -1))
        if 8.0 <= st <= 14.0:
            env_score += 3
    except: pass
    
    # Visibility >= 8.0
    try:
        vis = float(env.get('VisibilityRange', 0))
        if vis >= 8.0:
            env_score += 2
    except: pass
    
    # Weather <= 3.0
    try:
        weather = float(env.get('Weather', 99))
        if weather <= 3.0:
            env_score += 2
    except: pass
    
    score += env_score
    feedback_details.append(f"Environment: {env_score}/10")

    # --- Criterion 3: Own Ship Placement (8 pts) ---
    own = result.get('ownship', {})
    own_score = 0
    
    # Name check
    if 'vts' in own.get('ShipName', '').lower():
        own_score += 2
        
    # Position check (Calshot ~ 50.82, -1.31)
    try:
        lat = float(own.get('InitialLat', 0))
        lon = float(own.get('InitialLong', 0))
        if 50.77 <= lat <= 50.87 and -1.36 <= lon <= -1.26:
            own_score += 4
    except: pass
    
    # Speed check (<= 5)
    try:
        spd = float(own.get('InitialSpeed', 99))
        if spd <= 5.0:
            own_score += 2
    except: pass
    
    score += own_score
    feedback_details.append(f"OwnShip: {own_score}/8")

    # --- Criterion 4: Vessel Count (8 pts) ---
    otherships = result.get('otherships', [])
    count = len(otherships)
    if count == 8:
        score += 8
        feedback_details.append("Vessel Count: OK (8)")
    else:
        feedback_details.append(f"Vessel Count: FAIL ({count}/8)")

    # --- Criterion 5: Vessel Diversity (10 pts) ---
    types_found = set()
    required_keywords = ['container', 'cruise', 'tanker', 'ferry', 'bulk', 'naval', 'tug', 'warship']
    
    for vessel in otherships:
        v_type = vessel.get('type', '').lower()
        for kw in required_keywords:
            if kw in v_type:
                types_found.add(kw)
    
    # Consolidate synonyms
    if 'warship' in types_found: types_found.add('naval')
    
    # We want at least 6 distinct types
    div_score = min(10, len(types_found) * 2)
    score += div_score
    feedback_details.append(f"Diversity: {div_score}/10 ({len(types_found)} types)")

    # --- Criterion 6: Position Validity (8 pts) ---
    valid_pos_count = 0
    bounds = task_info.get('metadata', {}).get('solent_bounds', {})
    lat_min, lat_max = bounds.get('lat_min', 50.65), bounds.get('lat_max', 50.90)
    lon_min, lon_max = bounds.get('long_min', -1.55), bounds.get('long_max', -1.00)
    
    for vessel in otherships:
        try:
            lat = float(vessel.get('initlat', 0))
            lon = float(vessel.get('initlong', 0))
            if lat_min <= lat <= lat_max and lon_min <= lon <= lon_max:
                valid_pos_count += 1
        except: pass
    
    if count > 0:
        pos_score = int((valid_pos_count / count) * 8)
        score += pos_score
        feedback_details.append(f"Positions: {pos_score}/8")
    else:
        feedback_details.append("Positions: 0/8")

    # --- Criterion 7: Speed Realism (6 pts) ---
    valid_spd_count = 0
    for vessel in otherships:
        try:
            spd = float(vessel.get('initspeed', 0))
            if 3.0 <= spd <= 20.0:
                valid_spd_count += 1
        except: pass
        
    if count > 0:
        spd_score = int((valid_spd_count / count) * 6)
        score += spd_score
        feedback_details.append(f"Speeds: {spd_score}/6")

    # --- Criterion 8: Waypoint Legs (10 pts) ---
    valid_legs_count = 0
    for vessel in otherships:
        try:
            legs = int(vessel.get('legs_count', 0))
            if legs >= 2:
                valid_legs_count += 1
        except: pass
        
    if count > 0:
        leg_score = int((valid_legs_count / count) * 10)
        score += leg_score
        feedback_details.append(f"Legs: {leg_score}/10")

    # --- Criterion 9 & 10: Watch Log (25 pts total) ---
    log_content = result.get('log_content', '').lower()
    
    # Existence (5 pts)
    if files.get('log_file') == 'true' and len(log_content) > 100:
        score += 5
        
        # Content (20 pts)
        kw_score = 0
        keywords = task_info.get('metadata', {}).get('required_keywords_log', [])
        found_kws = [kw for kw in keywords if kw.lower() in log_content]
        
        # Scale 0-20 based on keyword coverage
        if keywords:
            kw_score = int((len(found_kws) / len(keywords)) * 20)
        
        score += kw_score
        feedback_details.append(f"Log Content: {kw_score + 5}/25")
    else:
        feedback_details.append("Log: FAIL (Missing or empty)")

    # --- Criterion 11: Spatial Deconfliction (5 pts) ---
    # Naive check: start positions shouldn't be identical
    positions = []
    overlap = False
    for vessel in otherships:
        try:
            pos = (float(vessel.get('initlat', 0)), float(vessel.get('initlong', 0)))
            if any(math.hypot(p[0]-pos[0], p[1]-pos[1]) < 0.005 for p in positions):
                overlap = True
            positions.append(pos)
        except: pass
    
    if not overlap and count > 0:
        score += 5
        feedback_details.append("Deconfliction: OK")
    else:
        feedback_details.append("Deconfliction: FAIL (Overlaps or no ships)")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_details)
    }