#!/usr/bin/env python3
"""
Verifier for restore_patient task.

Criteria:
1. Patient 'Deleted Patient' must exist and NOT be voided (60 pts).
2. Patient record must have been modified AFTER task start time (30 pts).
3. VLM Verification of workflow (10 pts).
"""

import json
import logging
import os
import tempfile
import dateutil.parser
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_patient(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic result
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
    feedback_parts = []
    
    # 2. Programmatic Checks
    patient_found = result.get("patient_found", False)
    is_voided = result.get("is_voided", True)
    date_changed_iso = result.get("date_changed", "")
    task_start_ts = result.get("task_start_ts", 0)

    # Check 1: Patient Active Status (60 pts)
    if patient_found and not is_voided:
        score += 60
        feedback_parts.append("✅ Patient is active (un-voided).")
    elif not patient_found:
        feedback_parts.append("❌ Target patient not found in system.")
    else:
        feedback_parts.append("❌ Patient is still voided.")

    # Check 2: Anti-Gaming Timestamp (30 pts)
    # Ensure the change happened during the task
    mod_valid = False
    if date_changed_iso:
        try:
            # Parse ISO string to timestamp
            # OpenMRS format example: "2023-10-27T10:00:00.000+0000"
            change_dt = dateutil.parser.parse(date_changed_iso)
            change_ts = change_dt.timestamp()
            
            # Allow a small buffer (e.g., 5 seconds) for clock skew
            if change_ts > (task_start_ts - 5):
                score += 30
                mod_valid = True
                feedback_parts.append("✅ Modification timestamp verified.")
            else:
                feedback_parts.append(f"❌ Patient modified before task start (Task: {task_start_ts}, Mod: {change_ts}).")
        except Exception as e:
            feedback_parts.append(f"⚠️ Could not parse modification date: {e}")
    else:
        feedback_parts.append("❌ No modification date found on record.")

    # 3. VLM Verification (10 pts)
    # We look for evidence of the admin interface, search, or unvoid action
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        images = frames + ([final_ss] if final_ss else [])
        
        prompt = """
        Analyze these screenshots of a user interacting with the OpenMRS/Bahmni Administration interface.
        The user's goal is to find a "voided" (deleted) patient and restore them.
        
        Look for:
        1. The OpenMRS Administration Page or "Manage Patients" screen.
        2. A search action where "Include Voided" (or similar) is checked or a voided patient is visible (often shown with strikethrough or 'Voided' label).
        3. An "Unvoid" or "Restore" button/link being clicked or available.
        4. A success message or the patient profile showing active status.
        
        Did the user appear to perform the steps to find and restore a voided patient?
        Respond "YES" or "NO" with brief reasoning.
        """
        
        try:
            vlm_resp = query_vlm(images=images, prompt=prompt).get('parsed', {})
            # Simple heuristic check on response
            if isinstance(vlm_resp, str): # Handle raw string response if wrapper doesn't parse
                lower_resp = vlm_resp.lower()
                if "yes" in lower_resp:
                    vlm_score = 10
            elif vlm_resp.get("answer", "").lower() == "yes":
                 vlm_score = 10
            
            # Fallback manual grading logic if structured parsing isn't guaranteed:
            # We assume query_vlm returns a dict with 'output' or 'response' text
            full_text = str(vlm_resp).lower()
            if "yes" in full_text and "no" not in full_text[:5]: # "No" at start means fail
                 vlm_score = 10
                 feedback_parts.append("✅ VLM verified workflow.")
            else:
                 feedback_parts.append("⚠️ VLM did not clearly verify workflow.")
                 
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("⚠️ VLM check skipped due to error.")
    
    score += vlm_score

    # Final Pass Determination
    # Must be unvoided AND modified during task to pass
    passed = (not is_voided) and mod_valid and (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }