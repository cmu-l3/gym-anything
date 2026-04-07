#!/usr/bin/env python3
"""
Verifier for anonymize_customer_data_gdpr task.

Uses `copy_from_env` to retrieve DB verification data exported by `export_result.sh`.
Also incorporates a VLM check to confirm the agent used the UI for editing.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anonymize_data(traj, env_info, task_info):
    """Verifies all aspects of the GDPR anonymization task."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_firstname', 'GDPR').lower()
    expected_lname = metadata.get('expected_lastname', 'Anonymized').lower()
    expected_email = metadata.get('expected_email', 'gdpr@anonymized.local').lower()
    expected_phone = metadata.get('expected_phone', '0000000000')

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/gdpr_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    lead = result.get("lead", {})
    contact = result.get("contact", {})
    comments_count = result.get("audit_comment_count", 0)

    # CRITERION 1: Records NOT Deleted (CRITICAL)
    if lead.get("deleted") == "1" or contact.get("deleted") == "1":
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "CRITICAL FAILURE: One or more records were deleted instead of anonymized. Historical analytics data is lost.",
            "subscores": {"not_deleted": 0}
        }
    else:
        score += 10
        feedback_parts.append("Records preserved (not deleted)")

    # CRITERION 2: Contact PII Anonymized (20 points)
    c_fname = contact.get("firstname", "").strip().lower()
    c_lname = contact.get("lastname", "").strip().lower()
    c_email = contact.get("email", "").strip().lower()
    c_phone = contact.get("phone", "").strip()

    if (c_fname == expected_fname and c_lname == expected_lname and 
        c_email == expected_email and c_phone == expected_phone):
        score += 20
        feedback_parts.append("Contact PII correctly anonymized")
    else:
        feedback_parts.append("Contact PII incomplete or incorrect")

    # CRITERION 3: Contact Address Cleared (15 points)
    c_street = contact.get("street", "").strip()
    c_city = contact.get("city", "").strip()
    c_state = contact.get("state", "").strip()
    c_zip = contact.get("zip", "").strip()

    if not c_street and not c_city and not c_state and not c_zip:
        score += 15
        feedback_parts.append("Contact Address cleared")
    else:
        feedback_parts.append("Contact Address was not fully cleared")

    # CRITERION 4: Contact Opt-Outs (10 points)
    if contact.get("emailoptout") == "1" and contact.get("donotcall") == "1":
        score += 10
        feedback_parts.append("Contact Opt-Outs enabled")
    else:
        feedback_parts.append("Contact Opt-Outs missing")

    # CRITERION 5: Lead PII Anonymized (20 points)
    l_fname = lead.get("firstname", "").strip().lower()
    l_lname = lead.get("lastname", "").strip().lower()
    l_email = lead.get("email", "").strip().lower()
    l_phone = lead.get("phone", "").strip()

    if (l_fname == expected_fname and l_lname == expected_lname and 
        l_email == expected_email and l_phone == expected_phone):
        score += 20
        feedback_parts.append("Lead PII correctly anonymized")
    else:
        feedback_parts.append("Lead PII incomplete or incorrect")

    # CRITERION 6: Lead Opt-Outs (10 points)
    if lead.get("emailoptout") == "1" and lead.get("donotcall") == "1":
        score += 10
        feedback_parts.append("Lead Opt-Outs enabled")
    else:
        feedback_parts.append("Lead Opt-Outs missing")

    # CRITERION 7: Audit Comment Added (15 points)
    if comments_count > 0:
        score += 15
        feedback_parts.append("Audit Comment successfully added")
    else:
        feedback_parts.append("Audit Comment missing or incorrect")

    # VLM Trajectory Verification to ensure genuine UI interaction
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "You are auditing a CRM task. Did the agent navigate through the Vtiger CRM UI "
                "to edit Contact or Lead records? Look for signs of interacting with record forms, "
                "lists, or search fields. Respond in JSON: {'used_ui': true/false}"
            )
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp and vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                if not parsed.get('used_ui', False):
                    # Flag suspicious execution if DB passes but UI wasn't used
                    feedback_parts.append("[VLM Warning: Trajectory doesn't show CRM UI usage]")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }