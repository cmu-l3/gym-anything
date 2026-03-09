#!/usr/bin/env python3
"""
Verifier for configure_work_shift task in AttendHRM.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_work_shift(traj, env_info, task_info):
    """
    Verify that the 'Night Shift' was created with correct timings.
    
    Strategy:
    1. Anti-gaming: Check if DB file was modified during task (implies save action).
    2. VLM Trajectory: Verify navigation to Shift module.
    3. VLM Final/Trajectory: Verify specific values (Name: Night Shift, Start: 22:00, End: 06:00).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Anti-Gaming Data from Container
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path in container is C:\workspace\task_result.json
        # The copy_from_env tool handles the path translation if the env is set up correctly,
        # but often we need to be careful. Assuming standard mapping.
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy task result: {e}")
        # We continue, but score will be impacted
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Anti-Gaming (DB Modification)
    db_modified = task_result.get("db_modified_during_task", False)
    app_running = task_result.get("app_was_running", False)
    
    # 3. VLM Verification
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    prompt = """
    You are analyzing screenshots of a user interacting with AttendHRM (HR Management Software).
    The user's goal is to create a new shift named "Night Shift".
    
    Please verify the following actions based on the screenshots:
    1. Did the user navigate to the 'Shift' configuration screen? (Look for windows titled "Shift", "Shift Details", or lists of shifts)
    2. Did the user enter the name "Night Shift"?
    3. Did the user set the Start Time to 22:00 (or 10:00 PM)?
    4. Did the user set the End Time to 06:00 (or 6:00 AM)?
    5. Is the "Night Shift" visible in the list of shifts at the end?
    
    Provide a JSON response with the following keys:
    - shift_screen_visited (bool)
    - name_entered (bool)
    - start_time_correct (bool)
    - end_time_correct (bool)
    - shift_saved_and_visible (bool)
    - confidence (0.0 to 1.0)
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if not vlm_result.get("success"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"VLM verification failed: {vlm_result.get('error')}"
        }
        
    parsed = vlm_result.get("parsed", {})
    
    # Scoring
    score = 0
    feedback = []
    
    # Criterion 1: App running (10 pts)
    if app_running:
        score += 10
    else:
        feedback.append("AttendHRM was not running at the end.")

    # Criterion 2: DB Modified (Save occurred) (20 pts)
    if db_modified:
        score += 20
        feedback.append("Database modification detected (Save action confirmed).")
    else:
        feedback.append("No database changes detected (Did you save the shift?).")

    # Criterion 3: VLM Navigation (10 pts)
    if parsed.get("shift_screen_visited"):
        score += 10
        feedback.append("Navigated to Shift configuration.")
    else:
        feedback.append("Could not confirm navigation to Shift configuration.")

    # Criterion 4: Values (40 pts)
    if parsed.get("name_entered"):
        score += 10
    if parsed.get("start_time_correct"):
        score += 15
    if parsed.get("end_time_correct"):
        score += 15

    # Criterion 5: Success Confirmation (20 pts)
    if parsed.get("shift_saved_and_visible"):
        score += 20
        feedback.append("Night Shift confirmed visible in list.")
    else:
        feedback.append("Could not confirm Night Shift in final list.")

    # Pass logic
    # Must have DB modified OR strong visual evidence of save
    # Must have correct times
    passed = (score >= 70) and (parsed.get("start_time_correct") and parsed.get("end_time_correct"))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": parsed
    }