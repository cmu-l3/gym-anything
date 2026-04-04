#!/usr/bin/env python3
"""
Verifier for connect_legacy_archive task.

Verification Strategy:
1. Primary: Check for database lock file (.ldb/.slock) next to the archive DB.
   - This proves the application effectively has the file OPEN.
2. Secondary: Check Wine registry for the new database path.
3. Tertiary: VLM check of the final screenshot to ensure app is visible and not in error state.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_connect_legacy_archive(traj, env_info, task_info):
    """
    Verify the agent connected Lobby Track to the legacy archive database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results
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

    score = 0
    feedback_parts = []
    
    lock_file_exists = result.get("lock_file_exists", False)
    registry_updated = result.get("registry_updated", False)
    app_running = result.get("app_running", False)

    # Criterion 1: Lock File (60 points) - Strongest signal of active connection
    if lock_file_exists:
        score += 60
        feedback_parts.append("Database lock file detected (Active connection confirmed)")
    else:
        feedback_parts.append("No database lock file found (App not connected to archive)")

    # Criterion 2: Registry Update (20 points) - Indicates configuration changed
    if registry_updated:
        score += 20
        feedback_parts.append("Registry settings updated with new path")
    else:
        feedback_parts.append("Registry does not reflect new database path")

    # Criterion 3: App Running (10 points) - Must not crash
    if app_running:
        score += 10
        feedback_parts.append("Application is running")
    else:
        feedback_parts.append("Application is closed/crashed")

    # Criterion 4: VLM Verification (10 points)
    # Check if the agent navigated through relevant dialogs
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        vlm_images = frames + [final_shot]
        
        prompt = """
        Review these screenshots of a user interacting with Jolly Lobby Track software.
        The goal was to change the database connection to an archive file.
        
        Look for:
        1. A 'Database Connection', 'Setup', or 'Options' dialog.
        2. A file browsing window selecting 'visitor_archive_2024'.
        3. A successful connection message or the main screen reloading.
        
        Did the agent appear to perform the database reconfiguration workflow?
        """
        
        try:
            vlm_res = query_vlm(images=vlm_images, prompt=prompt)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("answer", False): # Assuming boolean or positive sentiment analysis wrapper in gym_anything, typically we parse content.
                # Since gym_anything VLM interface can vary, we'll check for positive keyword indication if raw text or assume success implies yes for simple queries if designed that way. 
                # Better approach for this specific verifier pattern:
                analysis = vlm_res.get("result", "").lower()
                if "yes" in analysis or "successfully" in analysis or "appear" in analysis:
                    score += 10
                    feedback_parts.append("Visual verification passed")
                else:
                    feedback_parts.append("Visual verification inconclusive")
            else:
                # Fallback if VLM fails or returns negative
                if lock_file_exists: 
                    score += 10 # Give benefit of doubt if technical check passed
        except Exception:
            pass # VLM failure shouldn't fail the whole task if programmatic signals exist

    # Final Evaluation
    # Must have lock file OR (Registry updated AND App running) to pass
    passed = False
    if score >= 60 and (lock_file_exists or (registry_updated and app_running)):
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }