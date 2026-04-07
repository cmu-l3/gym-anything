#!/usr/bin/env python3
"""
Verifier for purge_stale_leave_requests task.

Verifies that:
1. Specific stale draft requests created in setup are DELETED.
2. Specific future draft requests created in setup are PRESERVED.
3. Specific past/future confirmed requests created in setup are PRESERVED.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_purge_stale_leave_requests(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error in result generation: {result['error']}"}

    scenario = result.get("scenario", {})
    results = result.get("results", {})

    # 1. Check Stale Drafts (Target: Should be EMPTY)
    created_stale = set(scenario.get("stale_draft_ids", []))
    remaining_stale = set(results.get("stale_remaining_ids", []))
    
    stale_deleted_count = len(created_stale) - len(remaining_stale)
    total_stale = len(created_stale)
    
    # 2. Check Safety - Future Drafts (Target: Should match created)
    created_future_draft = set(scenario.get("future_draft_ids", []))
    remaining_future_draft = set(results.get("future_draft_remaining_ids", []))
    future_draft_preserved = (created_future_draft == remaining_future_draft)

    # 3. Check Safety - History/Active (Target: Should match created)
    created_past_conf = set(scenario.get("past_confirmed_ids", []))
    remaining_past_conf = set(results.get("past_confirmed_remaining_ids", []))
    past_conf_preserved = (created_past_conf == remaining_past_conf)

    created_future_conf = set(scenario.get("future_confirmed_ids", []))
    remaining_future_conf = set(results.get("future_confirmed_remaining_ids", []))
    future_conf_preserved = (created_future_conf == remaining_future_conf)

    # Scoring
    score = 0
    feedback = []

    # Criterion 1: Stale Deleted (40 pts)
    if total_stale > 0:
        if len(remaining_stale) == 0:
            score += 40
            feedback.append("All stale drafts deleted.")
        else:
            partial = (stale_deleted_count / total_stale) * 40
            score += partial
            feedback.append(f"Deleted {stale_deleted_count}/{total_stale} stale drafts.")
    else:
        # Fallback if setup failed to create data
        feedback.append("No stale drafts were created to test deletion.")

    # Criterion 2: Future Drafts Preserved (30 pts)
    if future_draft_preserved:
        score += 30
        feedback.append("Future drafts preserved.")
    else:
        missing = len(created_future_draft) - len(remaining_future_draft)
        feedback.append(f"CRITICAL: {missing} future drafts were incorrectly deleted.")

    # Criterion 3: History/Active Preserved (30 pts)
    history_ok = past_conf_preserved and future_conf_preserved
    if history_ok:
        score += 30
        feedback.append("History and active requests preserved.")
    else:
        feedback.append("CRITICAL: Confirmed/Approved requests were incorrectly deleted.")

    passed = (score >= 99)  # Require perfection for data hygiene tasks

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback),
        "details": {
            "stale_remaining": list(remaining_stale),
            "future_draft_remaining": list(remaining_future_draft)
        }
    }