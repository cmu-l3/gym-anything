#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_check_in_patient(traj, env_info, task_info):
    """
    Verifies the patient check-in task.
    
    Criteria:
    1. Appointment status changed from 'Pending' to 'Arrived'/'Checked In'.
    2. Appointment reason updated to contain 'migraine' and 'aura'.
    3. Modification happened during the task window (anti-gaming).
    4. VLM visual confirmation of calendar interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # Data extraction
    final_status = result.get('final_status', '').lower()
    final_reason = result.get('final_reason', '').lower()
    db_updated_ts = result.get('db_updated_ts', 0)
    task_start = result.get('task_start', 0)
    
    # 1. Verify Status Change (40 pts)
    # Status should NOT be Pending, and should ideally be Arrived or Checked In
    excluded_statuses = [s.lower() for s in metadata.get('required_status_excludes', ['pending'])]
    
    if final_status and final_status not in excluded_statuses:
        # Check if it actually looks like a check-in status
        if any(x in final_status for x in ['arrived', 'check', 'here', 'ready']):
            score += 40
            feedback_parts.append(f"Status correctly updated to '{final_status}'")
        else:
            score += 20
            feedback_parts.append(f"Status changed to '{final_status}' (partial credit, expected Arrived/Checked In)")
    else:
        feedback_parts.append(f"Status remains '{final_status}' (failed)")

    # 2. Verify Reason Update (30 pts)
    required_keywords = metadata.get('required_reason_keywords', ['migraine', 'aura'])
    keywords_found = [k for k in required_keywords if k in final_reason]
    
    if len(keywords_found) == len(required_keywords):
        score += 30
        feedback_parts.append(f"Reason correctly updated: '{final_reason}'")
    elif len(keywords_found) > 0:
        score += 15
        feedback_parts.append(f"Reason partially updated (found {keywords_found}): '{final_reason}'")
    else:
        feedback_parts.append(f"Reason does not match requirements. Found: '{final_reason}'")

    # 3. Anti-Gaming Timestamp Check (10 pts)
    if db_updated_ts > task_start:
        score += 10
        feedback_parts.append("Database record modified during task window")
    else:
        feedback_parts.append("Record NOT modified during task (timestamp too old)")

    # 4. VLM Verification (20 pts)
    # Check if agent was looking at the calendar/schedule
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if frames and final_img:
            vlm_prompt = (
                "Review these screenshots of an Electronic Health Record system. "
                "1. Is a calendar or schedule view visible? "
                "2. Is there an appointment block for 'Arthur' or 'Dent'? "
                "3. Does the final state show the appointment status as 'Arrived' (often a green block or checkmark)?"
            )
            vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
            
            # Simple heuristic on VLM text output if structured parsing isn't available
            vlm_text = str(vlm_res).lower()
            if "yes" in vlm_text and ("calendar" in vlm_text or "schedule" in vlm_text):
                score += 20
                feedback_parts.append("Visual verification passed")
            else:
                score += 5 # Participation points for having images
                feedback_parts.append("Visual verification inconclusive")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback_parts.append("VLM verification skipped due to error")

    passed = score >= 70 and ("migraine" in final_reason)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }