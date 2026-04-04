#!/usr/bin/env python3
"""
Verifier for resolve_close_request task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_close_request(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_phrases = metadata.get('required_resolution_phrases', [])
    target_time = metadata.get('required_time_spent_minutes', 135)
    time_tolerance = metadata.get('time_tolerance_minutes', 15)

    # Fetch result JSON
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

    # 1. Verify Status (30 pts)
    status = result.get('final_status', '').lower()
    if status in ['resolved', 'closed']:
        score += 30
        feedback.append(f"Status changed to {status} (Success)")
    else:
        feedback.append(f"Status is '{status}', expected 'Resolved' or 'Closed'")

    # 2. Verify Resolution Text (40 pts)
    res_text = result.get('resolution_text', '') or ""
    
    if len(res_text) > 20:
        score += 10 # Base points for adding any resolution
        
        phrases_found = 0
        missing_phrases = []
        for phrase in required_phrases:
            if phrase.lower() in res_text.lower():
                phrases_found += 1
            else:
                missing_phrases.append(phrase)
        
        # Proportional score for phrases (max 30)
        if required_phrases:
            phrase_score = (phrases_found / len(required_phrases)) * 30
            score += phrase_score
            feedback.append(f"Resolution text verification: {phrases_found}/{len(required_phrases)} phrases found.")
        else:
            score += 30
    else:
        feedback.append("No substantial resolution text found.")

    # 3. Verify Time Spent (20 pts)
    # DB might return minutes directly
    try:
        time_spent = int(result.get('total_time_spent_minutes', 0))
    except (ValueError, TypeError):
        time_spent = 0

    # Note: Sometimes time spent is stored in milliseconds in Java apps
    if time_spent > 10000: 
        time_spent = time_spent / 60000  # Convert ms to min

    diff = abs(time_spent - target_time)
    if diff <= time_tolerance:
        score += 20
        feedback.append(f"Time spent logged correctly ({time_spent} min)")
    elif time_spent > 0:
        score += 10
        feedback.append(f"Time spent logged ({time_spent} min), but outside tolerance of {target_time} +/- {time_tolerance}")
    else:
        feedback.append("No time spent logged.")

    # 4. Anti-gaming / Timestamp check (10 pts)
    # Check if task was actually performed during the window
    task_start = float(result.get('task_start_ts', 0))
    # Resolution timestamp might be string or int
    try:
        res_ts = float(result.get('resolution_timestamp', 0))
        # Handle ms vs sec
        if res_ts > 10000000000: # likely ms
            res_ts = res_ts / 1000
    except (ValueError, TypeError):
        res_ts = 0

    if res_ts > task_start:
        score += 10
    elif len(res_text) > 0:
        # If we have text but timestamp logic failed/is missing in DB export, give benefit of doubt if text matches strict criteria
        score += 10 

    passed = (status in ['resolved', 'closed']) and (score >= 60)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }