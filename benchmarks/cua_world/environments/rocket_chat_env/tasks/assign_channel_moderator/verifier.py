#!/usr/bin/env python3
"""
Verifier for assign_channel_moderator task.

Criteria:
1. API Confirmation: The Rocket.Chat API reports 'agent.user' has 'moderator' role in 'release-updates'.
2. Database Confirmation: MongoDB query confirms the subscription has the 'moderator' role.
3. Anti-Gaming: Task must take > 5 seconds (human speed limit) to ensure it wasn't pre-scripted excessively fast 
   (though primarily we rely on the setup script clearing the state).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_channel_moderator(traj, env_info, task_info):
    """
    Verify that agent.user was assigned the moderator role.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    max_score = 100
    feedback_parts = []
    
    # Extract data
    api_has_role = result.get('api_has_role', False)
    mongo_has_role = result.get('mongo_has_role', False)
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    app_running = result.get('app_was_running', False)

    # Criterion 1: API Check (Primary) - 60 points
    if api_has_role:
        score += 60
        feedback_parts.append("API confirms moderator role assigned.")
    else:
        feedback_parts.append("API does NOT show moderator role.")

    # Criterion 2: MongoDB Check (Secondary/Confirmation) - 30 points
    if mongo_has_role:
        score += 30
        feedback_parts.append("Database confirms moderator role assigned.")
    else:
        feedback_parts.append("Database does NOT show moderator role.")

    # Criterion 3: App Running - 10 points
    if app_running:
        score += 10
    else:
        feedback_parts.append("Browser was closed at end of task.")

    # Anti-gaming: Time check
    duration = task_end - task_start
    if duration < 3 and score > 0:
        score = 0
        feedback_parts.append(f"Task completed suspiciously fast ({duration}s).")
    
    # Consistency check
    if api_has_role != mongo_has_role:
        feedback_parts.append("WARNING: Inconsistent state between API and Database.")
        # If DB says yes but API says no (or vice versa), we trust the positive signal 
        # but penalize slightly for potential cache/sync issues? 
        # For simplicity, we just keep the points earned above.

    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }