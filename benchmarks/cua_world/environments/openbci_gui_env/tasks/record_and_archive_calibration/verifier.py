#!/usr/bin/env python3
"""
Verifier for record_and_archive_calibration task.

Verification Criteria:
1. File Existence: 'alpha_calibration.txt' must exist in the recordings folder.
2. Anti-Gaming (Timestamp): The file must have been created *after* the task started.
3. Data Volume: File must contain sufficient data rows (>1000 lines) to represent ~5 seconds.
4. Format: File must appear to be a valid OpenBCI text log.
5. VLM Verification: Confirm visual evidence of recording workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calibration_recording(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    passed = False

    # --- CRITERION 1 & 2: File Existence & Freshness (40 pts) ---
    output_exists = result.get("output_exists", False)
    created_during_task = result.get("file_created_during_task", False)

    if output_exists:
        if created_during_task:
            score += 40
            feedback.append("Success: 'alpha_calibration.txt' created during task session.")
        else:
            # File exists but old -> Failed anti-gaming
            feedback.append("Failure: 'alpha_calibration.txt' exists but is stale (created before task).")
    else:
        feedback.append("Failure: 'alpha_calibration.txt' not found in Recordings folder.")

    # --- CRITERION 3: Data Quantity (30 pts) ---
    line_count = result.get("line_count", 0)
    # Header is usually ~6 lines. 5 seconds @ 250Hz = 1250 lines.
    # Allow leniency: >500 lines is clearly an attempt to record something.
    if line_count > 1000:
        score += 30
        feedback.append(f"Success: Recording length adequate ({line_count} lines).")
    elif line_count > 100:
        score += 10
        feedback.append(f"Partial: Recording file is very short ({line_count} lines), expected >1000.")
    else:
        if output_exists:
            feedback.append("Failure: File is empty or too short.")

    # --- CRITERION 4: File Content/Format (10 pts) ---
    is_valid_format = result.get("is_openbci_format", False)
    if is_valid_format:
        score += 10
        feedback.append("Success: File format appears valid (OpenBCI headers detected).")

    # --- CRITERION 5: VLM Verification (20 pts) ---
    # Check if the agent actually used the GUI controls
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of an OpenBCI GUI task.\n"
            "The user goal is to: 'Start Recording' and then 'Stop Recording' to create a file.\n"
            "1. Do you see the OpenBCI GUI?\n"
            "2. Do you see the 'Start Recording' or 'Stop Recording' buttons being used, or the recording timer active?\n"
            "3. Do you see a file manager or terminal window used for renaming a file?\n"
            "Answer 'Yes' if the workflow is visible."
        )
        
        try:
            vlm_response = query_vlm(images=frames + [final_shot], prompt=prompt)
            if vlm_response.get('success'):
                # Simple keyword matching on the response
                text = vlm_response.get('response', '').lower()
                if "yes" in text or "visible" in text or "recording" in text:
                    vlm_score = 20
                    feedback.append("Visual verification: Workflow confirmed.")
                else:
                    feedback.append("Visual verification: Could not confirm recording workflow.")
        except Exception:
            feedback.append("Visual verification: Skipped due to error.")
    
    score += vlm_score

    # Final Pass Determination
    # Must have the file, created now, with data.
    if output_exists and created_during_task and line_count > 500:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }