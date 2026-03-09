#!/usr/bin/env python3
"""
Verifier for adjust_video_quality task.

This task relies heavily on VLM verification because Jitsi Meet's internal
state (React/Redux store) is not easily accessible from the shell without
complex browser automation that might interfere with the agent.

Verification Logic:
1. Programmatic: Check if Firefox is running and screenshots changed (anti-gaming).
2. VLM: Analyze trajectory and final screenshot to confirm:
   - Agent joined the meeting (moved past pre-join).
   - Display name "Coach Martinez" was used (visible in trajectory or final UI).
   - "Manage video quality" panel is open.
   - Slider is set to "Low definition".
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_adjust_video_quality(traj, env_info, task_info):
    """
    Verify the agent joined the meeting and set video quality to Low definition.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from container
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

    # 2. Basic Programmatic Checks (20 points max)
    score = 0
    feedback_parts = []
    
    # Check 1: Firefox running (10 pts)
    if result.get('app_was_running', False):
        score += 10
    else:
        feedback_parts.append("Firefox was closed")

    # Check 2: State changed (10 pts) - Anti-gaming "do nothing" check
    if result.get('screenshots_differ', False):
        score += 10
    else:
        feedback_parts.append("Screen state did not change (did nothing?)")
        # If nothing changed, we can fail early to save VLM costs, 
        # but for this template we'll proceed to get VLM feedback.
    
    programmatic_score = score
    
    # 3. VLM Verification (80 points max)
    # We use trajectory frames to catch the "joining" process and final frame for the result
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
        return {
            "passed": False, 
            "score": programmatic_score, 
            "feedback": "No final screenshot available for analysis"
        }

    # Combine frames for analysis
    all_images = frames + [final_frame]
    
    prompt = """Analyze these screenshots of a user interacting with Jitsi Meet video conferencing.
    
    The user was tasked to:
    1. Enter display name "Coach Martinez" on the pre-join screen.
    2. Join the meeting "VirtualFitnessQ4".
    3. Open "Manage video quality" settings.
    4. Set video quality to "Low definition".

    Please evaluate the following criteria based on the screenshots:

    CRITERION 1: Meeting Joined (20 points)
    - Is the user inside the meeting (participant grid, toolbar visible)?
    - NOT still on the pre-join screen (which has a "Join meeting" button).

    CRITERION 2: Display Name (10 points)
    - Can you see "Coach Martinez" typed in the name field (in early frames) OR as the participant name (in later frames)?

    CRITERION 3: Quality Panel & Low Definition (50 points)
    - Is the "Manage video quality" panel/slider visible in the FINAL frame?
    - Is the slider handle positioned at "Low definition" (the 2nd option from the bottom, above "Audio only")?
    - Note: The order is usually Audio Only -> Low Definition -> Standard Definition -> High Definition.
    - If panel is open but wrong setting, award 10 points.
    - If panel is not visible at all, award 0 points.

    Respond in JSON format:
    {
        "meeting_joined": true/false,
        "display_name_correct": true/false,
        "quality_panel_visible": true/false,
        "setting_is_low_def": true/false,
        "explanation": "Brief description of what is visible"
    }
    """

    try:
        vlm_response = query_vlm(prompt=prompt, images=all_images)
        
        if not vlm_response.get("success"):
            return {
                "passed": False, 
                "score": programmatic_score, 
                "feedback": f"VLM analysis failed: {vlm_response.get('error')}"
            }
            
        parsed = vlm_response.get("parsed", {})
        
        # Score VLM criteria
        vlm_score = 0
        
        if parsed.get("meeting_joined"):
            vlm_score += 20
        else:
            feedback_parts.append("Did not successfully join the meeting")

        if parsed.get("display_name_correct"):
            vlm_score += 10
        else:
            feedback_parts.append("Display name 'Coach Martinez' not verified")

        if parsed.get("quality_panel_visible"):
            if parsed.get("setting_is_low_def"):
                vlm_score += 50
                feedback_parts.append("Video quality correctly set to Low definition")
            else:
                vlm_score += 10 # Partial credit for finding the menu
                feedback_parts.append("Quality panel opened but setting was NOT 'Low definition'")
        else:
            feedback_parts.append("Manage video quality panel not visible in final state")

        total_score = programmatic_score + vlm_score
        
        # Pass threshold: 60 (Must at least join and open panel correctly)
        passed = total_score >= 60

        return {
            "passed": passed,
            "score": total_score,
            "feedback": " | ".join(feedback_parts),
            "details": parsed
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": programmatic_score,
            "feedback": f"Verification error: {str(e)}"
        }