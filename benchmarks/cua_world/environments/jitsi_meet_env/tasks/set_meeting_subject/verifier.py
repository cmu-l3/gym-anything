#!/usr/bin/env python3
"""
Verifier for set_meeting_subject task.

Verification Strategy:
1. Programmatic: Check browser window title. Jitsi Meet updates the document title
   to reflect the meeting subject (e.g., "Subject | RoomName | Jitsi Meet").
2. VLM: Visual verification of the toolbar subject text and workflow progression.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_meeting_subject(traj, env_info, task_info):
    """
    Verify that the agent joined the meeting and set the correct subject.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', "Q4 2024 Quarterly Ops Review - Budget and Headcount")
    expected_partial = metadata.get('expected_partial_subject', "Q4 2024 Quarterly Ops Review")

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Programmatic Verification (Window Title) - 60 points total
    # ------------------------------------------------------------------
    window_titles = result.get('window_titles', "")
    firefox_running = result.get('firefox_running', "false") == "true"

    # Check if inside meeting (not just pre-join)
    # Typical Jitsi title format: "Meeting Name | Jitsi Meet" or "Room Name | Jitsi Meet"
    # Pre-join often doesn't have the subject or has "Join meeting"
    meeting_joined = "Jitsi Meet" in window_titles and "WeeklySync" in window_titles
    
    if not firefox_running:
        feedback_parts.append("Firefox is not running.")
    elif not meeting_joined:
        feedback_parts.append("Could not confirm agent is inside the meeting based on window title.")
    else:
        score += 15
        feedback_parts.append("Agent appears to be in the meeting.")

    # Check for subject in title
    subject_found_full = expected_subject in window_titles
    subject_found_partial = expected_partial in window_titles

    if subject_found_full:
        score += 45
        feedback_parts.append("Full subject found in window title.")
    elif subject_found_partial:
        score += 30
        feedback_parts.append("Partial subject found in window title.")
    else:
        feedback_parts.append(f"Subject '{expected_partial}...' not found in window title.")

    # ------------------------------------------------------------------
    # 2. VLM Verification - 40 points total
    # ------------------------------------------------------------------
    # Use trajectory to verify the action of changing the subject
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        frames.append(final_screen)

    vlm_prompt = f"""
    You are verifying if an agent successfully set a meeting subject in Jitsi Meet.
    
    Goal Subject: "{expected_subject}"
    
    Review the screenshots (chronological order) and answer:
    1. Did the agent join the meeting (move past the pre-join screen)?
    2. Is the meeting subject "{expected_partial}" visible in the toolbar (top center)?
    3. Did the agent actually type/edit the subject (is the edit field visible in any frame)?
    
    Return JSON:
    {{
        "meeting_joined": true/false,
        "subject_visible": true/false,
        "subject_correct": true/false,
        "workflow_observed": true/false,
        "reasoning": "..."
    }}
    """

    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('meeting_joined'):
            score += 10
            feedback_parts.append("VLM confirmed meeting join.")
        
        if parsed.get('subject_visible') and parsed.get('subject_correct'):
            score += 20
            feedback_parts.append("VLM confirmed correct subject visible.")
        elif parsed.get('subject_visible'):
            score += 10
            feedback_parts.append("VLM saw a subject, but it might not be fully correct.")
            
        if parsed.get('workflow_observed'):
            score += 10
            feedback_parts.append("VLM observed editing workflow.")
            
        feedback_parts.append(f"VLM Reasoning: {parsed.get('reasoning')}")
    else:
        feedback_parts.append("VLM verification failed to run.")
        # Fallback scoring if VLM fails but programmatic succeeded strongly
        if subject_found_full:
             score += 20
             feedback_parts.append("Fallback: Granting partial VLM points based on strong programmatic evidence.")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = score >= 60 and (subject_found_partial or (vlm_result and vlm_result.get('parsed', {}).get('subject_correct')))

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }