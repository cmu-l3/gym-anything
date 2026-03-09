#!/usr/bin/env python3
"""
Verifier for configure_kiosk_mode task.

Strategy:
1. Programmatic Check: Verify that configuration files or registry were modified during the task (shows settings were saved).
2. Programmatic Check: Verify application is still running (didn't crash).
3. VLM Verification: Analyze trajectory frames to confirm:
   - User navigated to Settings/Options
   - User entered the specific text "Summit Coworks"
   - User enabled Kiosk mode
   - Final screen shows Kiosk interface or saved settings
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_kiosk_mode(traj, env_info, task_info):
    """
    Verifies that the agent configured Kiosk mode correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_welcome = metadata.get('expected_welcome_text', 'Welcome to Summit Coworks')

    # =========================================================================
    # 1. Load Programmatic Results
    # =========================================================================
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    app_running = result.get('app_running', False)
    registry_modified = result.get('registry_modified', False)
    config_modified = result.get('config_modified', False)
    settings_saved = registry_modified or config_modified

    # =========================================================================
    # 2. VLM Trajectory Verification
    # =========================================================================
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    if final_frame:
        frames.append(final_frame)

    if not frames:
        return {"passed": False, "score": 0, "feedback": "No video evidence available"}

    prompt = f"""
    You are verifying if a user correctly configured 'Kiosk Mode' in a software called Jolly Lobby Track.
    
    The user was instructed to:
    1. Open Settings or Options.
    2. Find 'Kiosk' or 'Self-Service' settings.
    3. Enable Kiosk Mode.
    4. Enter the Welcome Text: "{expected_welcome}".
    5. Save/Apply settings.
    
    Review the provided screenshots from the session.
    
    Output JSON with the following boolean fields:
    - settings_opened: Did the user open a settings/configuration window?
    - kiosk_section_found: Did the user navigate to a Kiosk or Self-Service section?
    - text_entered: Is the text "{expected_welcome}" visible in any input field or on the final screen?
    - kiosk_enabled: Is there evidence of Kiosk mode being turned on (checkbox, toggle, or final kiosk screen)?
    - saved: Did the user click Save, OK, or Apply?
    - final_kiosk_view: Does the LAST screenshot look like a Kiosk/Self-Service welcome screen (usually minimal UI, big buttons) OR show the settings successfully applied?
    """

    vlm_response = query_vlm(images=frames, prompt=prompt)
    
    vlm_data = {}
    if vlm_response and vlm_response.get('success'):
        vlm_data = vlm_response.get('parsed', {})
    else:
        logger.warning(f"VLM query failed: {vlm_response.get('error')}")

    # =========================================================================
    # 3. Scoring Logic
    # =========================================================================
    score = 0
    feedback = []

    # Criterion 1: Application Health (10 pts)
    if app_running:
        score += 10
    else:
        feedback.append("Application was closed or crashed.")

    # Criterion 2: Navigation (Settings/Kiosk) (30 pts)
    if vlm_data.get('settings_opened', False):
        score += 15
        feedback.append("Opened settings.")
    if vlm_data.get('kiosk_section_found', False):
        score += 15
        feedback.append("Found Kiosk settings.")
    else:
        feedback.append("Did not find Kiosk/Self-Service settings.")

    # Criterion 3: Configuration (Text & Toggle) (40 pts)
    if vlm_data.get('text_entered', False):
        score += 20
        feedback.append(f"Entered text '{expected_welcome}'.")
    else:
        feedback.append(f"Missing welcome text '{expected_welcome}'.")
        
    if vlm_data.get('kiosk_enabled', False):
        score += 20
        feedback.append("Enabled Kiosk mode.")
    else:
        feedback.append("Did not enable Kiosk mode.")

    # Criterion 4: Persistence/Completion (Saved/File Mod) (20 pts)
    if settings_saved or vlm_data.get('saved', False):
        score += 10
        feedback.append("Settings saved (file modified or save clicked).")
    
    if vlm_data.get('final_kiosk_view', False):
        score += 10
        feedback.append("Final view shows Kiosk mode.")

    # Pass logic
    # Must have found settings, entered text, and app must be running.
    passed = (score >= 60) and app_running and vlm_data.get('text_entered', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "vlm_analysis": vlm_data,
            "programmatic_check": {
                "app_running": app_running,
                "settings_saved_file_check": settings_saved
            }
        }
    }