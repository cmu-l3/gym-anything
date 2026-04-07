#!/usr/bin/env python3
"""
Verifier for configure_speed_warnings task.

Scoring Criteria:
1. Files modified (Activity check) - 10 pts
2. Speed limit warning enabled (Config check) - 25 pts
3. Tolerance set to 10 km/h (Config check) - 20 pts
4. Speed camera warning enabled (Config check) - 20 pts
5. App still running (Stability check) - 5 pts
6. VLM Verification (Visual confirmation of settings menu) - 20 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_speed_warnings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # =======================================================
    # 1. Retrieve and Parse JSON Result from Container
    # =======================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    settings = result.get("settings_detected", {})

    # =======================================================
    # 2. Activity & Stability Checks (15 pts)
    # =======================================================
    if result.get("files_modified_during_task", False):
        score += 10
        feedback.append("Settings files were modified.")
    else:
        feedback.append("No settings files changed (did you save?).")

    if result.get("app_running", False):
        score += 5
        feedback.append("App exited cleanly.")

    # =======================================================
    # 3. Configuration Checks (65 pts)
    # =======================================================
    # Speed Warning
    if settings.get("speed_warning_enabled", False):
        score += 25
        feedback.append("Speed limit warning verified enabled.")
    else:
        feedback.append("Speed limit warning NOT detected.")

    # Tolerance
    if settings.get("tolerance_set_to_10", False):
        score += 20
        feedback.append("Speed tolerance verified at 10 km/h.")
    else:
        feedback.append("Speed tolerance NOT set to 10 km/h.")

    # Camera Warning
    if settings.get("camera_warning_enabled", False):
        score += 20
        feedback.append("Speed camera warning verified enabled.")
    else:
        feedback.append("Speed camera warning NOT detected.")

    # =======================================================
    # 4. VLM Verification (20 pts)
    # =======================================================
    # Use trajectory frames to verify the agent actually visited the settings
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying an agent's actions in a GPS Navigation app.
    The agent was supposed to:
    1. Go to Settings > Warnings/Notifications.
    2. Enable Speed Limit warnings.
    3. Set Speed Tolerance to +10 km/h.
    4. Enable Speed Camera/Radar warnings.

    Look at these screenshots. 
    - Do you see a Settings menu?
    - Do you see a 'Warnings' or 'Notifications' section?
    - Do you see options for 'Speed limit' or 'Speed cameras'?
    - Can you see any value set to '10 km/h' or similar?

    Return valid JSON:
    {
        "settings_visited": true/false,
        "warnings_menu_seen": true/false,
        "tolerance_value_visible": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("settings_visited"):
            vlm_score += 10
        if parsed.get("warnings_menu_seen"):
            vlm_score += 5
        if parsed.get("tolerance_value_visible"):
            vlm_score += 5
            
        feedback.append(f"VLM verification confidence: {parsed.get('confidence')}")
    
    score += vlm_score
    if vlm_score > 0:
        feedback.append(f"Visual verification passed (+{vlm_score} pts).")

    # =======================================================
    # Final Scoring
    # =======================================================
    # Pass threshold: 60 points, but MUST have enabled the main speed warning
    passed = (score >= 60) and settings.get("speed_warning_enabled", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }