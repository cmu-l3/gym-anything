#!/usr/bin/env python3
"""
Verifier for disable_video_mirroring task.

Verification Strategy:
1. Primary: VLM Analysis of the Final Screenshot.
   - The agent is instructed to keep the Settings > Video dialog open.
   - VLM checks for "Settings" dialog, "Video" tab active, and "Mirror local video" unchecked.
   - VLM also checks for the display name "Tutor Alex" in the background.

2. Secondary: VLM Trajectory Analysis.
   - Verify the agent actually navigated through the UI (Pre-join -> Join -> Settings).

3. Tertiary (Bonus): Programmatic check of localStorage if extraction succeeded.
   - Jitsi stores settings in `features/base/settings`.
   - We look for `disableSelfViewMirror` or similar keys (implementation details vary by version).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_video_mirroring(traj, env_info, task_info):
    """
    Verifies that the agent joined the meeting and disabled video mirroring.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load task result
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load task_result.json: {e}")

    # Load extracted settings (if available)
    jitsi_settings = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/jitsi_settings.json", f.name)
            f.seek(0)
            content = f.read().decode('utf-8').strip()
            if content and content != "null":
                # It might be double encoded JSON string
                if content.startswith('"') and content.endswith('"'):
                     content = json.loads(content) # Decode string to json string
                jitsi_settings = json.loads(content)
        except Exception as e:
            logger.warning(f"Could not load jitsi_settings.json: {e}")

    score = 0
    feedback = []

    # 2. Basic Checks (20 points)
    if task_result.get("app_running", False):
        score += 10
        feedback.append("Firefox is running.")
    else:
        feedback.append("Firefox was closed.")

    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        score += 10
    else:
        return {"passed": False, "score": score, "feedback": "No final screenshot available."}

    # 3. VLM Verification of Final State (50 points)
    # We expect the Settings dialog to be OPEN on the VIDEO tab with Mirror UNCHECKED.
    
    final_prompt = """
    You are verifying a Jitsi Meet task.
    Goal: Join meeting as 'Tutor Alex', open Settings > Video, and disable 'Mirror local video'.
    
    Analyze this screenshot:
    1. Is the 'Settings' dialog visible?
    2. Is the 'Video' tab currently selected in the settings?
    3. Is the 'Mirror local video' (or 'Mirror self view') checkbox visible?
    4. Is that checkbox UNCHECKED (disabled)?
    5. Can you see the name 'Tutor Alex' anywhere (e.g., in the meeting corner or self-view)?
    
    Output JSON:
    {
        "settings_open": true/false,
        "video_tab_active": true/false,
        "mirror_option_visible": true/false,
        "mirror_unchecked": true/false,
        "name_visible": true/false,
        "reasoning": "..."
    }
    """
    
    vlm_result = query_vlm(images=[final_screenshot], prompt=final_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    if vlm_data.get("settings_open"):
        score += 10
        feedback.append("Settings dialog is open.")
        
        if vlm_data.get("video_tab_active"):
            score += 10
            feedback.append("Video tab is active.")
            
            if vlm_data.get("mirror_option_visible"):
                if vlm_data.get("mirror_unchecked"):
                    score += 20
                    feedback.append("Mirroring is correctly disabled (unchecked).")
                else:
                    feedback.append("Mirroring option is visible but still CHECKED (Failed).")
            else:
                feedback.append("Could not find 'Mirror local video' option.")
        else:
            feedback.append("Video tab is NOT active.")
    else:
        feedback.append("Settings dialog is NOT open (or not detected). Agent should keep it open.")

    if vlm_data.get("name_visible"):
        score += 10
        feedback.append("Display name 'Tutor Alex' detected.")

    # 4. VLM Trajectory Verification (30 points)
    # Check if they actually joined the meeting and didn't just stay on pre-join
    frames = sample_trajectory_frames(traj, n=5)
    traj_prompt = """
    Analyze these frames of a user using Jitsi Meet.
    Did the user:
    1. Start at a pre-join screen?
    2. Click 'Join' to enter the main meeting?
    3. Open a settings menu?
    
    Output JSON:
    {
        "joined_meeting": true/false,
        "opened_settings": true/false
    }
    """
    traj_result = query_vlm(images=frames, prompt=traj_prompt)
    traj_data = traj_result.get("parsed", {})
    
    if traj_data.get("joined_meeting"):
        score += 15
        feedback.append("Trajectory confirms meeting join.")
    
    if traj_data.get("opened_settings"):
        score += 15
        feedback.append("Trajectory confirms settings interaction.")

    # 5. Bonus: Programmatic check (Validation, does not add points but confirms)
    # Key usually is 'localFlipX' (true/false). If 'unchecked' in UI, it might be false.
    # Note: Jitsi config keys can be tricky. We use this mainly for debugging logs.
    if jitsi_settings:
        logger.info(f"Extracted Jitsi Settings: {jitsi_settings}")
        # Logic to check specific key if known version-stable
        # e.g., if 'localFlipX' in jitsi_settings and jitsi_settings['localFlipX'] is False:
        #     logger.info("Programmatic check confirmed: localFlipX is False")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }