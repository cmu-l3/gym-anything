#!/usr/bin/env python3
"""
Verifier for moderate_dismiss_raised_hand task.
Uses VLM trajectory analysis to verify:
1. Two participants joined (Alice and Bob).
2. Bob raised his hand.
3. Alice (Moderator) dismissed the hand.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_moderate_dismiss_raised_hand(traj, env_info, task_info):
    """
    Verifies that the agent joined as two users, raised a hand on one side,
    and dismissed it from the OTHER side.
    """
    # 1. Setup & Basic Checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("app_was_running", False):
        return {"passed": False, "score": 0, "feedback": "Firefox was not running at the end of the task."}

    # 2. VLM Trajectory Analysis
    # We sample frames to see the progression: Join -> Raise Hand -> Dismiss Hand
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": 0, "feedback": "No trajectory frames available for verification."}

    # PROMPT DESIGN:
    # We need to detect:
    # A. Split screen state (two meetings).
    # B. "Raised Hand" icon appearing on the right side (Bob) or in the participant list on the left.
    # C. Moderator action: Context menu open on the left side (Alice) interacting with Bob's user.
    # D. Final state: Hand icon gone.

    vlm_prompt = """
    You are verifying a video conferencing moderation task.
    The screen shows two Firefox windows side-by-side.
    - LEFT Window = Moderator Alice
    - RIGHT Window = Citizen Bob

    Analyze the sequence of images and the final image to answer:
    1. Did two distinct participants ('Alice' and 'Bob') join the meeting?
    2. Did 'Citizen Bob' (Right Window) raise his hand? (Look for a blue hand icon or 'raised hand' badge).
    3. Did the Moderator (Left Window) open a menu to lower the hand? (Look for a context menu on Bob's tile/name in the Left window).
    4. Is the hand lowered in the final state?

    Return valid JSON:
    {
        "participants_joined": boolean,
        "hand_was_raised": boolean,
        "moderator_menu_action_observed": boolean,
        "final_hand_lowered": boolean,
        "explanation": "string"
    }
    """

    all_images = frames + [final_frame] if final_frame else frames
    
    try:
        vlm_response = query_vlm(images=all_images, prompt=vlm_prompt)
        analysis = vlm_response.get("parsed", {})
    except Exception as e:
        logger.error(f"VLM Query failed: {e}")
        return {"passed": False, "score": 0, "feedback": "Verification failed during visual analysis."}

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criteria 1: Participants Joined (20 pts)
    if analysis.get("participants_joined"):
        score += 20
        feedback.append("Both participants joined successfully.")
    else:
        feedback.append("Failed to verify both participants joined.")

    # Criteria 2: Hand Raised (20 pts)
    if analysis.get("hand_was_raised"):
        score += 20
        feedback.append("Guest correctly raised hand.")
    else:
        feedback.append("No raised hand detected.")

    # Criteria 3: Moderator Action (20 pts)
    # This is the crucial anti-gaming check. Did they use the moderator view?
    if analysis.get("moderator_menu_action_observed"):
        score += 20
        feedback.append("Moderator correctly accessed dismissal menu.")
    else:
        feedback.append("Did not detect moderator interaction (menu) on the Left window.")

    # Criteria 4: Final Success (40 pts)
    if analysis.get("final_hand_lowered"):
        score += 40
        feedback.append("Hand successfully dismissed in final state.")
    else:
        feedback.append("Hand was still raised at the end.")

    # Final Pass Check
    # Must have raised hand, dismissed it, and ends with clean state.
    passed = (score >= 80) and analysis.get("hand_was_raised") and analysis.get("final_hand_lowered")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": analysis
    }