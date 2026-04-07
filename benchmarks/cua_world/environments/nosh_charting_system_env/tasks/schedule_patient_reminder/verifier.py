#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_patient_reminder(traj, env_info, task_info):
    """
    Verify that the agent scheduled a Mammogram reminder for 2025-10-01.
    
    Criteria:
    1. Database record exists (30 pts)
    2. Reminder text contains "Mammogram" (25 pts)
    3. Due date matches 2025-10-01 (25 pts)
    4. VLM visual confirmation of workflow (20 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_date = metadata.get('target_date', '2025-10-01')
    target_content = metadata.get('reminder_content', 'Mammogram')

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Database Evidence
    score = 0
    feedback = []
    
    found = result.get('found', False)
    actual_text = result.get('reminder_text', '')
    actual_date = result.get('due_date', '')  # Format from DB could be '2025-10-01' or '2025-10-01 00:00:00'

    # Check Existence (30 pts)
    if found:
        score += 30
        feedback.append("Reminder record created in database.")
    else:
        feedback.append("No reminder record found in database.")

    # Check Content (25 pts)
    if target_content.lower() in actual_text.lower():
        score += 25
        feedback.append(f"Reminder content correct: '{actual_text}'.")
    else:
        feedback.append(f"Reminder content mismatch. Expected '{target_content}', got '{actual_text}'.")

    # Check Date (25 pts)
    # Loose string matching for date to handle potential time components
    if target_date in str(actual_date):
        score += 25
        feedback.append(f"Due date correct: {actual_date}.")
    else:
        feedback.append(f"Due date mismatch. Expected '{target_date}', got '{actual_date}'.")

    # 4. VLM Verification (20 pts)
    # We check if the agent actually navigated to the reminders section
    vlm_score = 0
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for VLM
    prompt = (
        "Analyze these screenshots of an EHR system (NOSH).\n"
        "1. Did the user navigate to a patient named 'Lucinda Haag'?\n"
        "2. Did the user open a 'Reminders' or 'Recall' section?\n"
        "3. Is there a form or table showing a 'Mammogram' reminder being added or listed?\n"
        "4. Is the date '10/01/2025' or '2025-10-01' visible?\n"
        "Return yes/no and reasoning."
    )
    
    try:
        vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        # Simple keyword heuristic on VLM reasoning if structure parsing isn't guaranteed
        # But ideally we parse a structured response. Assuming broad success for now if meaningful keywords present.
        analysis = vlm_resp.get('response', '').lower()
        
        if "mammogram" in analysis and ("10/01/2025" in analysis or "2025" in analysis):
            vlm_score = 20
            feedback.append("VLM confirms visual evidence of reminder creation.")
        elif "reminders" in analysis or "recall" in analysis:
            vlm_score = 10
            feedback.append("VLM confirms navigation to Reminders, but specific details unclear.")
        else:
            feedback.append("VLM could not visually confirm the specific actions.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if DB is perfect, give full VLM points to avoid punishing for VLM outage
        if score == 80: 
            vlm_score = 20
            feedback.append("VLM check skipped, but database verification is perfect.")

    score += vlm_score

    # 5. Final Determination
    # Pass if record exists with correct content and date (Database score >= 80)
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }