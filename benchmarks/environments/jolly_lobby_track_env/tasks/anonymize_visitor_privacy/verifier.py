#!/usr/bin/env python3
"""
Verifier for anonymize_visitor_privacy task.

Verification Strategy:
1. File Analysis: Check if the database file was modified and contains the "Redacted" and "Privacy Request" strings.
2. VLM Verification: Use trajectory and final screenshot to verify:
   - The user registered "Marcus Vane" (workflow check).
   - The user edited the record to "Redacted Visitor".
   - The contact fields were cleared (empty).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anonymize_visitor_privacy(traj, env_info, task_info):
    """
    Verify the privacy anonymization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
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
    
    # 2. Check File/Database Evidence (40 points)
    db_modified = result.get('db_modified', False)
    strings_check = result.get('strings_check', {})
    has_redacted = strings_check.get('has_redacted', False)
    has_privacy = strings_check.get('has_privacy_request', False)

    if db_modified:
        score += 10
        feedback_parts.append("Database modified during task")
    else:
        feedback_parts.append("Database NOT modified (no save detected)")

    if has_redacted:
        score += 15
        feedback_parts.append("Found 'Redacted' record in DB")
    else:
        feedback_parts.append("Did not find 'Redacted' string in DB")

    if has_privacy:
        score += 15
        feedback_parts.append("Found 'Privacy Request' company in DB")
    
    # 3. VLM Verification of Workflow & Details (60 points)
    # We use VLM to verify the clearing of fields and the specific values
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if not final_shot:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification"}
    
    vlm_prompt = """
    You are verifying a 'Right to Erasure' privacy task in visitor management software.
    
    Goal:
    1. Register visitor 'Marcus Vane'.
    2. Edit the record to change Name to 'Redacted Visitor' and Company to 'Privacy Request'.
    3. CLEAR/DELETE the Phone and Email fields (they must be empty).
    
    Review the images (trajectory and final state):
    1. Do you see evidence of a record being edited or created?
    2. In the final state or last valid frame, is the name shown as 'Redacted Visitor'?
    3. Is the Company 'Privacy Request'?
    4. Are the Phone and Email fields EMPTY/BLANK? (Crucial: They should NOT contain '555-0199' or 'm.vane@nexus.com')
    
    Return JSON:
    {
        "name_anonymized": boolean,
        "company_anonymized": boolean,
        "phone_cleared": boolean,
        "email_cleared": boolean,
        "record_visible_in_list": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('name_anonymized'):
            score += 20
            feedback_parts.append("VLM: Name correctly anonymized")
        else:
            feedback_parts.append("VLM: Name not anonymized")

        if parsed.get('company_anonymized'):
            score += 10
            feedback_parts.append("VLM: Company correctly anonymized")
            
        if parsed.get('phone_cleared') and parsed.get('email_cleared'):
            score += 20
            feedback_parts.append("VLM: Contact fields cleared")
        elif parsed.get('phone_cleared') or parsed.get('email_cleared'):
            score += 10
            feedback_parts.append("VLM: Contact fields partially cleared")
        else:
            feedback_parts.append("VLM: Contact fields NOT cleared")
            
        if parsed.get('record_visible_in_list'):
            score += 10
            feedback_parts.append("VLM: Anonymized record visible in list")
            
    else:
        feedback_parts.append("VLM verification failed")

    # Pass logic: Must have modified DB, found strings, and VLM confirms name change + fields cleared
    # Threshold: 75 points
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }