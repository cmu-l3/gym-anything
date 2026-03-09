#!/usr/bin/env python3
"""
Verifier for configure_mailbox_permissions task.

SCORING CRITERIA:
1. Sarah Chen has access to Field Service mailbox (60 points)
2. Marcus Rivera does NOT have access (25 points)
3. State actually changed from initial (Anti-gaming) (15 points)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_mailbox_permissions(traj, env_info, task_info):
    """Verify mailbox permissions were configured correctly."""
    
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
    feedback_parts = []
    
    # Check if entities still exist (sanity check)
    if not result.get('mailbox_exists', False) or not result.get('sarah_exists', False) or not result.get('marcus_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Critical Error: Mailbox or Users were deleted during the task."
        }

    # CRITERION 1: Sarah Chen has access (60 points)
    current_sarah = int(result.get('current_sarah_access', 0))
    if current_sarah >= 1:
        score += 60
        feedback_parts.append("Sarah Chen granted access (+60)")
    else:
        feedback_parts.append("Sarah Chen NOT granted access (0)")

    # CRITERION 2: Marcus Rivera does NOT have access (25 points)
    current_marcus = int(result.get('current_marcus_access', 0))
    if current_marcus == 0:
        score += 25
        feedback_parts.append("Marcus Rivera access restricted (+25)")
    else:
        feedback_parts.append("Marcus Rivera incorrectly has access (0)")

    # CRITERION 3: State changed from initial (15 points)
    # Anti-gaming: Ensure Sarah didn't have access before (which she shouldn't based on setup)
    # and that the current state is actually different.
    initial_sarah = int(result.get('initial_sarah_access', 0))
    
    if current_sarah >= 1 and initial_sarah == 0:
        score += 15
        feedback_parts.append("Permissions state successfully modified (+15)")
    elif current_sarah >= 1 and initial_sarah >= 1:
        feedback_parts.append("No state change detected - Sarah already had access (0)")
    elif current_sarah == 0:
        feedback_parts.append("No state change detected - Sarah still has no access (0)")

    # Determine pass/fail
    # Threshold: 60 points. Basically, Sarah MUST have access.
    # Ideally Marcus should not, but if Sarah has access and Marcus does too, score is 75, which passes.
    # This aligns with "Grant Sarah access" being the primary goal, but security hygiene (Marcus) is secondary.
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }