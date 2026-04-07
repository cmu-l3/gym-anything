#!/usr/bin/env python3
"""
Verifier for add_user_account task in FreeMED.

Uses copy_from_env to read exported verification data from the container.
Also employs a trajectory VLM check to ensure the UI was interacted with, 
preventing SQL-injection/terminal bypasses.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these screenshots from an agent's trajectory interacting with FreeMED.

Task context: The agent was instructed to create a new user account using the FreeMED administration interface.

Look for evidence of proper UI interaction:
1. Is the FreeMED web interface open?
2. Did the agent navigate to the "Administration", "System", or "User Management" section?
3. Is there evidence of filling out a form with user details (e.g., username "smitchell", First Name "Sarah", User Type "phy")?
4. Make sure this was done via the web browser UI, NOT by opening a terminal and typing SQL commands.

Respond in JSON format:
{
    "used_web_ui": true/false,
    "terminal_shortcut_used": true/false,
    "confidence": "low/medium/high",
    "observations": "brief summary of what is seen"
}
"""


def verify_add_user_account(traj, env_info, task_info):
    """
    Verify that the 'smitchell' user account was correctly added to FreeMED.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Obtain expected metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_fname', 'Sarah')
    expected_lname = metadata.get('expected_lname', 'Mitchell')
    expected_mname = metadata.get('expected_mname', 'Anne')
    expected_usertype = metadata.get('expected_usertype', 'phy')
    expected_description = metadata.get('expected_description', 'Nurse Practitioner')
    expected_password_hash = metadata.get('expected_password_hash', '91f7a6350d754bbcb11596708b76dfb3')

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        copy_from_env("/tmp/add_user_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring variables
    score = 0
    feedback_parts = []
    
    user_exists = result.get('user_exists', False)
    initial_count = int(result.get('initial_user_count', 0))
    current_count = int(result.get('current_user_count', 0))
    user_data = result.get('user_data', {})

    # VLM Trajectory Check (Anti-gaming for terminal SQL inserts)
    used_web_ui = True
    vlm_feedback = "UI interaction verified."
    if 'query_vlm' in env_info:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                vlm_result = env_info['query_vlm'](prompt=build_vlm_prompt(), images=frames)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    used_web_ui = parsed.get("used_web_ui", True)
                    terminal_used = parsed.get("terminal_shortcut_used", False)
                    if terminal_used or not used_web_ui:
                        used_web_ui = False
                        vlm_feedback = "VLM indicated the terminal might have been used instead of the UI."
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed, proceeding with DB checks: {e}")

    if not used_web_ui:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task failed: VLM detected terminal SQL usage instead of the FreeMED web interface.",
            "details": {"vlm_feedback": vlm_feedback}
        }

    # Criterion 1: User Exists (20 pts)
    if user_exists:
        score += 20
        feedback_parts.append("User 'smitchell' successfully created")
    else:
        feedback_parts.append("User 'smitchell' NOT found in the database")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: First Name Correct (10 pts)
    actual_fname = user_data.get('userfname', '')
    if actual_fname == expected_fname:
        score += 10
        feedback_parts.append(f"First Name correct ({actual_fname})")
    else:
        feedback_parts.append(f"First Name incorrect (Expected: {expected_fname}, Got: {actual_fname})")

    # Criterion 3: Last Name Correct (10 pts)
    actual_lname = user_data.get('userlname', '')
    if actual_lname == expected_lname:
        score += 10
        feedback_parts.append(f"Last Name correct ({actual_lname})")
    else:
        feedback_parts.append(f"Last Name incorrect (Expected: {expected_lname}, Got: {actual_lname})")

    # Criterion 4: Middle Name Correct (10 pts)
    actual_mname = user_data.get('usermname', '')
    if actual_mname == expected_mname:
        score += 10
        feedback_parts.append(f"Middle Name correct ({actual_mname})")
    else:
        feedback_parts.append(f"Middle Name incorrect (Expected: {expected_mname}, Got: {actual_mname})")

    # Criterion 5: User Type Correct (15 pts)
    actual_utype = user_data.get('usertype', '')
    if actual_utype == expected_usertype:
        score += 15
        feedback_parts.append(f"User Type correct ({actual_utype})")
    else:
        feedback_parts.append(f"User Type incorrect (Expected: {expected_usertype}, Got: {actual_utype})")

    # Criterion 6: Description Correct (10 pts)
    actual_desc = user_data.get('userdescrip', '')
    if expected_description.lower() in actual_desc.lower():
        score += 10
        feedback_parts.append("Description contains expected text")
    else:
        feedback_parts.append(f"Description incorrect (Expected to contain: {expected_description}, Got: {actual_desc})")

    # Criterion 7: Password Hash Correct (15 pts)
    actual_pass = user_data.get('userpassword', '')
    if actual_pass == expected_password_hash:
        score += 15
        feedback_parts.append("Password correct (MD5 hash matches)")
    elif actual_pass:
        # Partial credit: password was set, but wrong value
        score += 5
        feedback_parts.append("Password was set but value is incorrect")
    else:
        feedback_parts.append("Password was not set")

    # Criterion 8: Record Count Increased (10 pts - Anti-gaming)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("Total user count properly increased")
    else:
        feedback_parts.append("Warning: Total user count did not increase (Agent may have modified an existing user instead of creating a new one)")

    # Assess overall pass criteria
    passed = (score >= 65 and user_exists)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }