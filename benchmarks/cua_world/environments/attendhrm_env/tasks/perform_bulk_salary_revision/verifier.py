#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_bulk_salary_revision(traj, env_info, task_info):
    """
    Verifies that the agent performed the bulk salary revision correctly.
    
    Verification Signals:
    1. DB Check: 3 Junior Developers updated to 3500.00 on 2025-04-01.
    2. DB Check: No other employees affected.
    3. VLM: Visual confirmation of the bulk update workflow.
    """
    
    # 1. Retrieve result JSON from the Windows environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Adjust path to match where export_result.ps1 saved it
        # gym_anything usually handles path conversion, but we use the path defined in the script
        copy_from_env("C:\\workspace\\tasks\\perform_bulk_salary_revision\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data from environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Programmatic Criteria
    targets_updated = result_data.get("targets_updated_count", 0)
    non_targets_affected = result_data.get("non_targets_affected_count", 0)
    app_running = result_data.get("app_was_running", False)

    score = 0
    feedback = []

    # Criterion A: Targets Updated (Max 50)
    if targets_updated == 3:
        score += 50
        feedback.append("Success: All 3 Junior Developers records were updated.")
    elif targets_updated > 0:
        score += 20
        feedback.append(f"Partial: Only {targets_updated}/3 Junior Developers updated.")
    else:
        feedback.append("Fail: No Junior Developer records were updated correctly.")

    # Criterion B: Non-Targets Protected (Max 20)
    if non_targets_affected == 0:
        score += 20
        feedback.append("Success: No incorrect employees were modified.")
    else:
        feedback.append(f"Warning: {non_targets_affected} unrelated employees were incorrectly updated.")

    # 3. VLM Verification (Max 30)
    # We look for evidence of the Salary Increment module and bulk selection
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user interacting with AttendHRM (HR Software).
    The task is to perform a bulk salary revision for 'Junior Developers'.
    
    Look for:
    1. The 'Salary Increment' or 'Salary Revision' screen.
    2. Evidence of selecting specific employees (checkboxes, filters by designation).
    3. Entering the amount '3500' and date '01-Apr-2025' (or 01/04/2025).
    4. A success message or saved state in the final frame.
    
    Did the agent appear to perform a bulk update?
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    # Heuristic scoring based on VLM text
    vlm_score = 0
    if "3500" in str(vlm_result).lower() or "salary" in str(vlm_result).lower():
        vlm_score += 15
    if "junior" in str(vlm_result).lower() or "filter" in str(vlm_result).lower() or "select" in str(vlm_result).lower():
        vlm_score += 15
        
    score += vlm_score
    if vlm_score > 0:
        feedback.append("VLM: Visual evidence of salary update workflow found.")

    # 4. Final Determination
    passed = (targets_updated == 3) and (non_targets_affected == 0) and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }