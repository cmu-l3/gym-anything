#!/usr/bin/env python3
"""
Verifier for allow_dnd_override task.

Verifies:
1. Do Not Disturb (Zen Mode) is currently ON.
2. Flight Crew View (com.robert.fcView) is configured to bypass DND.
3. User navigated through Settings.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_allow_dnd_override(traj, env_info, task_info):
    """
    Verify that the agent enabled DND and added the app as an exception.
    """
    # 1. Setup access to file copy
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve result JSON from the device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/tasks/allow_dnd_override/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task verification data. Did the task complete?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Parse and Score
    score = 0
    feedback_parts = []
    
    # Criterion 1: DND Mode Active (25 pts)
    # zen_mode: 0=OFF, 1=IMPORTANT, 2=NO_INTERRUPTIONS, 3=ALARMS
    zen_mode = str(result.get("final_zen_mode", "0")).strip()
    is_dnd_on = zen_mode in ["1", "2", "3"]
    
    if is_dnd_on:
        score += 25
        feedback_parts.append("✅ Do Not Disturb is currently ON")
    else:
        feedback_parts.append("❌ Do Not Disturb is NOT enabled")

    # Criterion 2: App Exception Configured (35 pts)
    # Checked via notification policy or channel bypass flag
    is_policy_allowed = result.get("app_allowed_in_policy", False)
    is_channel_bypass = result.get("channel_bypass_dnd", False)
    
    if is_policy_allowed or is_channel_bypass:
        score += 35
        feedback_parts.append("✅ Flight Crew View is allowed to bypass DND")
    else:
        feedback_parts.append("❌ Flight Crew View is NOT in the DND exception list")

    # Criterion 3: Settings Visited (20 pts)
    # Ensures agent didn't just use adb shell or magic (anti-gaming)
    if result.get("settings_visited", False):
        score += 20
        feedback_parts.append("✅ Navigated through Android Settings")
    else:
        feedback_parts.append("❌ Did not access Settings app")

    # Criterion 4: Timing/Anti-gaming (20 pts)
    # Task shouldn't be instant (impossible for UI interaction)
    start = result.get("task_start", 0)
    end = result.get("task_end", 0)
    duration = end - start
    
    if duration > 5:
        score += 20
        feedback_parts.append(f"✅ Realistic duration ({duration}s)")
    else:
        feedback_parts.append("⚠️ Task completed suspiciously fast")

    # 4. Final Verdict
    # Pass requires DND ON (25) + Exception Configured (35) = 60 minimum
    passed = (score >= 60) and is_dnd_on and (is_policy_allowed or is_channel_bypass)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }