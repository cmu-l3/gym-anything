#!/usr/bin/env python3
"""
Verifier for clinical_event_log_monitor task.

Scoring Breakdown (100 pts):
1. Device Creation (20 pts): Evidence of devices in logs/windows.
2. Script Quality (30 pts): Executable, correct path, parsing logic.
3. Script Output (15 pts): Output file exists, has data.
4. Documentation (35 pts): Format description, patterns, recommendations.

Gate Condition: Score 0 if no devices created AND no output files exist.
Pass Threshold: 60 pts.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_clinical_event_log_monitor(traj, env_info, task_info):
    # Setup copy
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    task_start = result.get('task_start', 0)
    
    # --- GATE CHECK ---
    # If no devices created and no files written, automatic fail
    dev_evidence = (result.get('log_has_device_1') or result.get('log_has_device_2') or 
                    result.get('window_increase', 0) > 0)
    files_exist = (result['script']['exists'] or result['output']['exists'] or result['doc']['exists'])
    
    if not dev_evidence and not files_exist:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "GATE FAIL: No devices created and no work files found."
        }

    # --- SCORING ---

    # 1. Device Creation (20 pts)
    # We look for evidence of 2 distinct devices.
    # Evidence sources: Log keywords OR Window titles.
    d1_ok = result.get('log_has_device_1') or result.get('window_has_device_1')
    d2_ok = result.get('log_has_device_2') or result.get('window_has_device_2')
    
    # Fallback: if specific keywords failed, check generic window increase
    # 2 new windows usually means 2 devices created
    win_inc = result.get('window_increase', 0)
    
    if d1_ok and d2_ok:
        score += 20
        feedback.append("Two distinct devices detected.")
    elif win_inc >= 2:
        score += 20
        feedback.append("Two devices detected via window count.")
    elif d1_ok or d2_ok or win_inc >= 1:
        score += 10
        feedback.append("One device detected (target was 2).")
    else:
        feedback.append("No devices detected.")

    # 2. Script Quality (30 pts)
    script = result.get('script', {})
    if script.get('exists'):
        score += 5
        if script.get('executable'):
            score += 10
            feedback.append("Script is executable.")
        else:
            feedback.append("Script exists but is NOT executable.")
            
        if script.get('has_shebang'):
            score += 5
        if script.get('has_logpath'):
            score += 5
        if script.get('has_commands'):
            score += 5
    else:
        feedback.append("Monitor script not found.")

    # 3. Script Output (15 pts)
    output = result.get('output', {})
    if output.get('exists'):
        # Anti-gaming: Timestamp check
        if output.get('mtime', 0) > task_start:
            score += 5
            if output.get('size', 0) > 20: # Not empty
                score += 5
                if output.get('has_numbers'):
                    score += 5
                    feedback.append("Output file has valid content.")
                else:
                    feedback.append("Output file missing numeric data.")
            else:
                feedback.append("Output file is empty.")
        else:
            feedback.append("Output file timestamp predates task start.")
    else:
        feedback.append("Summary output file not found.")

    # 4. Documentation (35 pts)
    doc = result.get('doc', {})
    if doc.get('exists'):
        if doc.get('mtime', 0) > task_start:
            score += 5
            if doc.get('size', 0) > 100: # Decent length
                score += 10
                if doc.get('has_keywords'):
                    score += 10
                    feedback.append("Documentation describes log structure.")
                if doc.get('has_recommendation'):
                    score += 10
                    feedback.append("Documentation includes recommendations.")
            else:
                feedback.append("Documentation file is too short.")
        else:
            feedback.append("Documentation timestamp predates task start.")
    else:
        feedback.append("Documentation file not found.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }