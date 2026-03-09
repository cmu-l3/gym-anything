#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_professional_profile(traj, env_info, task_info):
    """
    Verifies that the agent configured the profile correctly and joined with correct device state.
    """
    score = 0
    feedback = []
    
    # 1. Setup - Get data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    result_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            content = f.read().strip()
            if content:
                result_data = json.loads(content)
    except Exception as e:
        feedback.append(f"Failed to load result data: {str(e)}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get("metadata", {})
    expected_name = metadata.get("expected_name", "Director Alice")
    expected_email = metadata.get("expected_email", "alice@corp.example.com")
    
    # 2. Programmatic Verification (60 points)
    
    # Check if joined
    in_meeting = result_data.get("in_meeting", False)
    if in_meeting:
        score += 10
        feedback.append("Successfully joined the meeting.")
    else:
        feedback.append("Failed to join the meeting (or API not accessible).")
        # Critical failure if not joined
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Check Display Name (20 pts)
    actual_name = result_data.get("display_name", "")
    if actual_name == expected_name:
        score += 20
        feedback.append(f"Display Name correct: '{actual_name}'.")
    else:
        feedback.append(f"Display Name incorrect. Expected '{expected_name}', got '{actual_name}'.")

    # Check Audio Muted (10 pts)
    audio_muted = result_data.get("audio_muted")
    if audio_muted is True:
        score += 10
        feedback.append("Audio was correctly muted.")
    else:
        feedback.append(f"Audio was NOT muted (state: {audio_muted}).")

    # Check Video Enabled (10 pts)
    video_muted = result_data.get("video_muted")
    if video_muted is False:
        score += 10
        feedback.append("Video was correctly enabled.")
    else:
        feedback.append(f"Video was NOT enabled (state: {video_muted}).")

    # Check Email Persistence (10 pts)
    # The email is stored in localStorage string under features/base/settings
    local_storage_str = result_data.get("local_storage", "{}")
    email_found = False
    try:
        if local_storage_str:
            ls_data = json.loads(local_storage_str)
            settings = ls_data.get("features", {}).get("base/settings", {})
            if settings.get("email") == expected_email:
                email_found = True
    except:
        pass

    if email_found:
        score += 10
        feedback.append("Email correctly persisted in settings.")
    else:
        feedback.append("Email not found in local storage settings.")

    # 3. VLM Verification (40 points)
    # We verify the final state visually
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = f"""
    You are verifying a Jitsi Meet task.
    Goal: Join meeting as '{expected_name}' with Microphone MUTED and Camera ON.
    
    Analyze the final screenshot and trajectory:
    1. Is the user successfully IN a meeting (grid view/main stage)?
    2. Can you see the name '{expected_name}' visible on the participant's tile or list?
    3. Is there a visual indication that the microphone is MUTED (red microphone icon)?
    4. Is there a visual indication that camera/video is ON (video feed visible)?
    
    Provide a score out of 40 based on these criteria (10 pts each).
    Return JSON: {{"score": int, "reasoning": "str"}}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames + [final_screenshot], prompt=vlm_prompt)
        if vlm_res and "parsed" in vlm_res:
            parsed = vlm_res["parsed"]
            vlm_score = min(40, parsed.get("score", 0))
            feedback.append(f"VLM Verification: {parsed.get('reasoning', 'No reasoning provided')}")
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback.append("VLM verification failed to execute.")

    score += vlm_score

    passed = (score >= 70) and (actual_name == expected_name) and in_meeting

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }