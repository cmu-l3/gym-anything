#!/usr/bin/env python3
"""
Verifier for enable_whiteboard task.

Verifies:
1. Server Config: .env file has correct variables.
2. Server State: Web container was restarted AFTER task start.
3. Service Health: Jitsi is reachable.
4. UI Interaction (VLM):
   - Meeting joined.
   - Whiteboard panel open.
   - Content added.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_whiteboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Exported Data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Programmatic Checks (55 points max) ---

    # Criterion 1: Configuration Updated (25 pts)
    config_content = result_data.get("config_content", "")
    has_enabled = "WHITEBOARD_ENABLED=true" in config_content or "WHITEBOARD_ENABLED=TRUE" in config_content
    has_url = "WHITEBOARD_COLLAB_SERVER_PUBLIC_URL=" in config_content
    
    if has_enabled and has_url:
        score += 25
        feedback_parts.append("Configuration updated correctly.")
    elif has_enabled:
        score += 15
        feedback_parts.append("Whiteboard enabled, but URL config missing.")
    else:
        feedback_parts.append("Configuration missing 'WHITEBOARD_ENABLED=true'.")

    # Criterion 2: Container Restarted (15 pts)
    task_start = result_data.get("task_start_time", 0)
    container_start = result_data.get("container_start_time", 0)
    
    if container_start > task_start:
        score += 15
        feedback_parts.append("Container restarted successfully.")
    else:
        feedback_parts.append("Container was NOT restarted (or restarted before task config change).")

    # Criterion 3: Web Service Healthy (10 pts)
    if result_data.get("web_healthy", False):
        score += 10
        feedback_parts.append("Jitsi web service is reachable.")
    else:
        feedback_parts.append("Jitsi web service is unreachable.")

    # Criterion 4: Signal File (5 pts)
    if result_data.get("signal_file_exists", False) and "done" in result_data.get("signal_content", "").lower():
        score += 5
        feedback_parts.append("Completion signal file created.")

    # --- VLM Verification (45 points max) ---
    
    # We use trajectory frames to check if the whiteboard was opened and modified.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a Jitsi Meet task. The user was supposed to:
    1. Join a meeting named "WhiteboardGlossarySession".
    2. Open the Whiteboard feature (Excalidraw).
    3. Write text like "Glossary Terms" on it.

    Look at the sequence of images and the final image.
    
    Answer the following:
    1. IS_MEETING_ACTIVE: Is the user inside a Jitsi meeting (toolbar visible, video grid or avatar)?
    2. WHITEBOARD_OPEN: Is the Excalidraw whiteboard panel visible (look for sketch/draw tools, white canvas)?
    3. CONTENT_ADDED: Is there any text or drawing on the whiteboard (specifically text like "Glossary")?
    4. ROOM_NAME_MATCH: Can you see the room name "WhiteboardGlossarySession" in the URL bar or meeting info?

    Return JSON:
    {
        "is_meeting_active": boolean,
        "whiteboard_open": boolean,
        "content_added": boolean,
        "room_name_match": boolean
    }
    """

    # Query VLM
    vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("is_meeting_active"):
            vlm_score += 15
            feedback_parts.append("Joined meeting.")
        
        if parsed.get("whiteboard_open"):
            vlm_score += 20
            feedback_parts.append("Whiteboard panel opened.")
            
            if parsed.get("content_added"):
                vlm_score += 5
                feedback_parts.append("Content added to whiteboard.")
        
        if parsed.get("room_name_match"):
            vlm_score += 5
            feedback_parts.append("Correct room name verified.")
            
    else:
        feedback_parts.append("Visual verification failed (VLM error).")
    
    score += vlm_score

    # Pass Threshold
    # Needs Config (25) + Restart (15) + Meeting Active (15) + Whiteboard Open (20) = 75 for solid pass
    # Minimum pass: 60
    passed = score >= 60 and has_enabled and (container_start > task_start)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }