#!/usr/bin/env python3
"""
Verifier for manage_mail_queue task.

Criteria:
1. All spam emails (sender: marketing@acmecorp.test) must be DELETED.
2. All legitimate emails (sender: support@acmecorp.test) must be PRESERVED.
3. Queue must not be empty (unless only spam existed, which is not the case here).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_mail_queue(traj, env_info, task_info):
    """
    Verifies the agent correctly filtered the mail queue.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define Targets
    METADATA = task_info.get('metadata', {})
    INITIAL_LEGIT = METADATA.get('initial_legit_count', 5)
    
    # 1. Read Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result from environment: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    remaining_spam = result.get('remaining_spam_count', -1)
    remaining_legit = result.get('remaining_legit_count', -1)
    total_queue = result.get('total_queue_count', -1)

    score = 0
    feedback = []
    
    # CRITERION 1: Removal of Spam (50 points)
    if remaining_spam == 0:
        score += 50
        feedback.append("Success: All marketing spam removed.")
    elif remaining_spam > 0:
        feedback.append(f"Fail: {remaining_spam} spam emails still in queue.")
    else:
        feedback.append("Error reading queue state.")

    # CRITERION 2: Preservation of Legit Mail (40 points)
    if remaining_legit == INITIAL_LEGIT:
        score += 40
        feedback.append(f"Success: All {INITIAL_LEGIT} support emails preserved.")
    elif remaining_legit < INITIAL_LEGIT:
        # Penalize heavily for data loss
        lost = INITIAL_LEGIT - remaining_legit
        feedback.append(f"Fail: Deleted {lost} legitimate support emails.")
    else:
        # Should not happen unless duplicate delivery, which shouldn't count against
        score += 40
        feedback.append(f"Note: More support emails found than expected ({remaining_legit}).")

    # CRITERION 3: VLM Trajectory Verification (10 points)
    # Did the agent actually use the UI?
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = (
        "Analyze these screenshots of a Webmin/Virtualmin session. "
        "Does the user navigate to the 'Mail Queue' or 'Postfix' module? "
        "Do they select specific emails or perform a delete action? "
        "Answer 'YES' or 'NO' and explain briefly."
    )
    
    # Simple VLM check
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_content = vlm_res.get('text', '').upper()
        if "YES" in vlm_content:
            score += 10
            feedback.append("VLM: Navigation to mail queue confirmed.")
        else:
            feedback.append("VLM: Navigation unclear from screenshots.")
    except Exception:
        # Fallback if VLM fails: If score is high (90), assume they used UI as CLI is also valid
        if score >= 90:
            score += 10
            feedback.append("VLM skipped, assuming success based on outcome.")

    # Final Pass/Fail Logic
    # Strict requirement: Must delete all spam AND preserve all legit
    passed = (remaining_spam == 0) and (remaining_legit == INITIAL_LEGIT)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }