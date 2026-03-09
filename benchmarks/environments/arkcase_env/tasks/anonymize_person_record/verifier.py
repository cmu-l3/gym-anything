#!/usr/bin/env python3
"""
Verifier for anonymize_person_record task.

Verification Strategy:
1. Validates that the Person record still exists (was not deleted).
2. Checks that First Name is 'Redacted'.
3. Checks that Last Name starts with 'User-' or is 'User-Anonymized'.
4. Checks that Email and Phone fields are empty/null.
5. Uses VLM to confirm UI state in final screenshot.
"""

import json
import tempfile
import os
import logging
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anonymize_person_record(traj, env_info, task_info):
    """
    Verify that the person record has been correctly anonymized.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Load result from container
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

    person_data = result.get('person_data', {})
    api_success = result.get('api_success', False)

    # Criterion 1: Record Identified & Exists (20 pts)
    if not api_success or not person_data.get('exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target person record could not be retrieved. Agent may have deleted the record entirely instead of editing it, or failed to save."
        }
    
    score += 20
    feedback_parts.append("Record exists")

    # Criterion 2: First Name Anonymized (20 pts)
    first_name = person_data.get('firstName', '').strip()
    if first_name.lower() == 'redacted':
        score += 20
        feedback_parts.append("First Name correct")
    else:
        feedback_parts.append(f"First Name mismatch: '{first_name}'")

    # Criterion 3: Last Name Anonymized (20 pts)
    # Accepts "User-Anonymized" or "User-[ID]"
    last_name = person_data.get('lastName', '').strip()
    target_id = result.get('target_person_id', '')
    
    is_user_id = target_id and f"user-{target_id}" in last_name.lower()
    is_generic = "user-anonymized" in last_name.lower() or "user-" in last_name.lower()
    
    if is_user_id or is_generic:
        score += 20
        feedback_parts.append("Last Name anonymized")
    else:
        feedback_parts.append(f"Last Name mismatch: '{last_name}'")

    # Criterion 4: Contact Info Cleared (20 pts total)
    # Email (10 pts)
    email = person_data.get('email')
    if not email or email.strip() == "":
        score += 10
        feedback_parts.append("Email cleared")
    else:
        feedback_parts.append(f"Email present: '{email}'")

    # Phone (10 pts) - checks both business and mobile
    b_phone = person_data.get('businessPhone')
    m_phone = person_data.get('mobilePhone')
    if (not b_phone or b_phone.strip() == "") and (not m_phone or m_phone.strip() == ""):
        score += 10
        feedback_parts.append("Phones cleared")
    else:
        feedback_parts.append(f"Phone present: '{b_phone or m_phone}'")

    # Criterion 5: VLM Visual Verification (20 pts)
    # Check if the agent was actually in the right UI
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        vlm_prompt = """
        Analyze this screenshot of the ArkCase interface.
        1. Is a "Person" or "Contact" details page visible?
        2. Is the name "Redacted" visible anywhere?
        3. Are the Email or Phone fields empty?
        """
        vlm_res = query_vlm(image=final_screenshot, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        # Simple heuristic: if VLM sees "Redacted", give points
        if "Redacted" in vlm_res.get('response', '') or "Redacted" in str(parsed):
            score += 20
            feedback_parts.append("Visual confirmation of 'Redacted'")
        else:
            # If programmatically correct, give partial points for UI effort
            if score >= 60:
                score += 10
                feedback_parts.append("Visual verification inconclusive")
    else:
        feedback_parts.append("No final screenshot")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }