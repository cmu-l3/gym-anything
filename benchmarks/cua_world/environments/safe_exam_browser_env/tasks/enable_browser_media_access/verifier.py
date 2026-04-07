#!/usr/bin/env python3
"""
Verifier for enable_browser_media_access task.

Verification Strategy (Multi-Signal):
1. Database Signal (Primary): Reads the exported JSON to check if `allowVideoCapture` 
   and `allowAudioCapture` exist and are set to true/1 in the SEB DB.
2. VLM Signal (Secondary): Samples the trajectory to verify the agent navigated to 
   the correct settings and visually toggled the checkboxes for camera/microphone.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    logger.warning("VLM utilities not available - visual verification will be skipped.")
    sample_trajectory_frames = None


def verify_enable_browser_media_access(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ====================================================================
    # 1. DATABASE VERIFICATION
    # ====================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load DB results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    config_exists = result.get("config_exists", False)
    media_settings = result.get("media_settings", [])
    
    db_camera_enabled = False
    db_mic_enabled = False

    if config_exists:
        score += 20
        feedback_parts.append("Exam configuration found.")
        
        # Look for explicit true/1 values in the DB attributes
        for setting in media_settings:
            key = setting.get("key", "").lower()
            val = str(setting.get("value", "")).lower()
            
            is_truthy = val in ['true', '1', 'yes', 'on']
            
            if is_truthy:
                if 'video' in key or 'camera' in key:
                    db_camera_enabled = True
                if 'audio' in key or 'mic' in key:
                    db_mic_enabled = True
                    
        if db_camera_enabled:
            score += 20
            feedback_parts.append("DB Verified: Camera enabled.")
        if db_mic_enabled:
            score += 20
            feedback_parts.append("DB Verified: Microphone enabled.")
    else:
        feedback_parts.append("Exam configuration 'Oral Communication 2025' missing.")

    # ====================================================================
    # 2. VLM TRAJECTORY VERIFICATION (Anti-gaming & UI confirmation)
    # ====================================================================
    vlm_camera_ok = False
    vlm_mic_ok = False
    
    if sample_trajectory_frames:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + ([final] if final else [])
        
        if images:
            prompt = """
            You are verifying a Safe Exam Browser Server administrative task.
            The agent was instructed to enable Camera (Video Capture) and Microphone (Audio Capture) 
            for the exam configuration named "Oral Communication 2025".
            
            Review these trajectory screenshots and respond in JSON format checking these criteria:
            1. "navigated_to_settings": Did the agent navigate to the configuration settings for "Oral Communication 2025"?
            2. "camera_toggled": Did the agent visually check/enable the setting for Camera or Video Capture?
            3. "microphone_toggled": Did the agent visually check/enable the setting for Microphone or Audio Capture?
            4. "saved_changes": Did the agent click Save after making changes?
            
            Return format:
            {
                "navigated_to_settings": true/false,
                "camera_toggled": true/false,
                "microphone_toggled": true/false,
                "saved_changes": true/false
            }
            """
            
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response:
                try:
                    # Clean markdown if present
                    content = vlm_response.strip()
                    if content.startswith("