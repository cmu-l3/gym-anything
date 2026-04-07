#!/usr/bin/env python3
"""
Verifier for create_patient_referral task.
Performs programmatic validation of database rows combined with VLM trajectory validation.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_val_in_row(row, target_val):
    """Check if a target value (e.g. database ID or name) is present in ANY column of the row."""
    if not target_val:
        return False
    target_val = str(target_val).lower()
    for k, v in row.items():
        if v is not None and target_val in str(v).lower():
            return True
    return False

def check_keyword_in_row(row, keywords):
    """Check if any of the keywords are present in ANY text column of the row."""
    for k, v in row.items():
        if v is None:
            continue
        val_str = str(v).lower()
        if any(kw.lower() in val_str for kw in keywords):
            return True
    return False

def verify_create_patient_referral(traj, env_info, task_info):
    """
    Scoring Breakdown (100 Points Total):
    - 25: New referral record created
    - 20: Record linked to correct Patient
    - 10: Record linked to correct Referring Provider
    - 10: Record linked to correct Referred-to Provider
    - 15: Clinical reason populated
    - 10: Urgency marked
    - 10: VLM trajectory confirmed correct form usage
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Extract output results file
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

    table = result.get('table', 'none')
    new_referrals = result.get('new_referrals', [])
    patient_id = result.get('patient_id', '')
    chen_id = result.get('chen_id', '')
    wilson_id = result.get('wilson_id', '')

    logger.info(f"Referral Table Found: {table}")
    logger.info(f"New Referrals Created: {len(new_referrals)}")

    db_success = False
    
    # 1. Evaluate Programmatic DB Entries
    if table == 'none' or len(new_referrals) == 0:
        feedback_parts.append("No new referral records found in database.")
    else:
        score += 25
        feedback_parts.append(f"Found {len(new_referrals)} new referral(s)")
        
        # We take the best matching row if multiple exist to prevent strict failing on retries
        best_row_score = -1
        best_row_feedback = []
        
        for row in new_referrals:
            row_score = 0
            row_feedback = []
            
            # Check Patient (Matches either DB relations ID or plaintext fallback)
            if check_val_in_row(row, patient_id) or check_val_in_row(row, "Elena") or check_val_in_row(row, "Rodriguez"):
                row_score += 20
                row_feedback.append("Correct patient linked")
            
            # Check Referring Provider
            if check_val_in_row(row, chen_id) or check_val_in_row(row, "Chen"):
                row_score += 10
                row_feedback.append("Referring provider correct")
                
            # Check Referred-to Provider
            if check_val_in_row(row, wilson_id) or check_val_in_row(row, "Wilson"):
                row_score += 10
                row_feedback.append("Referred-to provider correct")
                
            # Check Clinical Reason Payload
            if check_keyword_in_row(row, ["chest", "pain", "cardiac", "heart", "exertion", "ecg"]):
                row_score += 15
                row_feedback.append("Clinical reason documented")
                
            # Check Urgency
            if check_keyword_in_row(row, ["urgent", "high", "stat", "asap", "2"]):
                row_score += 10
                row_feedback.append("Urgency flagged")
                
            if row_score > best_row_score:
                best_row_score = row_score
                best_row_feedback = row_feedback
                
        score += best_row_score
        feedback_parts.extend(best_row_feedback)
        db_success = best_row_score >= 40  # Passing threshold for DB portion

    # 2. Evaluate Trajectory Visually via VLM
    vlm_success = False
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=8)
            prompt = """Examine these screenshots from a medical records system.
Task: Create a patient referral for Elena Rodriguez to Dr. James Wilson for cardiology.
    
Did the user successfully navigate to a referral form, fill out the patient (Elena Rodriguez), referring provider (Chen), specialist (Wilson), and clinical notes (chest pain/cardiac)? Did they save it?

Return JSON format:
{
    "form_opened": true/false,
    "patient_selected": true/false,
    "providers_entered": true/false,
    "notes_entered": true/false,
    "saved": true/false,
    "overall_success": true/false
}
"""
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and "parsed" in vlm_result:
                parsed = vlm_result["parsed"]
                if parsed.get("overall_success"):
                    score += 10
                    vlm_success = True
                    feedback_parts.append("VLM verified successful GUI workflow")
                else:
                    feedback_parts.append("VLM did not verify full success")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("VLM trajectory verification failed")

    # If DB evaluation wasn't fully successful but VLM saw partial success
    if not db_success and vlm_success:
        score = max(score, 40)
        
    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }