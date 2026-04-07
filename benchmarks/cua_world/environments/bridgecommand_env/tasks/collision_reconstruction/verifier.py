#!/usr/bin/env python3
"""
Verifier for collision_reconstruction task.

Verifies:
1. Scenario creation (directory and INI structure).
2. Environment parameters (Solent, fog, weather, time).
3. Own ship configuration (Name, Pos, Heading, Speed).
4. Traffic vessel configuration (3 specific vessels).
5. Radar configuration in bc5.ini.
6. Incident report content (names, COLREGS, keywords).
"""

import json
import os
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_collision_reconstruction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    incident_data = metadata.get('incident_data', {})
    
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

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: Scenario Structure (10 pts)
    # ---------------------------------------------------------
    if result.get('scenario_exists'):
        score += 5
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    files = result.get('files', {})
    if files.get('environment') and files.get('ownship') and files.get('othership'):
        score += 5
        feedback.append("All 3 INI files present.")
    else:
        feedback.append("Missing one or more INI files.")

    # ---------------------------------------------------------
    # Criterion 2: Environment Config (15 pts)
    # ---------------------------------------------------------
    env = files.get('environment', {}) or {}
    
    # Setting (Solent)
    if 'solent' in env.get('Setting', '').lower():
        score += 3
    else:
        feedback.append(f"Wrong setting: {env.get('Setting')}")

    # Time (6.5)
    try:
        t = float(env.get('StartTime', 0))
        if 6.0 <= t <= 7.0:
            score += 3
        else:
            feedback.append(f"Time {t} outside 0600-0700 range")
    except: pass

    # Visibility (1.5)
    try:
        v = float(env.get('VisibilityRange', 0))
        if 1.0 <= v <= 2.0:
            score += 3
        else:
            feedback.append(f"Visibility {v} not match 1.5nm (fog)")
    except: pass

    # Weather (4.0)
    try:
        w = float(env.get('Weather', 0))
        if 3.5 <= w <= 4.5:
            score += 3
        else:
            feedback.append(f"Weather {w} not Force 4")
    except: pass

    # Month (1)
    try:
        m = int(env.get('StartMonth', 0))
        if m == 1:
            score += 3
    except: pass

    # ---------------------------------------------------------
    # Criterion 3: Own Ship Config (10 pts)
    # ---------------------------------------------------------
    own = files.get('ownship', {}) or {}
    
    # Name
    if 'pacific' in own.get('ShipName', '').lower():
        score += 3
    else:
        feedback.append("Own ship name mismatch")

    # Pos (50.783, -1.195)
    try:
        lat = float(own.get('InitialLat', 0))
        lon = float(own.get('InitialLong', 0))
        if 50.70 <= lat <= 50.85 and -1.30 <= lon <= -1.10:
            score += 3
        else:
            feedback.append(f"Position {lat},{lon} outside Solent target area")
    except: pass

    # Speed (12)
    try:
        spd = float(own.get('InitialSpeed', 0))
        if 11.0 <= spd <= 13.0:
            score += 2
    except: pass

    # Heading (280)
    try:
        hdg = float(own.get('InitialBearing', 0))
        if 275 <= hdg <= 285:
            score += 2
    except: pass

    # ---------------------------------------------------------
    # Criterion 4: Traffic Vessels (25 pts)
    # ---------------------------------------------------------
    others = files.get('othership', []) or []
    
    if len(others) == 3:
        score += 5
        feedback.append("Correct number of traffic vessels (3).")
    else:
        feedback.append(f"Found {len(others)} vessels, expected 3.")

    # Check for specific vessels (fuzzy match)
    vessel_names = [v.get('Name', '') or v.get('Type', '') for v in others] # Sometimes name is not explicit in othership, usually Type or hardcoded models
    # Note: In othership.ini, 'Type' usually refers to the model/name used
    
    # We check if the configured Types/names loosely match the requirements
    # Vessel 1: Morning Star (Fishing)
    has_fishing = any('fishing' in str(v).lower() or 'morning' in str(v).lower() for v in others)
    # Vessel 2: Solent Guardian (Tanker)
    has_tanker = any('tanker' in str(v).lower() or 'guardian' in str(v).lower() or 'solent' in str(v).lower() for v in others)
    # Vessel 3: Dorado (Yacht)
    has_yacht = any('yacht' in str(v).lower() or 'dorado' in str(v).lower() for v in others)

    if has_fishing: score += 5
    if has_tanker: score += 5
    if has_yacht: score += 5
    
    # Check legs (movement)
    has_legs = all('Legs' in v for v in others)
    if has_legs and len(others) > 0:
        score += 5
        feedback.append("Vessels have waypoints defined.")
    else:
        feedback.append("Vessels missing movement legs.")

    # ---------------------------------------------------------
    # Criterion 5: Radar Configuration (10 pts)
    # ---------------------------------------------------------
    conf = result.get('config', {})
    
    if str(conf.get('arpa_on')) == '1': score += 3
    else: feedback.append("ARPA not enabled.")
    
    if str(conf.get('full_radar')) == '1': score += 3
    else: feedback.append("Full Radar not enabled.")
    
    try:
        rng = int(conf.get('max_radar_range', 48))
        if rng == 24: score += 4
        else: feedback.append(f"Radar range {rng} != 24")
    except: pass

    # ---------------------------------------------------------
    # Criterion 6: Report (30 pts)
    # ---------------------------------------------------------
    rep = result.get('report', {})
    if rep.get('exists'):
        score += 5
        content = rep.get('content', '').lower()
        
        # Keywords
        if 'reconstruction' in content: score += 5
        
        # Vessel names
        names_found = 0
        if 'pacific' in content: names_found += 1
        if 'morning' in content: names_found += 1
        if 'solent' in content: names_found += 1
        if 'dorado' in content: names_found += 1
        
        if names_found == 4: score += 10
        elif names_found >= 2: score += 5
        else: feedback.append(f"Only found {names_found}/4 vessel names in report.")
        
        # COLREGS Rules
        rules_found = len(re.findall(r'rule\s*\d+', content))
        if rules_found >= 3: score += 10
        elif rules_found >= 1: score += 5
        else: feedback.append("Insufficient COLREGS rule citations.")
        
    else:
        feedback.append("Report file NOT found.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }