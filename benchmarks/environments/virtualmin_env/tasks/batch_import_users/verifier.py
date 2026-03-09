#!/usr/bin/env python3
"""
Verifier for batch_import_users@1 task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_import_users(traj, env_info, task_info):
    """
    Verify that the 3 users were imported correctly from the CSV.
    """
    # 1. Retrieve result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Data
    user_list_text = result.get("user_list_output", "")
    initial_count = int(result.get("initial_user_count", 0))
    final_count = int(result.get("final_user_count", 0))
    
    metadata = task_info.get("metadata", {})
    expected_users = metadata.get("expected_users", [])
    expected_delta = metadata.get("expected_delta", 3)

    score = 0
    feedback_parts = []
    
    # 3. Verify Specific Users (20 pts each = 60 pts)
    # We parse the multiline output. It looks like:
    # Username: dave.bowman.acmecorp
    # Real name: David Bowman
    # ...
    
    users_found_count = 0
    
    for user_def in expected_users:
        username = user_def["username"] # e.g., dave.bowman
        real_name = user_def["real_name"]
        
        # Virtualmin might append domain to username (e.g., dave.bowman.acmecorp)
        # or keep it as email address. We look for the base username in the output block.
        
        # Simple check: Is the username present?
        # "Username: dave.bowman" or "Username: dave.bowman@acmecorp.test"
        if f"Username: {username}" in user_list_text or \
           f"Username: {user_def['full_email']}" in user_list_text:
            
            score += 20
            users_found_count += 1
            feedback_parts.append(f"User {username} found (+20)")
            
            # Check Real Name (5 pts extra per user included in the 60 total? 
            # Original plan said 20 for creation, 15 for names total.
            # Let's stick to the README plan: 20 per user creation, 15 total for names)
            pass
        else:
            feedback_parts.append(f"User {username} NOT found")

    # 4. Verify Real Names (15 pts)
    # Only award if all names match (or proportional? Plan said 15 pts total)
    names_correct = True
    for user_def in expected_users:
        username = user_def["username"]
        real_name = user_def["real_name"]
        
        # Regex or string search for the block
        # We look for "Real name: David Bowman" somewhere near the username
        # Since parsing text blocks is tricky without regex, we'll do a simple existence check
        # This assumes unique real names which is true for this task
        if f"Real name: {real_name}" not in user_list_text:
            names_correct = False
            feedback_parts.append(f"Real name for {username} incorrect or missing")
    
    if names_correct and users_found_count == 3:
        score += 15
        feedback_parts.append("All real names correct (+15)")
    elif names_correct and users_found_count > 0:
        # Partial credit for names if some users exist
        score += 5
        feedback_parts.append("Found real names correct (+5)")

    # 5. Verify Count Delta (15 pts)
    actual_delta = final_count - initial_count
    if actual_delta == expected_delta:
        score += 15
        feedback_parts.append(f"User count increased by exactly {expected_delta} (+15)")
    elif actual_delta > expected_delta:
        score += 5
        feedback_parts.append(f"User count increased by {actual_delta} (expected {expected_delta}) (+5)")
    else:
        feedback_parts.append(f"User count delta incorrect: {actual_delta}")

    # 6. Batch Mode Heuristic (10 pts)
    # If all 3 users created successfully and names are correct, we assume efficient batch processing 
    # was used or at least the result is perfect.
    if users_found_count == 3 and names_correct:
        score += 10
        feedback_parts.append("Process completed successfully (+10)")

    # Normalize score
    score = min(score, 100)
    passed = (score >= 75)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }