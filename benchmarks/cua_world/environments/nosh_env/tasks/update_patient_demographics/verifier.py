#!/usr/bin/env python3
"""
Verifier for update_patient_demographics task.

Criteria:
1. Patient record exists.
2. Address, City, Zip, Phone, Email match EXPECTED new values.
3. State matches (should remain CT).
4. Patient Name/DOB preserved (not overwritten).
5. Anti-gaming: Fields actually changed from initial state.
6. VLM: Validates workflow trajectory (search -> edit -> save).
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_patient_demographics(traj, env_info, task_info):
    """
    Verifies that the patient demographics were updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    # 1. Load Expected Data
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {})
    
    # Default fallback values if metadata missing
    exp_address = expected.get('address', "789 Birchwood Drive Apt 3B")
    exp_city = expected.get('city', "New Haven")
    exp_zip = expected.get('zip', "06511")
    exp_phone = expected.get('phone_home', "203-555-0389")
    exp_email = expected.get('email', "eleanor.whitfield@gmail.com")

    # 2. Retrieve Result from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Evaluate Data
    score = 0
    feedback = []
    
    found = result.get('patient_found', False)
    data = result.get('patient_data', {})
    
    if not found:
        return {"passed": False, "score": 0, "feedback": "Patient 'Eleanor Whitfield' not found in database."}

    # Field Checks (15 points each for main fields)
    
    # Address (Fuzzy match for street types like Dr vs Drive)
    act_address = data.get('address', '')
    if exp_address.lower() in act_address.lower() or "789 birchwood" in act_address.lower():
        score += 15
        feedback.append("Address updated")
    else:
        feedback.append(f"Address mismatch: expected '{exp_address}', got '{act_address}'")

    # City (10 pts)
    if data.get('city', '').lower() == exp_city.lower():
        score += 10
        feedback.append("City updated")
    else:
        feedback.append(f"City mismatch: got {data.get('city')}")

    # Zip (10 pts)
    if data.get('zip', '') == exp_zip:
        score += 10
        feedback.append("Zip updated")
    else:
        feedback.append(f"Zip mismatch: got {data.get('zip')}")

    # Phone (15 pts) - clean formatting before compare
    act_phone = ''.join(filter(str.isdigit, data.get('phone', '')))
    exp_phone_clean = ''.join(filter(str.isdigit, exp_phone))
    if exp_phone_clean in act_phone:
        score += 15
        feedback.append("Phone updated")
    else:
        feedback.append(f"Phone mismatch: got {data.get('phone')}")

    # Email (15 pts)
    if data.get('email', '').lower() == exp_email.lower():
        score += 15
        feedback.append("Email updated")
    else:
        feedback.append(f"Email mismatch: got {data.get('email')}")

    # State (5 pts) - Should remain CT
    if data.get('state', '').upper() == 'CT':
        score += 5
        feedback.append("State preserved (CT)")
    
    # Identity Check (10 pts) - Name shouldn't have changed
    if data.get('firstname') == 'Eleanor' and data.get('lastname') == 'Whitfield':
        score += 10
        feedback.append("Identity preserved")
    else:
        feedback.append("WARNING: Name was altered!")

    # Anti-gaming (10 pts)
    # Check if fields were actually modified from initial state
    changed_count = result.get('fields_changed_count', 0)
    if changed_count >= 3:
        score += 10
        feedback.append("DB changes verified")
    else:
        feedback.append("Warning: Few changes detected from initial state")

    # 4. VLM Verification (10 pts)
    # Check if the agent actually used the UI
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        # We look for demographics form or patient search
        prompt = """
        Review these screenshots of an agent using an EHR system.
        1. Did the agent search for a patient or open a patient chart?
        2. Is a demographics or patient details form visible?
        3. Did the agent enter text into address/phone/email fields?
        
        Return JSON: {"workflow_valid": true/false, "confidence": "high/med/low"}
        """
        
        # Only query if we have frames
        if frames:
            vlm_res = query_vlm(frames + [final_img], prompt)
            if vlm_res.get('parsed', {}).get('workflow_valid', False):
                vlm_score = 10
                feedback.append("VLM: Workflow valid")
            else:
                feedback.append("VLM: Workflow unclear")
        else:
            # Fallback if no frames (rare)
            vlm_score = 10 
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        vlm_score = 0
    
    score += vlm_score

    # Final tally
    passed = score >= 60 and changed_count > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }