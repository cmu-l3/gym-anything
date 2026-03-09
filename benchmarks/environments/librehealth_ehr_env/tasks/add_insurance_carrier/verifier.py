#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_insurance_carrier(traj, env_info, task_info):
    """
    Verifies that the agent added the insurance carrier correctly.
    
    Scoring:
    - Record created (Name matches): 30 pts
    - Payer ID (CMS ID) matches: 20 pts
    - Address details match: 20 pts
    - Phone matches: 10 pts
    - No data corruption (count check): 10 pts
    - VLM Trajectory (Process Check): 10 pts
    
    Total: 100 pts
    Threshold: 70 pts
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
        
    metadata = task_info.get('metadata', {})
    expected = {
        'name': metadata.get('expected_name', "Cigna Health Spring"),
        'cms_id': metadata.get('expected_cms_id', "62308"),
        'street': metadata.get('expected_street', "500 Great Circle Road"),
        'city': metadata.get('expected_city', "Nashville"),
        'state': metadata.get('expected_state', "TN"),
        'zip': metadata.get('expected_zip', "37228"),
        'phone': metadata.get('expected_phone', "(800) 668-3813")
    }

    # 2. Retrieve Result JSON
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
    feedback = []
    
    # 3. Verify Database Record (Primary Signal)
    record = result_data.get('record', {})
    record_found = result_data.get('record_found', False)
    
    if not record_found:
        feedback.append("Failed: No insurance company record found with name starting 'Cigna Health Spring'.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
    
    # Name Check (30 pts)
    # The SQL query filtered by name, so if we have a record, the name is at least partially correct.
    # We check exact match here.
    actual_name = record.get('name', '').strip()
    if actual_name == expected['name']:
        score += 30
        feedback.append("Success: Company name matches.")
    else:
        # Partial credit if close (SQL matched 'Cigna Health Spring%')
        score += 15
        feedback.append(f"Partial: Name '{actual_name}' matches pattern but not exact expectation.")

    # Payer ID / CMS ID Check (20 pts)
    actual_cms_id = record.get('cms_id', '').strip()
    if actual_cms_id == expected['cms_id']:
        score += 20
        feedback.append("Success: Payer ID (CMS ID) matches.")
    else:
        feedback.append(f"Failed: Payer ID '{actual_cms_id}' does not match expected '{expected['cms_id']}'.")

    # Address Check (20 pts)
    addr_score = 0
    addr_errors = []
    
    if record.get('street', '').strip() == expected['street']: addr_score += 5
    else: addr_errors.append("Street")
    
    if record.get('city', '').strip() == expected['city']: addr_score += 5
    else: addr_errors.append("City")
    
    if record.get('state', '').strip() == expected['state']: addr_score += 5
    else: addr_errors.append("State")
    
    if record.get('zip', '').strip() == expected['zip']: addr_score += 5
    else: addr_errors.append("Zip")
    
    score += addr_score
    if addr_errors:
        feedback.append(f"Address Mismatch in: {', '.join(addr_errors)}.")
    else:
        feedback.append("Success: Address details match.")

    # Phone Check (10 pts)
    # Normalize phone for comparison (strip spaces/parens/dashes)
    def norm_phone(p): return ''.join(filter(str.isdigit, p))
    
    if norm_phone(record.get('phone', '')) == norm_phone(expected['phone']):
        score += 10
        feedback.append("Success: Phone number matches.")
    else:
        feedback.append(f"Failed: Phone '{record.get('phone')}' does not match.")

    # 4. Anti-Gaming / Data Integrity (10 pts)
    stats = result_data.get('stats', {})
    count_diff = stats.get('count_diff', 0)
    
    if count_diff == 1:
        score += 10
        feedback.append("Success: Exact net increase of 1 record in database.")
    elif count_diff > 1:
        score += 5
        feedback.append("Warning: Multiple records created.")
    else:
        feedback.append("Warning: No net increase in records (was an existing one overwritten?).")

    # 5. VLM Trajectory Verification (10 pts)
    # We check if the agent visited the Practice/Insurance settings page
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "Analyze these screenshots of a medical software interface (LibreHealth/OpenEMR). "
            "Did the user navigate to an 'Administration', 'Practice', or 'Insurance Companies' settings page? "
            "Look for lists of insurance carriers or a form to add a new company. "
            "Return JSON: {\"visited_settings\": true/false}"
        )
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_result.get('parsed', {}).get('visited_settings', False):
            score += 10
            feedback.append("VLM: Confirmed navigation to settings.")
        else:
            feedback.append("VLM: Could not confirm navigation to settings page.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails technically but data is correct
        if score >= 70:
            score += 10
            feedback.append("VLM: Skipped (Technical error), awarded points based on data success.")

    # Final Result
    passed = (score >= 70) and (actual_cms_id == expected['cms_id'])
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }