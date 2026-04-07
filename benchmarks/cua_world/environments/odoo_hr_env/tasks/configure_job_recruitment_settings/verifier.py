#!/usr/bin/env python3
"""
Verifier for configure_job_recruitment_settings task.

Checks if the specific 'Marketing and Community Manager' job record was updated with:
1. Email Alias: 'social-guru'
2. Recruiter: 'Marc Demo'
3. Target: 3
"""

import json
import os
import tempfile

def verify_configure_job_recruitment_settings(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check if we successfully queried the record
    if not result.get("job_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The target job position was deleted or could not be found."
        }

    score = 0
    feedback_parts = []
    
    # 1. Check Integrity (10 pts)
    # If job_found is true, we queried the ID from setup, so we know it's the same record.
    score += 10
    
    # 2. Check Email Alias (30 pts)
    actual_alias = (result.get("alias_name") or "").lower()
    expected_alias = task_info['metadata']['expected_alias']
    if actual_alias == expected_alias:
        score += 30
        feedback_parts.append("Email alias correct.")
    else:
        feedback_parts.append(f"Email alias incorrect (expected '{expected_alias}', got '{actual_alias}').")

    # 3. Check Recruiter (30 pts)
    actual_recruiter = (result.get("recruiter_name") or "").lower()
    expected_recruiter = task_info['metadata']['expected_recruiter_name'].lower()
    
    # Loose matching for names (contains check)
    if expected_recruiter in actual_recruiter:
        score += 30
        feedback_parts.append("Recruiter correct.")
    else:
        feedback_parts.append(f"Recruiter incorrect (expected '{expected_recruiter}', got '{actual_recruiter}').")

    # 4. Check Target (30 pts)
    actual_target = result.get("target_count")
    expected_target = task_info['metadata']['expected_target']
    
    if actual_target == expected_target:
        score += 30
        feedback_parts.append("Hiring target correct.")
    else:
        feedback_parts.append(f"Hiring target incorrect (expected {expected_target}, got {actual_target}).")

    # Final Score
    # Pass threshold: 70 (Must get at least 2 major fields correct + integrity)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }