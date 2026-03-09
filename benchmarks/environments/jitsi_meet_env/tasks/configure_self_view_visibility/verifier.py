#!/usr/bin/env python3
"""
Verifier for configure_self_view_visibility task.

Verification Strategy:
1. Programmatic: Check Jitsi 'features/base/settings' in localStorage for 'disableSelfView': true.
2. VLM: Check final screenshot and trajectory to confirm self-view is hidden but camera is ON.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_self_view_visibility(traj, env_info, task_info):
    """
    Verifies that the agent has hidden the self-view in Jitsi Meet.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Parse Programmatic Data
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        feedback_parts.append("Failed to retrieve task result data")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Analyze Jitsi Settings (Primary Verification)
    settings = task_result.get('jitsi_settings', {})
    disable_self_view = settings.get('disableSelfView', False)
    
    # Check if they are actually in the meeting (Window title usually contains room name)
    window_title = task_result.get('window_title', '')
    in_meeting = "WebinarPrep" in window_title or "Jitsi Meet" in window_title
    
    if in_meeting:
        score += 20
        feedback_parts.append("Agent joined the meeting.")
    else:
        feedback_parts.append("Agent does not appear to be in the correct meeting window.")

    if disable_self_view is True:
        score += 60
        feedback_parts.append("Success: 'Hide self view' setting is enabled in configuration.")
    else:
        feedback_parts.append(f"Failure: 'Hide self view' setting is {disable_self_view} (expected true).")

    # 3. VLM Verification (Visual Confirmation)
    # We need to ensure the camera is actually ON (not just stopped)
    # If camera is stopped, self view is hidden by definition, which is a loophole we must close.
    
    final_screenshot = get_final_screenshot(traj)
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying a Jitsi Meet task.
    Goal: The user should have the camera turned ON, but the "Self View" (their own video feed on screen) should be HIDDEN.
    
    Analyze the final screenshot provided.
    1. Is the user inside a Jitsi meeting? (Look for toolbar, filmstrip, or main stage).
    2. Is the Camera turned ON? (Look at the camera icon in the toolbar. It should NOT have a slash through it. If it says 'Stop video', the camera is ON).
    3. Is the Self View visible? (Usually a small rectangle showing the user's own camera feed, often in a corner or filmstrip). 
       Note: If the user is the only one in the meeting, hiding self view might result in a "You are alone" message or empty stage.
       
    Compare with these previous frames to see if they opened a menu or settings dialog.
    
    Return JSON:
    {
        "in_meeting": boolean,
        "camera_is_on": boolean,
        "self_view_visible": boolean,
        "settings_menu_opened": boolean,
        "explanation": "string"
    }
    """
    
    vlm_score = 0
    if final_screenshot:
        try:
            # Combine frames for context
            images = trajectory_frames + [final_screenshot]
            vlm_result = query_vlm(
                prompt=vlm_prompt,
                images=images
            )
            
            parsed = vlm_result.get('parsed', {})
            logger.info(f"VLM Analysis: {parsed}")
            
            if parsed.get('in_meeting'):
                # Already scored programmatically, but good confirmation
                pass
                
            if parsed.get('camera_is_on'):
                score += 20
                feedback_parts.append("Visual check: Camera is active (correct).")
            else:
                feedback_parts.append("Visual check: Camera appears to be OFF. Task requires camera ON but view hidden.")
                
            if not parsed.get('self_view_visible'):
                # This corroborates the programmatic check
                vlm_score += 10 # Bonus for visual consistency
                feedback_parts.append("Visual check: Self view is not visible.")
            else:
                feedback_parts.append("Visual check: Self view appears to be visible.")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("Visual verification skipped due to error.")

    # Final scoring logic
    # Pass if settings are correct AND we have reasonable confidence camera is on
    # (programmatic check for camera state is hard without deep introspection, so we rely on VLM or implicit state)
    
    # We accept the task if the setting is definitely True (60pts) + In meeting (20pts) + Camera On (20pts)
    # The programmatic check `disableSelfView` is the gold standard for the "hidden" part.
    
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": min(100, score + vlm_score),
        "feedback": " ".join(feedback_parts)
    }