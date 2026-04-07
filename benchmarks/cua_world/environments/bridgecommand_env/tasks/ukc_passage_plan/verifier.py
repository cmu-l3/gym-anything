#!/usr/bin/env python3
import json
import logging
import os
import tempfile
import re

logger = logging.getLogger(__name__)

def verify_ukc_passage_plan(traj, env_info, task_info):
    """
    Verify UKC Passage Planning task.
    
    Scoring Criteria:
    1. Passage Plan Math (30 pts):
       - Squat calc correct (~0.30m)
       - Required tide correct (~2.90m)
    2. Scenario Configuration (40 pts):
       - Scenario exists and was created during task
       - Start time falls within safe window (Morning: 06:00-09:00 start)
       - Location is Solent
    3. Radar Settings (15 pts):
       - Full radar enabled, Max range 48, Res 128
    4. Document Quality (15 pts):
       - Plan file exists and contains keywords (Squat, Barrass, Window)
    """
    
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- 1. Passage Plan Math & Document Content (45 pts total) ---
    plan_content = result.get('plan_content', '').lower()
    plan_exists = result.get('plan_exists', False)
    
    if plan_exists and len(plan_content) > 100:
        score += 15
        feedback.append("Passage plan document created.")
        
        # Check Squat (Expected: 0.2952 -> 0.29 or 0.30)
        if re.search(r"0\.29|0\.30", plan_content):
            score += 10
            feedback.append("Squat calculation correct (found 0.29/0.30).")
        else:
            feedback.append("Squat calculation value not found in text.")

        # Check Required Tide (Expected: ~2.90)
        if re.search(r"2\.9|2\.8|3\.0", plan_content):
            score += 5
            feedback.append("Required tidal height correct (found ~2.9).")
        else:
            feedback.append("Required tidal height not found in text.")
            
        # Check Keywords
        if "barrass" in plan_content and "window" in plan_content:
            score += 5
            feedback.append("Plan contains required methodology keywords.")
    else:
        feedback.append("Passage plan document missing or empty.")

    # --- 2. Scenario Configuration (40 pts) ---
    scenario_exists = result.get('scenario_exists', False)
    start_time_str = result.get('start_time', '')
    setting = result.get('setting', '').lower()
    
    if scenario_exists:
        score += 10
        feedback.append("Scenario directory created.")
        
        # Verify Setting
        if "solent" in setting:
            score += 5
            feedback.append("Scenario setting correct (Solent).")
        else:
            feedback.append(f"Incorrect scenario setting: {setting}")
            
        # Verify Start Time
        # Optimal window is ~08:00-11:00. Start time should be 1h before -> 06:00 to 09:00
        # Accepts float string like "6.5" or "07:30" (BC uses decimal hours)
        try:
            start_time = float(start_time_str)
            # Acceptable range: 06.0 to 09.0 (Morning window prep)
            if 6.0 <= start_time <= 9.5:
                score += 25
                feedback.append(f"Scenario start time ({start_time}) is optimal for safe transit.")
            elif 19.0 <= start_time <= 22.0:
                # Evening window is technically safe but less optimal due to darkness/lower margin
                score += 15
                feedback.append(f"Scenario start time ({start_time}) is safe (evening window), but morning was optimal.")
            else:
                feedback.append(f"Scenario start time ({start_time}) is outside optimal safe windows (Need 6.0-9.0 or 19.0-22.0).")
        except ValueError:
            feedback.append(f"Invalid start time format: {start_time_str}")
    else:
        feedback.append("Scenario not created or not newer than task start.")

    # --- 3. Radar Configuration (15 pts) ---
    radar = result.get('radar_config', {})
    
    # Full Radar (1 or True)
    if radar.get('full_radar') in ['1', 'true', 'True']:
        score += 5
    
    # Max Range (48)
    if radar.get('max_range') == '48':
        score += 5
        
    # Resolution (128)
    if radar.get('range_res') == '128':
        score += 5
        
    if score >= 100:
        feedback.append("Radar configuration correct.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }