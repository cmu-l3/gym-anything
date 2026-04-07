#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_patient_no_show(traj, env_info, task_info):
    """
    Verify that the agent updated the patient's appointment status to 'No Show'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Check Database Status (Primary Verification)
    final_status = str(result.get("final_status", "")).lower().replace("_", "").replace(" ", "")
    # Acceptable variations of "No Show" in DB
    valid_statuses = ["noshow", "no show", "no_show", "missed"]
    
    status_correct = any(s in final_status for s in valid_statuses)
    
    if status_correct:
        score += 50
        feedback.append("Database confirms appointment status updated to 'No Show'.")
    elif "active" in final_status:
        feedback.append("Appointment status is still 'Active'. Agent failed to update status.")
    else:
        feedback.append(f"Appointment status is '{result.get('final_status')}', expected 'No Show'.")

    # 3. VLM Verification (Secondary Verification - Anti-Gaming)
    # Ensure the agent actually navigated the calendar
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = (
            "Review these screenshots of an EHR system interaction. "
            "Does the user navigate to a calendar or schedule view? "
            "Is there any indication of selecting a past date or seeing an appointment slot? "
            "Does the final screen show an appointment marked as 'No Show' or a dialog for changing status? "
            "Respond 'Yes' if the workflow to mark a no-show is visible."
        )
        
        try:
            vlm_response = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
            if vlm_response.get("success") and "yes" in vlm_response.get("parsed", {}).get("answer", "").lower():
                score += 30
                feedback.append("Visual evidence confirms calendar navigation.")
            else:
                feedback.append("Visual evidence is unclear about calendar navigation.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if DB is correct, give partial VLM points
            if status_correct:
                score += 15

    # 4. Final Validity Check
    # Ensure the record wasn't deleted (id must still exist)
    if result.get("appointment_id") and result.get("appointment_id") != "0":
        score += 20
        feedback.append("Appointment record preserved (not deleted).")
    else:
        feedback.append("Appointment record appears missing/deleted.")

    passed = score >= 80 and status_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }