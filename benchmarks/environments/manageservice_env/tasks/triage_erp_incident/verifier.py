#!/usr/bin/env python3
"""
Verifier for triage_erp_incident task.
"""

import json
import os
import sys
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_triage_erp_incident(traj, env_info, task_info):
    """
    Verify that the agent correctly triaged the ERP incident.
    """
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load result JSON
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

    # 3. Validation Logic
    if not result.get("request_found"):
        return {"passed": False, "score": 0, "feedback": "Target request not found in database."}

    score = 0
    feedback_parts = []
    
    # Expected values
    exp_cat = task_info['metadata'].get("expected_category", "Enterprise Applications")
    exp_sub = task_info['metadata'].get("expected_subcategory", "Payroll")
    exp_pri = task_info['metadata'].get("expected_priority", "High")
    exp_grp = task_info['metadata'].get("expected_group", "ERP Support")

    # Check Category (25 pts)
    act_cat = result.get("category", "")
    if act_cat == exp_cat:
        score += 25
        feedback_parts.append("Category correct")
    else:
        feedback_parts.append(f"Category incorrect (Expected: {exp_cat}, Got: {act_cat})")

    # Check Subcategory (25 pts)
    act_sub = result.get("subcategory", "")
    if act_sub == exp_sub:
        score += 25
        feedback_parts.append("Subcategory correct")
    else:
        feedback_parts.append(f"Subcategory incorrect (Expected: {exp_sub}, Got: {act_sub})")

    # Check Priority (25 pts)
    act_pri = result.get("priority", "")
    if act_pri == exp_pri:
        score += 25
        feedback_parts.append("Priority correct")
    else:
        feedback_parts.append(f"Priority incorrect (Expected: {exp_pri}, Got: {act_pri})")

    # Check Group (25 pts)
    act_grp = result.get("group", "")
    if act_grp == exp_grp:
        score += 25
        feedback_parts.append("Group correct")
    else:
        feedback_parts.append(f"Group incorrect (Expected: {exp_grp}, Got: {act_grp})")

    # 4. Optional VLM Check (Tie-breaker or confirmation)
    # If score is > 0 but < 100, or to confirm UI interaction
    # We won't deduct points based on VLM if DB is correct, but can use it for feedback
    # or to catch edge cases where DB update happened magically (unlikely).
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }