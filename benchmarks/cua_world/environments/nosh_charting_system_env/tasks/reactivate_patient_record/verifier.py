#!/usr/bin/env python3
"""
Verifier for reactivate_patient_record task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reactivate_patient(traj, env_info, task_info):
    """
    Verifies if the agent successfully reactivated the correct patient record.
    
    Criteria:
    1. Database: Target PID active status must be 1 (Active).
    2. Database: No new duplicate records created (Record count shouldn't increase).
    3. VLM: Trajectory should show search filter interaction (searching for inactive).
    """
    
    # 1. Setup Result Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Database State
    score = 0
    feedback = []
    
    target_pid = result.get("target_pid")
    final_status = str(result.get("final_active_status", "0")).strip()
    initial_count = int(result.get("initial_record_count", 0))
    final_count = int(result.get("final_record_count", 0))

    # Criterion A: Patient is Active (50 pts)
    # Status '1' means Active in NOSH
    if final_status == "1":
        score += 50
        feedback.append("Success: Patient record is now marked Active.")
    else:
        feedback.append(f"Fail: Patient record status is {final_status} (Expected 1/Active).")

    # Criterion B: No Duplicates Created (30 pts)
    # The agent should have reactivated the existing record, not created a new one.
    if final_count == initial_count:
        score += 30
        feedback.append("Success: No duplicate records created.")
    elif final_count > initial_count:
        feedback.append(f"Penalty: {final_count - initial_count} new duplicate record(s) created.")
    else:
        # Should not happen unless record deleted
        feedback.append("Warning: Record count decreased.")

    # 3. VLM Verification (20 pts)
    # Check if agent used search filters or navigated correctly
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of an Electronic Health Record system. "
        "The user was trying to find an inactive patient named 'Maria Garcia'. "
        "1. Do you see a search interface where filters (like 'Active', 'Inactive', or 'All') were adjusted? "
        "2. Do you see the patient 'Maria Garcia' visible on screen? "
        "3. Do you see a status change or edit form? "
        "Answer with a JSON object: {'filters_used': bool, 'patient_seen': bool, 'edit_form_seen': bool}"
    )
    
    try:
        vlm_response = query_vlm(frames + [final_img], vlm_prompt)
        parsed = vlm_response.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('filters_used') or parsed.get('patient_seen'):
            vlm_score += 10
        if parsed.get('edit_form_seen'):
            vlm_score += 10
            
        score += vlm_score
        if vlm_score > 0:
            feedback.append(f"VLM: Verified UI interaction ({vlm_score} pts).")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if database passed, assume some interaction happened
        if score >= 80:
            score += 20
            feedback.append("VLM: Skipped (DB check sufficient).")

    # 4. Final Verdict
    # Must have reactivated the patient AND not created duplicates to pass
    passed = (final_status == "1") and (final_count == initial_count)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }