#!/usr/bin/env python3
"""
Verifier for quota_demographic_sampling task.

Verifies:
1. Survey is active.
2. Three specific quotas exist with correct limits (200, 200, 50).
3. Quotas are correctly linked to Gender question answers (M, F, NB).
4. Quota action is set to Terminate.
5. Message is configured correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quota_demographic_sampling(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Expected config from metadata
    # Male(M): 200, Female(F): 200, Non-binary(NB): 50
    expected_map = {
        "M": 200,
        "F": 200,
        "NB": 50
    }
    
    # 1. Survey Activation (20 pts)
    is_active = result.get("active", "N")
    if is_active == "Y":
        score += 20
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    quotas = result.get("quotas", [])
    
    # 2. Quota Existence and Configuration (20 pts for >0 quotas, up to 60 for correct config)
    if not quotas:
        return {"passed": False, "score": score, "feedback": "No quotas found."}
    
    # Analyze quotas found
    # We need to match observed quotas to expected ones based on the linked answer code
    # If a quota has no members, we can't be sure what it is intended for
    
    matched_quotas = 0
    correct_limits = 0
    correct_messages = 0
    correct_actions = 0
    
    found_codes = []

    for q in quotas:
        # Check Action (Default is 0 or 1 depending on version, usually 1=Terminate in DB)
        # Note: In LimeSurvey DB, 'action' 1 usually maps to Terminate. 
        # Since the task asks for "Terminate survey", we check if it's set.
        # However, defaults vary. Let's be lenient on the specific integer if behavior is correct,
        # but 0 is usually "Report only". 1 is Terminate.
        if q.get("action") == 1: 
            correct_actions += 1

        # Check Message
        msg = q.get("message", "").lower()
        if "target number of responses" in msg:
            correct_messages += 1
            
        # Check Members
        members = q.get("members", [])
        if not members:
            continue
            
        # Assuming one member per quota for this task
        # We look at the first member's answer code
        code = members[0].get("answer_code")
        limit = q.get("limit")
        
        if code in expected_map:
            found_codes.append(code)
            expected_limit = expected_map[code]
            
            # Check Limit
            if limit == expected_limit:
                correct_limits += 1
                feedback.append(f"Quota for '{code}' has correct limit ({limit}).")
            else:
                feedback.append(f"Quota for '{code}' has WRONG limit (Found: {limit}, Expected: {expected_limit}).")
        else:
            feedback.append(f"Found quota for unexpected answer code: {code}")

    # Scoring Logic
    
    # Existence of relevant quotas (linked to correct answers)
    unique_found = len(set(found_codes))
    if unique_found >= 3:
        score += 25 # Found all 3 intended quotas
    elif unique_found > 0:
        score += 10 * unique_found
        feedback.append(f"Only found {unique_found}/3 required quotas.")
    
    # Correct Limits
    if correct_limits >= 3:
        score += 25
    elif correct_limits > 0:
        score += 8 * correct_limits
    
    # Correct Messages (10 pts)
    if correct_messages >= 3:
        score += 10
    elif correct_messages > 0:
        score += 3
        
    # Correct Actions (20 pts)
    # If quotas terminate
    if correct_actions >= 3:
        score += 20
    elif correct_actions > 0:
        score += 5
        
    passed = (score >= 70) and (is_active == "Y")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }