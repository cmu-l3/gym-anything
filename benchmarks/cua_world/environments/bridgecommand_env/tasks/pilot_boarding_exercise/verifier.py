#!/usr/bin/env python3
"""
Verifier for pilot_boarding_exercise task.
Checks scenario files, configuration, and documentation against requirements.
"""

import json
import base64
import os
import re
import tempfile
import configparser
import io

def verify_pilot_boarding_exercise(traj, env_info, task_info):
    # 1. Setup and retrieve result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Helpers for decoding and parsing
    def decode_content(b64_str):
        if not b64_str: return ""
        try:
            return base64.b64decode(b64_str).decode('utf-8', errors='ignore')
        except:
            return ""

    def parse_ini_string(content):
        # Bridge Command INI files are sometimes messy (no section headers, or duplicate keys)
        # We'll use a loose parsing strategy
        data = {}
        for line in content.splitlines():
            line = line.strip()
            if '=' in line and not line.startswith(';'):
                key, val = line.split('=', 1)
                key = key.strip()
                val = val.strip().strip('"') # Remove quotes if present
                data[key] = val
        return data

    def parse_othership(content):
        # Parses indexed keys like Type(1)=pilot
        vessels = {}
        for line in content.splitlines():
            line = line.strip()
            # Match pattern: Key(Index)=Value
            match = re.match(r'([A-Za-z]+)\((\d+)\)=(.+)', line)
            if match:
                key, idx, val = match.groups()
                idx = int(idx)
                if idx not in vessels: vessels[idx] = {}
                vessels[idx][key] = val.strip().strip('"')
            elif '=' in line:
                # Global keys like Number=5
                k, v = line.split('=', 1)
                vessels[k.strip()] = v.strip().strip('"')
        return vessels

    # 3. Validation Logic
    score = 0
    feedback = []
    
    # Metadata expectations
    meta = task_info.get('metadata', {})
    
    # --- Criterion 1: Scenario Directory Structure (10 pts) ---
    if result.get('scenario_dir_exists'):
        score += 4
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory missing.")

    files_exist = (result['environment_ini']['exists'] and 
                   result['ownship_ini']['exists'] and 
                   result['othership_ini']['exists'])
    if files_exist:
        score += 6
        feedback.append("All 3 INI files exist.")
    else:
        feedback.append("One or more INI files missing.")

    # --- Criterion 2: Environment Configuration (15 pts) ---
    env_content = decode_content(result['environment_ini']['content_b64'])
    env_data = parse_ini_string(env_content)
    
    env_score = 0
    if 'Solent' in env_data.get('Setting', ''): env_score += 5
    
    # Check time (06:00-08:00)
    try:
        start_time = float(env_data.get('StartTime', -1))
        if 6.0 <= start_time <= 8.0: env_score += 5
    except: pass
    
    if env_data.get('VisibilityRange') == '8.0': env_score += 3
    if env_data.get('Weather') == '3.0': env_score += 2
    
    score += env_score
    feedback.append(f"Environment config score: {env_score}/15")

    # --- Criterion 3: Ownship Configuration (10 pts) ---
    own_content = decode_content(result['ownship_ini']['content_b64'])
    own_data = parse_ini_string(own_content)
    
    own_score = 0
    if 'Pacific Trader' in own_data.get('ShipName', ''): own_score += 4
    
    # Check coordinates (approximate check)
    try:
        lat = float(own_data.get('InitialLat', 0))
        lng = float(own_data.get('InitialLong', 0))
        if 50.7 <= lat <= 50.8 and -1.1 <= lng <= -1.0: own_score += 3
    except: pass
    
    try:
        spd = float(own_data.get('InitialSpeed', 0))
        if 9.0 <= spd <= 11.0: own_score += 3
    except: pass
    
    score += own_score
    feedback.append(f"Ownship config score: {own_score}/10")

    # --- Criterion 4: Traffic Vessels (30 pts) ---
    other_content = decode_content(result['othership_ini']['content_b64'])
    other_data = parse_othership(other_content)
    
    other_score = 0
    # Check total number
    try:
        num = int(other_data.get('Number', 0))
        if num == 5: other_score += 5
    except: pass
    
    # Check specific vessels by name/type presence
    required_names = ["Doris T", "Ever Forward", "Solent Spirit", "FV Doreen", "Svitzer Doris"]
    found_names = []
    
    # Iterate through indexed vessels
    for idx in range(1, 20):
        if idx not in other_data: continue
        v = other_data[idx]
        name = v.get('Name', '')
        # Check if this vessel matches any requirement
        for req in required_names:
            if req.lower() in name.lower():
                found_names.append(req)
        
        # Check pilot vessel specifically
        if 'Doris T' in name and v.get('Type') == 'pilot':
            other_score += 5 # Bonus for getting the pilot boat right
            
        # Check waypoint leg existence
        if 'Leg' in v or 'BearingLeg' in v or 'Legs' in v:
            # Just rough check that legs are defined
            pass

    unique_found = len(set(found_names))
    # 4 points per correct vessel found (max 20)
    other_score += min(20, unique_found * 4)
    
    score += other_score
    feedback.append(f"Traffic vessels score: {other_score}/30 ({unique_found} vessels identified)")

    # --- Criterion 5: Radar Configuration (15 pts) ---
    config_content = decode_content(result['bc5_config']['content_b64'])
    # configparser is strict, let's use our loose parser but prepend a dummy section if needed
    if "[RADAR]" not in config_content and "[Graphics]" not in config_content:
        config_content = "[General]\n" + config_content
    
    # Parse proper INI
    parser = configparser.ConfigParser(strict=False)
    try:
        parser.read_string(config_content)
        # Flatten to dict for easier searching
        flat_config = {}
        for sec in parser.sections():
            for k, v in parser.items(sec):
                flat_config[k.lower()] = v
    except:
        # Fallback to loose parser
        flat_config = {k.lower(): v for k, v in parse_ini_string(config_content).items()}

    radar_score = 0
    if flat_config.get('arpa_on') == '1': radar_score += 3
    if flat_config.get('full_radar') == '1': radar_score += 3
    if flat_config.get('radar_range_resolution') == '256': radar_score += 3
    if flat_config.get('max_radar_range') == '72': radar_score += 3
    if flat_config.get('view_angle') == '90': radar_score += 3
    
    score += radar_score
    feedback.append(f"Radar config score: {radar_score}/15")

    # --- Criterion 6: Checklist Document (20 pts) ---
    checklist_score = 0
    checklist_data = result.get('checklist', {})
    
    if checklist_data.get('exists'):
        checklist_score += 5
        if checklist_data.get('modified_during_task'):
            checklist_score += 5
        else:
            feedback.append("Checklist file exists but wasn't modified during task.")
            
        content = decode_content(checklist_data.get('content_b64', '')).lower()
        if len(content) > 100:
            keywords = ["pacific", "imo", "ladder", "6", "vhf"]
            hits = sum(1 for k in keywords if k in content)
            checklist_score += hits * 2  # Max 10 pts
    
    score += checklist_score
    feedback.append(f"Checklist score: {checklist_score}/20")

    # Final result
    passed = score >= 60 and result.get('scenario_dir_exists')
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }