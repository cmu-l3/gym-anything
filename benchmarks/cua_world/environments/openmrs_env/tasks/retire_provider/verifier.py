#!/usr/bin/env python3
"""
Verifier for retire_provider task (OpenMRS).

Verification Criteria:
1. Provider 'retired' status is true (60 pts)
2. Retire reason contains "Sabbatical" (20 pts)
3. Action was performed during the task window (anti-gaming) (10 pts)
4. VLM Verification: Agent navigated to System Admin / Provider Management (10 pts)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retire_provider(traj, env_info, task_info):
    """
    Verifies that the correct provider was retired with the correct reason.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_reason = metadata.get('expected_retire_reason', 'Sabbatical').lower()

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify Provider Status (60 pts)
    is_retired = result.get('is_retired', False)
    if is_retired:
        score += 60
        feedback_parts.append("Provider successfully retired")
    else:
        feedback_parts.append("Provider is NOT retired")

    # 3. Verify Reason (20 pts)
    actual_reason = result.get('retire_reason', '').lower()
    if expected_reason in actual_reason:
        score += 20
        feedback_parts.append(f"Reason matches ('{actual_reason}')")
    elif is_retired:
        # Partial credit if retired but wrong reason
        score += 5
        feedback_parts.append(f"Reason mismatch: expected '{expected_reason}', got '{actual_reason}'")
    else:
        feedback_parts.append("Reason not checked (not retired)")

    # 4. Anti-Gaming Timestamp Check (10 pts)
    # Ensure the change happened *after* task start
    timestamp_valid = result.get('timestamp_valid', False)
    if timestamp_valid and is_retired:
        score += 10
        feedback_parts.append("Action performed during task window")
    elif is_retired:
        feedback_parts.append("WARNING: Provider retired before task start? (Timestamp check failed)")
        score = 0  # Fail if pre-retired (gaming)

    # 5. VLM Trajectory Verification (10 pts)
    # Ensure they used the UI (Administration / Manage Providers)
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        You are analyzing screenshots of a user using the OpenMRS Electronic Health Record system.
        The user's goal is to 'Retire' a provider record.
        
        Look for these visual indicators in the sequence:
        1. Navigation to 'System Administration' or 'Advanced Administration'.
        2. A list of providers or a search for 'Eleanor'.
        3. A form or popup with a 'Retire' button or checkbox.
        4. Typing a reason for retiring (e.g., 'Sabbatical').
        
        Did the user navigate to an administration or provider management screen?
        Answer 'YES' or 'NO' and explain briefly.
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_response.get("success") and "YES" in vlm_response.get("parsed", {}).get("answer", "").upper():
                score += 10
                feedback_parts.append("VLM confirmed admin workflow navigation")
            elif "YES" in str(vlm_response.get("raw_response", "")).upper():
                # Fallback if parsing missed it but text has YES
                score += 10
                feedback_parts.append("VLM confirmed admin workflow navigation")
            else:
                feedback_parts.append("VLM did not clearly observe admin navigation")
        except Exception:
            feedback_parts.append("VLM verification skipped due to error")
    else:
        feedback_parts.append("No trajectory frames for VLM")

    # Final Pass/Fail
    # Must be retired AND valid timestamp to pass
    passed = (is_retired and timestamp_valid and score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }