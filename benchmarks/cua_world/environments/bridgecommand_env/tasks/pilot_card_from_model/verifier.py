#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
import math

logger = logging.getLogger(__name__)

def verify_pilot_card_from_model(traj, env_info, task_info):
    """
    Verify pilot_card_from_model task.
    
    Checks:
    1. Pilot card existence and structure (Sections A-F).
    2. Data Accuracy: numeric values in pilot card match a real model in Models/.
    3. Scenario configuration (Solent, position, traffic).
    4. Config settings (instruments visible).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    
    # === 1. Pilot Card Structure (30 pts) ===
    content = result.get('pilot_card_content', '')
    if not content:
        feedback.append("FAIL: Pilot card file missing or empty")
    else:
        score += 5 # Exists
        # Check timestamp
        if result.get('pilot_card_mtime', 0) > result.get('task_start_time', 0):
            score += 5
            feedback.append("Pilot card created during task")
        else:
            feedback.append("FAIL: Pilot card timestamp invalid")

        # Check sections
        sections = ['Section A', 'Section B', 'Section C', 'Section D', 'Section E', 'Section F']
        missing_sections = [s for s in sections if s.lower() not in content.lower()]
        
        if not missing_sections:
            score += 20
            feedback.append("All 6 IMO pilot card sections present")
        else:
            partial = 20 - (len(missing_sections) * 3)
            score += max(0, partial)
            feedback.append(f"Missing sections: {', '.join(missing_sections)}")

    # === 2. Data Cross-Reference (30 pts) ===
    # Strategy: Extract numbers from pilot card and fuzzy match against the models database
    models_db = result.get('models_db', {})
    
    # Extract candidate numbers from pilot card (look for patterns like "Length: 100", "100m", "Speed: 15")
    # We look for key parameters: Length, Width, MaxSpeed
    card_text = content.lower()
    
    # Helper to find closest number in text to a target value
    def match_value(text, target, tolerance=0.05):
        if not target: return False
        try:
            target = float(target)
        except: return False
        
        # Regex to find numbers
        numbers = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", text)]
        for n in numbers:
            if abs(n - target) <= (target * tolerance):
                return True
        return False

    best_match_model = None
    best_match_count = 0
    best_match_details = []

    # Iterate all models to find which one the user likely documented
    for model_name, props in models_db.items():
        matches = 0
        details = []
        
        # Check Length
        if match_value(card_text, props.get('length')):
            matches += 1
            details.append(f"Length {props.get('length')}")
            
        # Check Width/Beam
        if match_value(card_text, props.get('width')):
            matches += 1
            details.append(f"Beam {props.get('width')}")
            
        # Check Speed
        if match_value(card_text, props.get('maxspeed')):
            matches += 1
            details.append(f"Speed {props.get('maxspeed')}")
            
        # Check Rudder/Turn (optional)
        if match_value(card_text, props.get('ruddermaxangle')):
            matches += 1
            details.append(f"Rudder {props.get('ruddermaxangle')}")

        if matches > best_match_count:
            best_match_count = matches
            best_match_model = model_name
            best_match_details = details

    if best_match_count >= 2:
        score += 30
        feedback.append(f"Data matches model '{best_match_model}' ({', '.join(best_match_details)})")
    elif best_match_count == 1:
        score += 15
        feedback.append(f"Weak data match to model '{best_match_model}' ({best_match_details[0]})")
    else:
        feedback.append("FAIL: Pilot card data values do not match any known vessel model")

    # === 3. Scenario Verification (30 pts) ===
    scen = result.get('scenario', {})
    
    # Environment
    env_content = scen.get('environment', '') or ''
    if 'Solent' in env_content:
        score += 5
        feedback.append("Scenario setting: Solent")
    else:
        feedback.append("FAIL: Scenario setting not Solent")
        
    # Visibility
    vis_match = re.search(r"VisibilityRange=([\d\.]+)", env_content)
    if vis_match and float(vis_match.group(1)) >= 8.0:
        score += 5
        feedback.append("Visibility good (>8nm)")
    else:
        feedback.append("FAIL: Visibility low or not set")
        
    # Ownship Position (Nab Tower area)
    own_content = scen.get('ownship', '') or ''
    lat_match = re.search(r"InitialLat=([\d\.\-]+)", own_content)
    long_match = re.search(r"InitialLong=([\d\.\-]+)", own_content)
    
    pos_ok = False
    if lat_match and long_match:
        lat, lon = float(lat_match.group(1)), float(long_match.group(1))
        # Nab Tower approx 50.67, -0.95. Tolerance +/- 0.1
        if 50.57 <= lat <= 50.77 and -1.05 <= lon <= -0.85:
            pos_ok = True
    
    if pos_ok:
        score += 10
        feedback.append("Ownship positioned near Nab Tower")
    else:
        feedback.append("FAIL: Ownship position incorrect or missing")

    # Traffic
    other_content = scen.get('othership', '') or ''
    traffic_count = 0
    count_match = re.search(r"Number=(\d+)", other_content)
    if count_match:
        traffic_count = int(count_match.group(1))
    
    if traffic_count >= 2:
        score += 10
        feedback.append(f"Traffic present ({traffic_count} vessels)")
    else:
        feedback.append("FAIL: Insufficient traffic vessels")

    # === 4. Config Verification (10 pts) ===
    bc5_content = result.get('bc5_content', '') or ''
    if "hide_instruments=0" in bc5_content or 'hide_instruments="0"' in bc5_content:
        score += 10
        feedback.append("Instruments enabled (hide_instruments=0)")
    else:
        feedback.append("FAIL: Instruments hidden or setting missing")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": ". ".join(feedback)
    }