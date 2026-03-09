#!/usr/bin/env python3
"""
Verifier for configure_campaign_crm_integration task.

Checks if the Vicidial campaign 'SALESTEAM' has the correct Web Form URL,
Web Form Target, and Dispo Call URL configured in the database.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_campaign_crm_integration(traj, env_info, task_info):
    """
    Verify the campaign CRM integration settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_web_form = metadata.get('expected_web_form_address', "")
    expected_target = metadata.get('expected_web_form_target', "_blank")
    expected_dispo_url = metadata.get('expected_dispo_call_url', "")

    # Retrieve result file
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

    # Extract actual values
    actual_web_form = result.get('web_form_address', "")
    actual_target = result.get('web_form_target', "")
    actual_dispo_url = result.get('dispo_call_url', "")

    score = 0
    feedback_parts = []
    
    # 1. Verify Web Form URL (35 points)
    # We verify exact match because syntax matters
    if actual_web_form.strip() == expected_web_form.strip():
        score += 35
        feedback_parts.append("Web Form URL is correct.")
    else:
        feedback_parts.append(f"Web Form URL incorrect. Expected '{expected_web_form}', got '{actual_web_form}'.")

    # 2. Verify Web Form Target (15 points)
    if actual_target.strip() == expected_target.strip():
        score += 15
        feedback_parts.append("Web Form Target is correct.")
    else:
        feedback_parts.append(f"Web Form Target incorrect. Expected '{expected_target}', got '{actual_target}'.")

    # 3. Verify Dispo Call URL (40 points)
    if actual_dispo_url.strip() == expected_dispo_url.strip():
        score += 40
        feedback_parts.append("Dispo Call URL is correct.")
    else:
        feedback_parts.append(f"Dispo Call URL incorrect. Expected '{expected_dispo_url}', got '{actual_dispo_url}'.")

    # 4. Basic sanity check - changes persisted (10 points)
    # If any field is non-empty and different from default, give points for effort/persistence
    # Setup script clears these, so any non-empty value means *something* was done
    something_changed = (actual_web_form != "") or (actual_dispo_url != "") or (actual_target != "_top")
    if something_changed:
        score += 10
    else:
        feedback_parts.append("No changes detected in database.")

    # Determine pass/fail
    # Threshold: 75. Must get strictly correct URLs to pass effectively.
    # Allowing minor partial credit via scoring, but pass requires correctness.
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }