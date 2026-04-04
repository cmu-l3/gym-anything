#!/usr/bin/env python3
"""
Verifier for grant_moderator_multiparticipant task.

Verification Strategy:
1. File Check: Verify the agent saved the required screenshot and it was created during the task.
2. VLM Trajectory Analysis:
   - Confirm two participants (FitnessCoach, ClassHelper) were present.
   - Confirm the moderator menu was accessed.
   - Confirm the "Grant Moderator" action was taken.
3. VLM Final Screenshot Analysis:
   - Confirm ClassHelper shows the moderator indicator (star/badge) in the saved screenshot.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_grant_moderator(traj, env_info, task_info):
    """
    Verify that the agent granted moderator rights to the second participant.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Load the agent's saved screenshot (if it exists)
    user_screenshot_path = None
    if result_data.get("user_screenshot_exists") and result_data.get("user_screenshot_valid_timestamp"):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            # The path inside the container
            container_path = result_data.get("user_screenshot_path")
            copy_from_env(container_path, temp_img.name)
            user_screenshot_path = temp_img.name
        except Exception as e:
            logger.warning(f"Failed to copy user screenshot: {e}")
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)

    # 2. VLM Analysis
    frames = sample_trajectory_frames(traj, n=8)  # Sample more frames for complex workflow
    final_frame = get_final_screenshot(traj)
    
    # Construct image list for VLM
    # We include the user's saved screenshot as the last image if available, 
    # otherwise just use the trajectory.
    vlm_images = frames + [final_frame]
    if user_screenshot_path:
        vlm_images.append(user_screenshot_path)

    prompt = """
    You are evaluating a Jitsi Meet task where an agent must:
    1. Join a meeting as "FitnessCoach".
    2. Open a second tab and join as "ClassHelper".
    3. Grant Moderator rights to "ClassHelper".
    
    Review the sequence of screenshots. The last image might be a specific proof screenshot saved by the agent.
    
    Check for these specific events:
    A. **Two Participants**: Are "FitnessCoach" and "ClassHelper" both visible in the meeting at the same time?
    B. **Context Menu**: Did the agent click the three dots/menu on "ClassHelper"?
    C. **Grant Action**: Did the agent select "Grant Moderator" (or similar) from the menu?
    D. **Success State**: Does "ClassHelper" have a moderator star/badge/icon in the participants list in the final state?
    
    Respond in JSON:
    {
        "two_participants_seen": true/false,
        "menu_opened": true/false,
        "grant_action_seen": true/false,
        "moderator_status_confirmed": true/false,
        "participants_names": ["list", "of", "names", "seen"],
        "reasoning": "brief explanation"
    }
    """

    vlm_result = query_vlm(images=vlm_images, prompt=prompt)
    
    # Clean up temp screenshot
    if user_screenshot_path and os.path.exists(user_screenshot_path):
        os.unlink(user_screenshot_path)

    if not vlm_result.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM analysis failed"}

    analysis = vlm_result.get("parsed", {})
    
    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: File artifacts (25 points)
    if result_data.get("user_screenshot_exists"):
        score += 10
        feedback.append("Screenshot file created.")
        if result_data.get("user_screenshot_valid_timestamp"):
            score += 15
            feedback.append("Screenshot created during task.")
        else:
            feedback.append("Screenshot timestamp invalid (anti-gaming).")
    else:
        feedback.append("No screenshot saved.")

    # Criterion 2: Two participants visible (25 points)
    if analysis.get("two_participants_seen"):
        score += 25
        feedback.append("Confirmed two participants joined.")
    else:
        feedback.append("Could not confirm two participants present.")

    # Criterion 3: Menu/Action interaction (25 points)
    if analysis.get("menu_opened") or analysis.get("grant_action_seen"):
        score += 25
        feedback.append("Moderator action/menu detected.")
    else:
        feedback.append("No moderator menu interaction detected.")

    # Criterion 4: Final Success (25 points)
    if analysis.get("moderator_status_confirmed"):
        score += 25
        feedback.append("ClassHelper confirmed as Moderator.")
    else:
        feedback.append("Moderator status not visible on ClassHelper.")

    # Pass logic: Need meaningful progress (participants + menu) AND final success OR robust file evidence
    # Threshold: 60 points required
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": analysis
    }