#!/usr/bin/env python3
"""
Verifier for configure_proctoring_features task.

VERIFICATION STRATEGY:
1. DB Check: Validates that 'Distance Learning 101' exam config was created (anti-gaming: it didn't exist prior).
2. DB Check: Validates that configuration values for chat and retries were persisted accurately to MariaDB.
3. VLM Check: Analyzes trajectory frames to visually confirm the agent interacted with the SEB Settings UI.
"""

import json
import tempfile
import os
import logging

# Attempt to import VLM tools
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_proctoring_features(traj, env_info, task_info):
    # Enforce copy_from_env usage
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract task result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Base Configuration Check (20 points)
    config_exists = result.get('config_exists', False)
    config_values = result.get('config_values', {})

    if config_exists:
        score += 20
        feedback.append("Exam configuration 'Distance Learning 101' created.")
    else:
        feedback.append("Exam configuration 'Distance Learning 101' not found in database.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 2. Database Value Checks (40 points)
    # Flexible parsing: attributes might be named "allowChat", "sebServerAllowChat", "connectionRetries"
    chat_enabled = False
    retries_correct = False

    for k, v in config_values.items():
        k_lower = k.lower()
        if 'chat' in k_lower and str(v).lower() in ['true', '1', 'yes', 'on']:
            chat_enabled = True
        if ('retry' in k_lower or 'retries' in k_lower) and str(v) == '10':
            retries_correct = True

    if chat_enabled:
        score += 20
        feedback.append("Chat feature found enabled in DB.")
    else:
        feedback.append("Chat feature NOT found enabled in DB.")

    if retries_correct:
        score += 20
        feedback.append("Connection retries found set to 10 in DB.")
    else:
        feedback.append("Connection retries NOT set to 10 in DB.")

    # 3. VLM Trajectory Verification (40 points)
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)

            prompt = (
                "You are evaluating an AI agent configuring a Safe Exam Browser server. "
                "The agent's task is to navigate to the Exam Configurations, edit 'Distance Learning 101', "
                "switch to the 'SEB Settings' tab, and enable the 'Chat' feature and set "
                "'Connection Retries' to 10.\n"
                "Review these chronologically ordered screenshots from the agent's session.\n"
                "Answer in strictly valid JSON format: {\"navigated_to_seb_settings\": true/false, \"interacted_with_chat_or_network\": true/false}"
            )

            vlm_result = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_result.get('parsed', {})

            if parsed.get('navigated_to_seb_settings'): 
                vlm_score += 20
            if parsed.get('interacted_with_chat_or_network'): 
                vlm_score += 20

            feedback.append(f"VLM Visual Check Score: {vlm_score}/40")
            score += vlm_score

        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            # Graceful degradation: Assign score if DB is perfect but VLM crashed
            if chat_enabled and retries_correct:
                score += 40
                feedback.append("VLM unavailable; perfect DB validation fallback applied.")
    else:
        if chat_enabled and retries_correct:
            score += 40
            feedback.append("VLM tools not present; perfect DB validation fallback applied.")

    # Determine passing logic
    passed = config_exists and chat_enabled and retries_correct and score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }