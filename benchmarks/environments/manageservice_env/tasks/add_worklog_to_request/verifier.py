#!/usr/bin/env python3
"""
Verifier for add_worklog_to_request task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_worklog(traj, env_info, task_info):
    """
    Verifies if the agent added the correct work log entry.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata / Expectations
    metadata = task_info.get('metadata', {})
    expected_time_mins = metadata.get('expected_time_minutes', 150)
    required_keywords = metadata.get('required_keywords', ["MTU", "VPN"])
    
    score = 0
    max_score = 100
    feedback = []
    
    # 1. Load Result JSON
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

    worklogs = result.get('worklogs', [])
    task_start = result.get('task_start_ts', 0)
    
    # Filter for worklogs created AFTER task start (Anti-gaming)
    # SDP timestamps are usually in milliseconds
    valid_worklogs = []
    for wl in worklogs:
        try:
            # created_time might be string
            ct = int(wl.get('created_time', 0))
            if ct > task_start:
                valid_worklogs.append(wl)
        except:
            pass
            
    # Check 1: Did we add ANY worklog? (25 pts)
    if not valid_worklogs:
        feedback.append("No new work log entries found created during the task session.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
    
    score += 25
    feedback.append("New work log entry detected.")
    
    # Check 2: Verify Content of the best matching worklog
    best_match_score = 0
    best_log = None
    
    for wl in valid_worklogs:
        current_entry_score = 0
        desc = wl.get('description', '').lower()
        time_val = 0
        try:
            time_val = int(wl.get('time_spent', 0))
        except:
            pass
        
        # Time Check (20 pts)
        # SDP usually stores time_spent in milliseconds
        # 2h 30m = 150 mins = 9,000,000 ms
        # Allow +/- 5 minutes tolerance (300,000 ms)
        expected_ms = expected_time_mins * 60 * 1000
        tolerance_ms = 5 * 60 * 1000
        
        time_ok = False
        if abs(time_val - expected_ms) < tolerance_ms:
            current_entry_score += 20
            time_ok = True
        else:
            # Fallback: maybe stored in minutes?
            if abs(time_val - expected_time_mins) < 5:
                 current_entry_score += 20
                 time_ok = True
        
        # Keyword Check (30 pts)
        keywords_found = 0
        for kw in required_keywords:
            if kw.lower() in desc:
                keywords_found += 1
        
        kw_score = 0
        if len(required_keywords) > 0:
            kw_score = (keywords_found / len(required_keywords)) * 30
        current_entry_score += kw_score
        
        if current_entry_score > best_match_score:
            best_match_score = current_entry_score
            best_log = wl

    score += best_match_score
    
    if best_log:
        feedback.append(f"Best entry matched {int(best_match_score)}/50 content points.")
        if best_match_score < 40:
            feedback.append("Check time value (expected 2h30m) and description details.")
    
    # Check 3: VLM Verification (25 pts)
    # We verify that the worklog is actually visible in the UI
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        prompt = "Is there a work log or time entry visible in this ServiceDesk Plus screenshot? Does it show '2 hours' or '2:30'?"
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer_bool', False):
             vlm_score = 25
             feedback.append("Visual verification confirmed work log visibility.")
        elif vlm_res.get('success'):
             # Partial credit if UI looks correct but specific text ambiguous
             vlm_score = 15
             feedback.append("Visual verification ambiguous but UI correct.")
    
    score += vlm_score

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }