#!/usr/bin/env python3
"""
Verifier for configure_account_security task.
Checks Rocket.Chat database state exported by the export script and assesses UI trajectory using VLM.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_account_security(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. VLM Trajectory checking
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        # Sample frames throughout the trajectory to verify agent actually used the UI
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "You are reviewing a sequence of screenshots of an agent configuring Rocket.Chat. "
                "Did the agent navigate to the 'Administration' > 'Settings' > 'Accounts' section "
                "and interact with the 'Password Policy' or 'Login Expiration' settings? "
                "Respond in JSON format with a boolean key 'interacted'."
            )
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("parsed", {}).get("interacted"):
                vlm_score = 15
                logger.info("VLM verified meaningful trajectory interaction.")
    except ImportError:
        logger.warning("VLM module not available; skipping trajectory verification.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # 2. Extract application state JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Login Expiration (10 points)
    if result.get("Accounts_LoginExpiration") == 90:
        score += 10
        feedback.append("Login Expiration correctly set to 90.")
    else:
        feedback.append(f"Login Expiration incorrect: {result.get('Accounts_LoginExpiration')}")

    # Criterion 2: Policy Enabled (10 points)
    if result.get("Accounts_Password_Policy_Enabled") is True:
        score += 10
        feedback.append("Password Policy enabled.")
    else:
        feedback.append("Password Policy not enabled.")

    # Criterion 3: MinLength (15 points)
    if result.get("Accounts_Password_Policy_MinLength") == 12:
        score += 15
        feedback.append("MinLength correctly set to 12.")
    else:
        feedback.append(f"MinLength incorrect: {result.get('Accounts_Password_Policy_MinLength')}")

    # Criterion 4: Complexity Toggles (4 * 5 points = 20 points)
    complexity = 0
    for key in ["Accounts_Password_Policy_AtLeastOneLowercase",
                "Accounts_Password_Policy_AtLeastOneUppercase",
                "Accounts_Password_Policy_AtLeastOneNumber",
                "Accounts_Password_Policy_AtLeastOneSymbol"]:
        if result.get(key) is True:
            complexity += 5
    score += complexity
    feedback.append(f"Complexity points: {complexity}/20.")

    # Criterion 5: Repeating characters (15 points total)
    repeating_score = 0
    if result.get("Accounts_Password_Policy_ForbidRepeatingCharacters") is True:
        repeating_score += 5
    if result.get("Accounts_Password_Policy_MaxRepeatingCharacters") == 3:
        repeating_score += 10
    score += repeating_score
    feedback.append(f"Repeating characters policy points: {repeating_score}/15.")

    # Criterion 6: Password History (15 points total)
    history_score = 0
    if result.get("Accounts_Password_History_Enabled") is True:
        history_score += 5
    if result.get("Accounts_Password_History_Amount") == 5:
        history_score += 10
    score += history_score
    feedback.append(f"Password History policy points: {history_score}/15.")

    # Add VLM score (15 points)
    score += vlm_score

    # Passed if fundamental configuration parameters match successfully (allowing for VLM fail margin)
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }