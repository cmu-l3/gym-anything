#!/usr/bin/env python3
"""
Verifier for terminate_recurring_event_series task.

Criteria:
1. No future events exist after the target Friday (40 pts)
2. The event on the target Friday still exists (20 pts)
3. Past events still exist (history preserved) (20 pts)
4. Recurrence rule was correctly modified to 'until' specific date (20 pts)
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_terminate_recurring_event_series(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read result from container
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Database check failed: {result['error']}"}

    score = 0
    feedback = []
    
    # 2. Evaluate Criteria
    
    # Criterion 1: No Future Events (40 pts)
    future_count = result.get("future_event_count", 999)
    if future_count == 0:
        score += 40
        feedback.append("Success: No future events found after target date.")
    else:
        feedback.append(f"Fail: Found {future_count} events after the target date.")

    # Criterion 2: Target Event Exists (20 pts)
    target_exists = result.get("target_event_exists", False)
    if target_exists:
        score += 20
        feedback.append("Success: Meeting on target Friday preserved.")
    else:
        feedback.append("Fail: Meeting on target Friday is missing.")

    # Criterion 3: History Preserved (20 pts)
    past_count = result.get("past_event_count", 0)
    if past_count > 0:
        score += 20
        feedback.append(f"Success: {past_count} past meetings preserved.")
    else:
        feedback.append("Fail: Past meetings were deleted (series likely deleted entirely).")

    # Criterion 4: Recurrence Rule Correctness (20 pts)
    # The clean way is to set end_type='until' and until=TARGET_DATE
    rec_info = result.get("recurrence_info", {})
    end_type = rec_info.get("end_type")
    until_date = rec_info.get("until")
    target_date = result.get("target_date")
    
    rule_correct = False
    if end_type == 'until' and until_date == target_date:
        rule_correct = True
        score += 20
        feedback.append("Success: Recurrence rule set to 'Until' target date.")
    elif end_type == 'count':
        # Technically valid if they calculated the count exactly right, but less robust
        # We give partial credit if future_count is 0 but method was 'count'
        if future_count == 0:
            score += 10
            feedback.append("Partial: Used 'Number of repetitions' instead of 'End date'.")
    else:
        # If they just deleted future events individually (detached them), future_count might be 0
        # but the rule might still be 'forever'.
        if future_count == 0 and past_count > 0:
             feedback.append("Note: Achieved result possibly by manual deletion rather than rule change.")

    # Final result
    passed = (score >= 80) # Needs to preserve history + stop future + keep target
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }