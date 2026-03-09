#!/usr/bin/env python3
"""
Verifier for Manual Data Entry Task.

Checks if the agent entered 3 specific responses into the LimeSurvey database correctly.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manual_data_entry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_data = metadata.get('expected_responses', [])
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Table exists and count is correct (Gate)
    if not result.get('table_exists'):
        return {"passed": False, "score": 0, "feedback": "Survey response table does not exist. Survey may not be active."}
    
    response_count = result.get('response_count', 0)
    
    # Scoring Breakdown
    # 1. Response Count (15 pts)
    if response_count == 3:
        score += 15
        feedback_parts.append("Correct number of responses (3).")
    elif response_count > 3:
        score += 5
        feedback_parts.append(f"Too many responses ({response_count}), expected 3.")
    elif response_count > 0:
        score += 5
        feedback_parts.append(f"Too few responses ({response_count}), expected 3.")
    else:
        return {"passed": False, "score": 0, "feedback": "No responses found in database."}

    # 2. Check Data Content (20 pts per response = 60 pts total)
    responses = result.get('responses', [])
    
    # We need to match responses. Since order might vary if agent deleted/re-entered, 
    # we'll look for best matches for each expected response.
    
    matched_indices = set()
    total_data_score = 0
    
    for i, expected in enumerate(expected_data):
        best_match_score = 0
        best_match_idx = -1
        
        # Define expected values
        ex_zip = expected['zip']
        ex_health = expected['health']
        ex_days = float(expected['days'])
        ex_insured = expected['insured']
        ex_age = float(expected['age'])
        
        for j, actual in enumerate(responses):
            if j in matched_indices: continue
            
            current_score = 0
            # Compare fields
            # ZIP
            if str(actual.get('QZIP', '')).strip() == ex_zip:
                current_score += 4
            
            # Health (Code)
            if str(actual.get('QHEALTH', '')) == ex_health:
                current_score += 4
            
            # Days (Numeric)
            try:
                if float(actual.get('QDAYS', -1)) == ex_days:
                    current_score += 4
            except: pass
            
            # Insured (Code)
            if str(actual.get('QINSURED', '')) == ex_insured:
                current_score += 4
            
            # Age (Numeric)
            try:
                if float(actual.get('QAGE', -1)) == ex_age:
                    current_score += 4
            except: pass
            
            if current_score > best_match_score:
                best_match_score = current_score
                best_match_idx = j
        
        if best_match_idx != -1:
            matched_indices.add(best_match_idx)
            total_data_score += best_match_score
            if best_match_score == 20:
                feedback_parts.append(f"Response {i+1} perfectly matched.")
            else:
                feedback_parts.append(f"Response {i+1} partially matched ({best_match_score}/20 pts).")
        else:
            feedback_parts.append(f"Response {i+1} missing or no close match found.")

    score += total_data_score

    # 3. Timestamps / Anti-Gaming (15 pts)
    # Check if responses were added after task start
    task_start = float(result.get('task_start_time', 0))
    valid_timestamps = 0
    for r in responses:
        sub_date = r.get('submitdate')
        if sub_date:
            try:
                # Format: YYYY-MM-DD HH:MM:SS
                dt = datetime.strptime(sub_date, "%Y-%m-%d %H:%M:%S")
                if dt.timestamp() > task_start:
                    valid_timestamps += 1
            except: pass
    
    if valid_timestamps == response_count and response_count > 0:
        score += 15
        feedback_parts.append("Timestamps valid.")
    elif valid_timestamps > 0:
        score += 10
        feedback_parts.append(f"Some timestamps valid ({valid_timestamps}/{response_count}).")
    
    # 4. Consistency Check (10 pts)
    # Implicitly handled by matching, but bonus if we found distinct matches for all 3
    if len(matched_indices) == 3:
        score += 10
        feedback_parts.append("All expected responses accounted for.")

    passed = score >= 70 and response_count >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }