#!/usr/bin/env python3
"""
Verifier for cancel_surgical_plan task.

Criteria:
1. Operative plan status must be 'Canceled' (40 pts)
2. Reason ('flu') must be documented in notes/instructions (30 pts)
3. Document must have been modified during the task (anti-gaming) (15 pts)
4. Application was running (5 pts)
5. VLM verification of the cancellation (10 pts)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cancel_surgical_plan(traj, env_info, task_info):
    """
    Verify that the agent cancelled the surgery and documented the reason.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_status = metadata.get('target_status', 'Canceled').lower()
    reason_keywords = metadata.get('cancellation_reason_keywords', ['flu'])
    
    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    doc = result.get('plan_doc', {})
    # HospitalRun wrapper data check
    data = doc.get('data', doc)
    
    # 1. Check if doc exists (Critical)
    if not result.get('doc_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target operative plan document not found. Was it deleted?"
        }

    # 2. Check Status (40 pts)
    current_status = data.get('status', '').lower()
    if current_status == target_status or current_status == 'cancelled':
        score += 40
        feedback_parts.append("Status updated to Canceled")
    else:
        feedback_parts.append(f"Status mismatch: expected '{target_status}', got '{current_status}'")

    # 3. Check Reason Documentation (30 pts)
    # The agent might put the note in 'admissionInstructions', 'notes', or 'operationDescription'
    combined_notes = (
        str(data.get('admissionInstructions', '')) + " " +
        str(data.get('notes', '')) + " " +
        str(data.get('additionalNotes', '')) + " " +
        str(data.get('operationDescription', ''))
    ).lower()
    
    found_keyword = False
    for keyword in reason_keywords:
        if keyword in combined_notes:
            found_keyword = True
            break
            
    if found_keyword:
        score += 30
        feedback_parts.append("Cancellation reason (flu) documented")
    else:
        feedback_parts.append("Cancellation reason ('flu') NOT found in notes")

    # 4. Anti-gaming: Was modified? (15 pts)
    if result.get('was_modified', False):
        score += 15
        feedback_parts.append("Record was modified during task")
    else:
        feedback_parts.append("Record was NOT modified (revision unchanged)")

    # 5. App running (5 pts)
    if result.get('app_was_running', False):
        score += 5

    # 6. VLM Verification (10 pts)
    # Check if final screenshot shows the plan in Canceled state
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        try:
            vlm_resp = query_vlm(
                image=final_screenshot,
                prompt="Is this a medical record screen? Can you see 'Canceled' or 'Cancelled' status for a surgery? Answer JSON with boolean 'is_canceled'."
            )
            if vlm_resp.get('parsed', {}).get('is_canceled', False):
                vlm_score = 10
                feedback_parts.append("VLM confirmed canceled status visually")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Final Pass Logic
    # Must have correct status AND reason to pass
    passed = (current_status in [target_status, 'cancelled']) and found_keyword and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }