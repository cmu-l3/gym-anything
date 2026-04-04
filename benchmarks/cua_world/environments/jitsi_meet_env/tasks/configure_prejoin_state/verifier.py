#!/usr/bin/env python3
"""
Verifier for configure_prejoin_state task.
Verifies:
1. Final state in meeting (Audio=Muted, Video=Muted, Name=Silent_Observer, Room=Correct) via JS state extraction.
2. Workflow via VLM trajectory (Must have interacted with Pre-Join screen).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_prejoin_state(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_room = metadata.get("target_room", "TownHall_2024_Auditor")
    target_name = metadata.get("target_name", "Silent_Observer")

    # 1. Load exported result
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
    
    # --- CRITERION 1: Browser State Verification (60 pts) ---
    jitsi_state = result.get("jitsi_state", {})
    
    # Check Room Name
    # Room name in Jitsi might be lowercased by the server, check carefully
    actual_room = jitsi_state.get("roomName", "")
    if actual_room and target_room.lower() in actual_room.lower():
        score += 20
        feedback_parts.append(f"Joined correct room '{actual_room}'")
    else:
        feedback_parts.append(f"Wrong room: found '{actual_room}', expected '{target_room}'")

    # Check Display Name
    actual_name = jitsi_state.get("displayName", "")
    if actual_name == target_name:
        score += 20
        feedback_parts.append(f"Correct display name '{actual_name}'")
    else:
        feedback_parts.append(f"Wrong name: found '{actual_name}', expected '{target_name}'")

    # Check Mute State (Final)
    audio_muted = jitsi_state.get("audioMuted", False)
    video_muted = jitsi_state.get("videoMuted", False)
    
    if audio_muted:
        score += 10
        feedback_parts.append("Audio is muted")
    else:
        feedback_parts.append("Audio is NOT muted")
        
    if video_muted:
        score += 10
        feedback_parts.append("Video is disabled")
    else:
        feedback_parts.append("Video is NOT disabled")

    # --- CRITERION 2: VLM Trajectory Verification (40 pts) ---
    # We need to verify they used the Pre-Join screen, not just muted after joining.
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying a user workflow in Jitsi Meet. The user was instructed to:
    1. Go to the Pre-Join/Lobby screen.
    2. Disable Microphone and Camera on that screen.
    3. Enter the name 'Silent_Observer'.
    4. Click 'Join Meeting'.
    
    Look at these screenshots of the user's journey.
    
    Question 1: Did the user interact with the Pre-Join screen? (This screen typically shows a preview of the camera, a name input field, and 'Join meeting' button).
    Question 2: Is there evidence that the user clicked the Mute/Stop Camera buttons BEFORE the final meeting screen?
    Question 3: In the final state, does the user appear to be in the meeting with icons indicating they are muted?

    Return valid JSON:
    {
        "seen_prejoin_screen": true/false,
        "actions_on_prejoin": true/false,
        "final_state_muted": true/false,
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("seen_prejoin_screen"):
            score += 10
            feedback_parts.append("VLM: Pre-join screen detected")
        if parsed.get("actions_on_prejoin"):
            score += 20
            feedback_parts.append("VLM: Actions on pre-join detected")
        if parsed.get("final_state_muted"):
            score += 10
            feedback_parts.append("VLM: Final state visually confirmed muted")
            
        if parsed.get("seen_prejoin_screen") and parsed.get("actions_on_prejoin"):
            vlm_passed = True
    else:
        feedback_parts.append("VLM verification failed to run")

    # Final logic
    # Must have correct room and name (Basic reqs)
    basic_reqs = (actual_name == target_name) and (target_room.lower() in str(actual_room).lower())
    # Must be muted in final state
    muted_reqs = audio_muted and video_muted
    
    passed = score >= 80 and basic_reqs and muted_reqs
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }