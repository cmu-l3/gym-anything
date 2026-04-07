#!/usr/bin/env python3
"""
Verifier for Fisheries Patrol Exercise task.
Scores the agent's creation of a maritime training scenario and documentation.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fisheries_patrol_exercise(traj, env_info, task_info):
    """
    Verify the fisheries patrol scenario creation.

    Scoring (100 pts total):
    1. Scenario Files (10 pts): Directory and 3 INI files exist.
    2. Environment (10 pts): Solent, Time 06:00, Oct, Vis 8.0, Weather 3.0.
    3. Ownship (8 pts): Name 'PV Sentinel', correct Lat/Long/Speed.
    4. Vessels Structure (12 pts): 6 indexed vessels found.
    5. Vessel Geometry (10 pts): All vessels within Solent bounds, distinct positions.
    6. Vessel Details (15 pts): Names/Types match requirements (3x FV, 1x Cargo, 1x Yacht).
    7. Waypoints (10 pts): Each vessel has >= 2 legs.
    8. Radar Config (12 pts): 5 specific parameters set in bc5.ini.
    9. Documentation (13 pts): Briefing file exists, contains vessel names & keywords.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback = []
    
    # Metadata for validation ranges
    meta = task_info.get('metadata', {})
    bounds = meta.get('solent_bounds', {'lat_min': 50.55, 'lat_max': 50.85, 'long_min': -1.60, 'long_max': -0.90})

    # --- 1. Scenario Files (10 pts) ---
    if result.get('scenario_dir_exists'):
        score += 4
        files = result.get('files', {})
        if files.get('environment.ini', {}).get('exists'): score += 2
        if files.get('ownship.ini', {}).get('exists'): score += 2
        if files.get('othership.ini', {}).get('exists'): score += 2
        feedback.append("Scenario files structure created.")
    else:
        feedback.append("FAIL: Scenario directory not created.")
        return {"passed": False, "score": 0, "feedback": "Scenario directory missing."}

    # --- 2. Environment (10 pts) ---
    env = result.get('scenario_data', {}).get('environment', {})
    
    # Check Setting
    if 'solent' in env.get('Setting', '').lower():
        score += 2
    else:
        feedback.append(f"Environment Setting incorrect: {env.get('Setting')}")

    # Check Time/Date
    try:
        if 5.0 <= float(env.get('StartTime', -1)) <= 7.0: score += 2
        if int(env.get('StartMonth', -1)) == 10: score += 2
    except: pass
    
    # Check Vis/Weather
    try:
        if float(env.get('VisibilityRange', 0)) >= 5.0: score += 2
        if float(env.get('Weather', 99)) <= 4.0: score += 2
    except: pass

    # --- 3. Ownship (8 pts) ---
    own = result.get('scenario_data', {}).get('ownship', {})
    
    if 'sentinel' in own.get('ShipName', '').lower():
        score += 3
        feedback.append("Ownship name correct.")
    
    try:
        lat = float(own.get('InitialLat', 0))
        lon = float(own.get('InitialLong', 0))
        if 50.55 <= lat <= 50.70 and -1.25 <= lon <= -1.05:
            score += 3
        else:
            feedback.append(f"Ownship pos ({lat}, {lon}) out of expected patrol area.")
            
        speed = float(own.get('InitialSpeed', 0))
        if 10 <= speed <= 15: score += 2
    except:
        feedback.append("Ownship parameters missing or invalid.")

    # --- 4 & 5 & 6 & 7. Traffic Vessels Analysis (47 pts) ---
    vessels = result.get('scenario_data', {}).get('othership', {}).get('vessels', [])
    v_count = len(vessels)
    
    if v_count == 6:
        score += 12 # Structure score
        feedback.append("Correct number of vessels (6).")
    else:
        score += min(v_count * 2, 8)
        feedback.append(f"Found {v_count} vessels (expected 6).")

    # Analyze individual vessels
    valid_pos_count = 0
    valid_leg_count = 0
    fv_count = 0
    cargo_count = 0
    yacht_count = 0
    
    for v in vessels:
        # Check Position (Geometry)
        try:
            lat = float(v.get('lat', 0))
            lon = float(v.get('long', 0))
            if bounds['lat_min'] <= lat <= bounds['lat_max'] and bounds['long_min'] <= lon <= bounds['long_max']:
                valid_pos_count += 1
        except: pass
        
        # Check Legs
        if len(v.get('legs', [])) >= 2:
            valid_leg_count += 1
            
        # Check Name/Type
        name = v.get('type', '').lower() # BC stores name in Type() field usually for simple scenarios or Name()
        # In the task description, we asked for specific names.
        # Bridge Command often puts the readable name in the Type value for "Othership" definitions in simplified mode,
        # or separate ShipName. The task spec asked for Type(N)=Name. 
        # So we check the value of 'type' for the name strings.
        if 'fv ' in name or 'trawler' in name or 'potter' in name or 'netter' in name:
            fv_count += 1
        elif 'express' in name or 'cargo' in name or 'mv ' in name:
            cargo_count += 1
        elif 'artemis' in name or 'yacht' in name or 'sy ' in name:
            yacht_count += 1

    # Score Geometry (10 pts)
    if valid_pos_count >= 6: score += 10
    elif valid_pos_count >= 4: score += 5
    
    # Score Details/Types (15 pts)
    if fv_count >= 3: score += 5
    if cargo_count >= 1: score += 5
    if yacht_count >= 1: score += 5
    
    # Score Waypoints (10 pts)
    if valid_leg_count >= 6: score += 10
    elif valid_leg_count >= 4: score += 5

    # --- 8. Radar Config (12 pts) ---
    radar = result.get('radar_config', {})
    radar_points = 0
    if radar.get('arpa_on') == '1': radar_points += 2
    if radar.get('full_radar') == '1': radar_points += 2
    if radar.get('radar_range_resolution') == '256': radar_points += 3
    if radar.get('max_radar_range') == '72': radar_points += 3
    if radar.get('radar_angular_resolution') == '720': radar_points += 2
    score += radar_points
    if radar_points < 12:
        feedback.append(f"Radar config incomplete ({radar_points}/12 pts).")

    # --- 9. Documentation (13 pts) ---
    doc = result.get('briefing', {})
    if doc.get('exists'):
        score += 3
        content = doc.get('content', '').lower()
        
        # Check for vessel names in doc
        names_found = 0
        expected_names = ['horizon', 'neptune', 'silver spray', 'channel express', 'morning star', 'artemis']
        for name in expected_names:
            if name in content:
                names_found += 1
        
        if names_found >= 6: score += 5
        elif names_found >= 3: score += 3
        
        # Check for keywords
        keywords = ['vms', 'license', 'gear', 'catch', 'inspection', 'quota', 'restricted', 'vhf']
        kw_found = sum(1 for k in keywords if k in content)
        if kw_found >= 2: score += 5
        
        # Anti-gaming: Check doc was modified AFTER task start
        task_start = result.get('timestamps', {}).get('task_start', 0)
        doc_mtime = doc.get('mtime', 0)
        if doc_mtime <= task_start:
            feedback.append("Briefing file timestamp is too old (anti-gaming check).")
            score -= 13 # Revoke doc points
    else:
        feedback.append("Briefing document missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }