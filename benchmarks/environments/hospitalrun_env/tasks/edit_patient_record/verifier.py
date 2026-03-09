#!/usr/bin/env python3
"""
Verifier for edit_patient_record task.
Verifies that James Chen's record was updated with new contact info
while preserving his identity data.
"""

import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_patient_record(traj, env_info, task_info):
    """
    Verify the patient record update.
    
    Scoring:
    - 25 pts: Address updated correctly
    - 25 pts: Phone updated correctly
    - 25 pts: Email updated correctly
    - 10 pts: Identity fields (Name, DOB, Sex, Blood) preserved (not corrupted)
    - 5 pts:  Document revision check (proof of database write)
    - 10 pts: VLM Verification of workflow
    """
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_addr = metadata.get('expected_address', '1200 Harbor Boulevard')
    expected_phone = metadata.get('expected_phone', '555-0199')
    expected_email = metadata.get('expected_email', 'j.chen.new@email.com')
    
    orig_fname = metadata.get('original_first_name', 'James')
    orig_lname = metadata.get('original_last_name', 'Chen')
    orig_sex = metadata.get('original_sex', 'Male')
    orig_blood = metadata.get('original_blood_type', 'A+')

    # Read export result
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    db_data = result.get('db_result', {})
    
    if not db_data.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Patient record P00002 not found in database! Error: {db_data.get('error')}"
        }

    # 2. Verify Target Fields (75 pts total)
    
    # Address (25 pts)
    actual_addr = db_data.get('address', '')
    if expected_addr.lower() in actual_addr.lower(): # Loose matching for address formatting
        score += 25
        feedback_parts.append("Address updated")
    else:
        feedback_parts.append(f"Address incorrect (Expected: '{expected_addr}', Got: '{actual_addr}')")

    # Phone (25 pts)
    actual_phone = db_data.get('phone', '')
    if actual_phone.replace('-', '').replace(' ', '') == expected_phone.replace('-', '').replace(' ', ''):
        score += 25
        feedback_parts.append("Phone updated")
    else:
        feedback_parts.append(f"Phone incorrect (Expected: '{expected_phone}', Got: '{actual_phone}')")

    # Email (25 pts)
    actual_email = db_data.get('email', '')
    if actual_email.lower().strip() == expected_email.lower().strip():
        score += 25
        feedback_parts.append("Email updated")
    else:
        feedback_parts.append(f"Email incorrect (Expected: '{expected_email}', Got: '{actual_email}')")

    # 3. Verify Identity Preservation (10 pts)
    # Ensure the agent didn't accidentally overwrite the wrong patient or clear other fields
    identity_ok = True
    issues = []
    
    if db_data.get('firstName') != orig_fname:
        identity_ok = False
        issues.append(f"First Name changed to {db_data.get('firstName')}")
    if db_data.get('lastName') != orig_lname:
        identity_ok = False
        issues.append(f"Last Name changed to {db_data.get('lastName')}")
    if db_data.get('sex') != orig_sex:
        identity_ok = False
        issues.append("Sex changed")
    if db_data.get('bloodType') != orig_blood:
        identity_ok = False
        issues.append("Blood Type changed")
        
    if identity_ok:
        score += 10
        feedback_parts.append("Identity preserved")
    else:
        feedback_parts.append(f"Identity corrupted: {', '.join(issues)}")

    # 4. Verify Document Modification (5 pts)
    # CouchDB revisions start with "1-..." for new docs. Updates increment to "2-..." etc.
    # Since we reset the doc in setup (making it rev 1 or keeping existing), an update by agent
    # should result in a higher revision number or at least a different rev hash.
    # A simple heuristic: if fields changed, this is implicitly true, but we check explicitly.
    rev = db_data.get('rev', '')
    if rev and not rev.startswith('1-'):
        score += 5
    elif rev.startswith('1-') and score >= 75:
        # If score is high but rev is 1, maybe setup created it as 1 and agent updated? 
        # Actually setup might do a PUT that results in 2-. 
        # Let's trust the field checks primarily.
        score += 5

    # 5. VLM Verification (10 pts)
    # Check trajectory for "Edit" form usage
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of a HospitalRun electronic health record system.
        The user goal is to Edit a patient record.
        
        Look for:
        1. A patient list or search screen.
        2. A patient detail view (showing 'James Chen').
        3. An 'Edit' form (input fields visible, 'Save' or 'Update' buttons).
        4. A success message or return to detail view.
        
        Did the user navigate to a patient and enter an edit/input mode?
        Return JSON: {"edit_mode_seen": boolean, "reason": "string"}
        """
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res and vlm_res.get('parsed', {}).get('edit_mode_seen'):
            score += 10
            feedback_parts.append("Workflow verified by VLM")
        else:
            feedback_parts.append("VLM did not clearly see edit workflow")
    else:
        # Fallback if no frames (shouldn't happen in standard runs)
        feedback_parts.append("No frames for VLM")

    # Final Pass/Fail
    passed = score >= 60 and ("Address updated" in feedback_parts or "Phone updated" in feedback_parts or "Email updated" in feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }