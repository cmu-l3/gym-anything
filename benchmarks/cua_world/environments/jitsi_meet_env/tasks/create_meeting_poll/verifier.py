#!/usr/bin/env python3
"""
Verifier for create_meeting_poll task.

This task is primarily visual: we need to verify that a specific poll exists 
in the Jitsi Meet interface. Since Jitsi is a complex SPA (Single Page App) 
inside a container, inspecting the DOM or internal state from the outside is 
brittle. 

Strategy:
1. Validates task execution metadata (timestamps, app running).
2. Uses VLM (Vision-Language Model) to inspect the final screenshot.
3. Checks for key visual elements:
   - Polls panel is open.
   - Question text matches.
   - Options match.
   - Poll is in "published/sent" state (not draft).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_meeting_poll(traj, env_info, task_info):
    """
    Verify that the agent created and published the correct poll.
    """
    # 1. Setup and Basic Checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load metadata from task_info
    metadata = task_info.get('metadata', {})
    expected_question = metadata.get('poll_question', "")
    expected_options = metadata.get('poll_options', [])
    
    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Liveness Checks (10 points)
    score = 0
    feedback_parts = []
    
    if result_data.get("app_running", False):
        score += 10
        feedback_parts.append("Firefox is running.")
    else:
        feedback_parts.append("Firefox was closed (unexpected).")

    # 2. VLM Verification
    # We use both trajectory (process) and final state (outcome)
    
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}
    
    # Sample trajectory to verify the "Create" process wasn't skipped/faked
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    
    # Construct VLM Prompt
    prompt = f"""
    You are verifying a task in Jitsi Meet video conferencing.
    The user was asked to create a poll with specific content.
    
    Expected Content:
    - Question: "{expected_question}"
    - Options: {str(expected_options)}
    
    Analyze the provided images (trajectory + final state).
    
    Check for the following criteria:
    1. [Meeting Joined] Is the user inside a meeting (not on the landing page)?
    2. [Polls Panel] Is the 'Polls' side panel or tab visible/open?
    3. [Question Text] Is the specific question text visible?
    4. [Options] Are the answer options (Mandarin, Spanish, Arabic, German) visible?
    5. [Published State] Is the poll published (showing voting buttons/results) rather than just a draft form?
    
    Respond in JSON format:
    {{
        "meeting_joined": true/false,
        "polls_panel_visible": true/false,
        "question_text_match": true/false,
        "options_match_count": <integer 0-4>,
        "is_published": true/false,
        "reasoning": "<brief explanation>"
    }}
    """
    
    # Query VLM
    vlm_response = query_vlm(
        prompt=prompt,
        images=trajectory_frames + [final_screenshot]
    )
    
    if not vlm_response.get("success"):
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Verification failed due to VLM error: {vlm_response.get('error')}"
        }
        
    analysis = vlm_response.get("parsed", {})
    
    # 3. Scoring Logic
    
    # Criterion 1: Meeting Joined (15 pts)
    if analysis.get("meeting_joined"):
        score += 15
        feedback_parts.append("Joined meeting successfully.")
    else:
        feedback_parts.append("Did not appear to join the meeting.")

    # Criterion 2: Polls Panel Open (20 pts)
    if analysis.get("polls_panel_visible"):
        score += 20
        feedback_parts.append("Polls panel is open.")
    else:
        feedback_parts.append("Polls panel not found.")

    # Criterion 3: Question Text (20 pts)
    if analysis.get("question_text_match"):
        score += 20
        feedback_parts.append("Poll question text matches.")
    else:
        feedback_parts.append("Poll question text incorrect or missing.")

    # Criterion 4: Options (20 pts)
    # 5 points per correct option found
    options_count = analysis.get("options_match_count", 0)
    score += (options_count * 5)
    feedback_parts.append(f"Found {options_count}/4 poll options.")

    # Criterion 5: Published/Submitted (15 pts)
    # We want to ensure they clicked 'Send', not just typed it in.
    if analysis.get("is_published"):
        score += 15
        feedback_parts.append("Poll was successfully published.")
    else:
        feedback_parts.append("Poll appears to be in draft mode or not submitted.")

    # 4. Final Pass Determination
    # Pass if score >= 60 AND critical criteria met
    # Critical: Meeting Joined, Polls Panel Open, Published
    critical_met = (
        analysis.get("meeting_joined") and 
        analysis.get("polls_panel_visible") and 
        analysis.get("is_published")
    )
    
    passed = (score >= 60) and critical_met

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }