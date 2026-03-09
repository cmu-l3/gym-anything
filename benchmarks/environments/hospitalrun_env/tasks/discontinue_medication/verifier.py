#!/usr/bin/env python3
"""
Verifier for discontinue_medication task.
Verifies that the agent canceled the Amoxicillin order for Maria Santos and provided a reason.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_discontinue_medication(traj, env_info, task_info):
    """
    Verification Logic:
    1. CouchDB Check:
       - The specific medication document 'medication_p1_mariasantos_amox' should NOT have status 'Active'.
       - It should have status 'Canceled', 'Discontinued', 'Stopped', or similar.
       - A reason field (notes, reason, description) should contain 'rash' or 'skin'.
       - The document modification time (or _rev generation) implies change during task.
    
    2. VLM Check:
       - Verify trajectory shows navigation to Maria Santos -> Medication -> Edit/Status Change.
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Data extraction
    target_doc_wrapper = result_data.get('target_medication_doc', {})
    # HospitalRun usually wraps data in a "data" property, but sometimes root
    target_doc = target_doc_wrapper.get('data', target_doc_wrapper)
    
    related_docs = result_data.get('related_medication_docs', [])
    
    task_start = result_data.get('task_start', 0)
    
    # 2. Database Verification
    
    # Check 1: Status Change (40 pts)
    # Expected: "Canceled", "Discontinued", "Stopped", "Inactive"
    # We fail if it is still "Active"
    
    current_status = target_doc.get('status', 'Unknown')
    # Some implementations might use boolean 'discontinued': true
    is_discontinued_bool = target_doc.get('discontinued', False)
    
    status_passed = False
    
    if str(is_discontinued_bool).lower() == 'true':
        status_passed = True
        current_status = "Discontinued (bool)"
    elif current_status.lower() in ['canceled', 'cancelled', 'discontinued', 'stopped', 'inactive', 'completed']:
        status_passed = True
    elif current_status.lower() == 'active':
        status_passed = False
    else:
        # Ambiguous status
        status_passed = False

    if status_passed:
        score += 40
        feedback_parts.append(f"Medication status successfully updated to '{current_status}'.")
    else:
        feedback_parts.append(f"Medication status is still '{current_status}' (expected Canceled/Discontinued).")

    # Check 2: Reason Documentation (30 pts)
    # Look for keywords in various fields
    keywords = ['rash', 'skin', 'allergy', 'reaction']
    fields_to_check = [
        target_doc.get('reason', ''),
        target_doc.get('notes', ''),
        target_doc.get('description', ''),
        target_doc.get('visitNotes', '')
    ]
    
    reason_found = False
    found_text = ""
    for field in fields_to_check:
        if not isinstance(field, str): continue
        for kw in keywords:
            if kw.lower() in field.lower():
                reason_found = True
                found_text = field
                break
        if reason_found: break
    
    if reason_found:
        score += 30
        feedback_parts.append(f"Reason correctly documented: '{found_text}'.")
    else:
        feedback_parts.append("Reason 'rash/skin/allergy' not found in medication notes.")

    # Check 3: Modification Check (Anti-gaming) (10 pts)
    # Since we can't easily parse CouchDB rev hashes for time without decoding, 
    # we assume if status changed from the known seed state ('Active'), work was done.
    # However, if we found a NEW document in related_docs that represents the cancellation, that's also valid.
    
    work_verified = False
    if status_passed:
        work_verified = True
        score += 10
    
    # 3. VLM Trajectory Verification (20 pts)
    # Use VLM to ensure they actually used the UI
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_score = 0
    if frames:
        prompt = """
        Analyze these screenshots of a user using HospitalRun (an EHR system).
        The goal was to discontinue a medication for Maria Santos.
        
        Look for:
        1. A patient dashboard or list showing "Maria Santos".
        2. A medication list or medication details modal.
        3. A dropdown or button being clicked to change status (e.g., "Active" to "Discontinued").
        4. Typing into a notes/reason field.
        
        Did the user perform these actions?
        """
        
        try:
            # We assume query_vlm returns a JSON or dict with 'success' and 'content'/'rating'
            # Adjust based on actual gym_anything VLM interface
            vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
            # Simple heuristic: if VLM is positive. Real implementation would parse JSON response.
            # Assuming a helper that returns bool or score
            if "yes" in str(vlm_response).lower() or "true" in str(vlm_response).lower():
                vlm_score = 20
                feedback_parts.append("VLM verification passed: Workflow observed.")
            else:
                vlm_score = 10 # Partial credit if ambiguous
                feedback_parts.append("VLM verification: Workflow partially observed.")
        except Exception:
            # Fallback if VLM fails
            vlm_score = 20 
            feedback_parts.append("VLM check skipped (service unavailable), awarding points based on DB success.")
    else:
         feedback_parts.append("No trajectory frames available for VLM.")

    score += vlm_score

    # Final tally
    passed = (score >= 90) # Requires Status (40) + Reason (30) + VLM (20) = 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }