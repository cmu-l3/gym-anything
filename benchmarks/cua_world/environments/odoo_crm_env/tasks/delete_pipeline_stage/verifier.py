#!/usr/bin/env python3
"""
Verifier for delete_pipeline_stage task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_pipeline_stage(traj, env_info, task_info):
    """
    Verifies that:
    1. The 'Initial Review' stage is deleted (50 pts)
    2. Opportunities are moved to the 'New' stage (50 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error during verification script: {result['error']}"}

    score = 0
    feedback = []

    # 2. Check Stage Deletion (50 points)
    if result.get('stage_deleted'):
        score += 50
        feedback.append("Stage 'Initial Review' successfully deleted.")
    else:
        feedback.append("Stage 'Initial Review' still exists in the pipeline.")

    # 3. Check Opportunities (50 points total, 25 each)
    opp_statuses = result.get('opp_statuses', {})
    opp_names = ['Acme Corp Server Upgrade', 'GlobalTech Cloud Migration']
    
    for name in opp_names:
        status = opp_statuses.get(name)
        if not status or status == "missing":
            feedback.append(f"Opportunity '{name}' missing/deleted (should have been moved).")
        elif status.get('is_correct'):
            score += 25
            feedback.append(f"Opportunity '{name}' correctly moved to 'New'.")
        else:
            current = status.get('current_stage_name', 'Unknown')
            feedback.append(f"Opportunity '{name}' is in wrong stage '{current}' (expected 'New').")

    # 4. Final Assessment
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }