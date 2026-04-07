#!/usr/bin/env python3
"""
Verifier for perseid_meteor_plan task.
Scores multiple independent signals: Location configuration, rendering flags, evidence of screenshots, and correct output file.
"""

import json
import os
import tempfile

def verify_perseid_meteor_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env missing"}
        
    # Copy and load the JSON result
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        json_path = f.name
    try:
        copy_from_env("/tmp/task_result.json", json_path)
        with open(json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(json_path):
            os.unlink(json_path)
            
    # Copy and read the plan text
    plan_text = ""
    if result.get("plan_exists"):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as f:
            txt_path = f.name
        try:
            copy_from_env("/tmp/perseid_plan.txt", txt_path)
            with open(txt_path, 'r', errors='ignore') as f:
                plan_text = f.read()
        except Exception:
            pass
        finally:
            if os.path.exists(txt_path):
                os.unlink(txt_path)
                
    score = 0
    feedback = []
    
    # Check 1: Location Settings (Flagstaff: ~35.215 N, 111.633 W)
    config = result.get("config", {})
    lat = config.get("lat_rad", 0.0)
    lon = config.get("lon_rad", 0.0)
    
    if abs(lat - 0.6146) <= 0.05:
        score += 15
        feedback.append("Latitude correct (Flagstaff).")
    else:
        feedback.append(f"Latitude incorrect: {lat:.4f} rad.")
        
    if abs(lon - -1.9484) <= 0.10:
        score += 5
        feedback.append("Longitude correct (Flagstaff).")
    else:
        feedback.append(f"Longitude incorrect: {lon:.4f} rad.")
        
    # Check 2: Display Flags
    if config.get("flag_constellation_drawing"):
        score += 10
        feedback.append("Constellation lines enabled.")
    else:
        feedback.append("Constellation lines NOT enabled.")
        
    if config.get("flag_constellation_name"):
        score += 10
        feedback.append("Constellation labels enabled.")
    else:
        feedback.append("Constellation labels NOT enabled.")
        
    if not config.get("flag_landscape"):
        score += 10
        feedback.append("Landscape disabled.")
    else:
        feedback.append("Landscape NOT disabled.")
        
    if config.get("flag_atmosphere"):
        score += 10
        feedback.append("Atmosphere enabled.")
    else:
        feedback.append("Atmosphere NOT enabled.")
        
    # Check 3: Screenshots capturing
    ss_count = result.get("new_screenshots", 0)
    if ss_count >= 2:
        score += 20
        feedback.append(f"Screenshots captured: {ss_count}.")
    elif ss_count == 1:
        score += 10
        feedback.append("Only 1 screenshot captured (expected at least 2).")
    else:
        feedback.append("No screenshots captured.")
        
    # Check 4: Observation Plan File & Content
    if result.get("plan_exists") and result.get("plan_created_during_task"):
        score += 10
        feedback.append("Observation plan file created.")
        
        # Verify keywords in the plan file
        text_lower = plan_text.lower()
        keywords = ["perseus", "moon", "perseid"]
        found = [kw for kw in keywords if kw in text_lower]
        
        if len(found) >= 2:
            score += 10
            feedback.append(f"Plan contains required keywords: {', '.join(found)}.")
        else:
            feedback.append("Plan is missing required observation keywords.")
    else:
        feedback.append("Observation plan file missing or not created during task.")
        
    # Determine pass/fail based on score threshold (60/100)
    passed = score >= 60
    return {"passed": passed, "score": score, "feedback": " ".join(feedback)}