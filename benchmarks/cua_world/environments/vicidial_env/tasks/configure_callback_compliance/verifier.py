#!/usr/bin/env python3
"""
Verifier for configure_callback_compliance task in Vicidial.

Checks if Campaign CB_SAFE was created with specific Scheduled Callback settings.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_callback_compliance(traj, env_info, task_info):
    """
    Verify the campaign configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result from container
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

    # Scoring configuration
    score = 0
    feedback_parts = []
    
    # 1. Campaign Existence (20 pts)
    if not result.get('campaign_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Campaign 'CB_SAFE' was not created."
        }
    
    score += 20
    feedback_parts.append("Campaign created")
    
    data = result.get('campaign_data', {})
    
    # 2. Callbacks Enabled (10 pts)
    if data.get('scheduled_callbacks') == metadata.get('expected_scheduled_callbacks', 'Y'):
        score += 10
    else:
        feedback_parts.append(f"Scheduled Callbacks not enabled (Got: {data.get('scheduled_callbacks')})")

    # 3. Days Limit (15 pts) - Integer check
    try:
        days_limit = int(data.get('scheduled_callbacks_days_limit', 0))
        expected_days = int(metadata.get('expected_days_limit', 14))
        if days_limit == expected_days:
            score += 15
        else:
            feedback_parts.append(f"Days limit incorrect (Got: {days_limit}, Expected: {expected_days})")
    except ValueError:
        feedback_parts.append("Days limit value invalid")

    # 4. Max Count (15 pts) - Integer check
    try:
        max_sched = int(data.get('max_scheduled_callbacks', 0))
        expected_max = int(metadata.get('expected_max_callbacks', 50))
        if max_sched == expected_max:
            score += 15
        else:
            feedback_parts.append(f"Max callbacks incorrect (Got: {max_sched}, Expected: {expected_max})")
    except ValueError:
        feedback_parts.append("Max callbacks value invalid")

    # 5. Alert Config (10 pts)
    if data.get('scheduled_callbacks_alert') == metadata.get('expected_alert', 'BLINK'):
        score += 10
    else:
        feedback_parts.append(f"Alert setting incorrect (Got: {data.get('scheduled_callbacks_alert')})")

    # 6. Hoarding Protection / Agent Limit (15 pts)
    if data.get('agent_only_callbacks_limitation') == metadata.get('expected_agent_limitation', 'Y'):
        score += 15
    else:
        feedback_parts.append("Agent only limitation not enabled")

    # 7. Count Method (10 pts)
    if data.get('scheduled_callbacks_count') == metadata.get('expected_count', 'LIVE'):
        score += 10
    else:
        feedback_parts.append(f"Count method incorrect (Got: {data.get('scheduled_callbacks_count')})")

    # 8. Active (5 pts)
    if data.get('active') == metadata.get('expected_active', 'Y'):
        score += 5
    else:
        feedback_parts.append("Campaign is not Active")

    # Feedback Formatting
    if score == 100:
        feedback = "Task completed successfully! All compliance rules configured correctly."
    else:
        feedback = " | ".join(feedback_parts)

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }