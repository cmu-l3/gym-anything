#!/usr/bin/env python3
"""
Verifier for update_arrest_report task.
Verifies that the agent correctly updated the specific database record
while preserving other information.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_arrest_report(traj, env_info, task_info):
    """
    Verify the arrest report update.
    
    Criteria:
    1. The specific arrest report ID must still exist (not deleted).
    2. The 'charges' field must contain 'Grand Larceny'.
    3. The 'charges' field must NOT contain 'Petty Theft' (it should be replaced, not appended).
    4. The 'narrative' field should be preserved (sanity check against wiping the row).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_new = metadata.get('new_charge', 'Grand Larceny').lower()
    forbidden_old = metadata.get('old_charge', 'Petty Theft').lower()
    expected_narrative_part = metadata.get('expected_narrative_snippet', 'Suspect apprehended').lower()

    # Load result
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

    score = 0
    feedback_parts = []
    
    # 1. Check if report exists
    if not result.get('report_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The target arrest report was not found in the database. It may have been deleted."
        }
    
    score += 10
    feedback_parts.append("Report record exists")

    # Get values
    current_charges = result.get('current_charges', '').lower()
    current_narrative = result.get('current_narrative', '').lower()

    # 2. Check for New Charge (40 pts)
    if expected_new in current_charges:
        score += 40
        feedback_parts.append(f"Charge updated to include '{metadata.get('new_charge')}'")
    else:
        feedback_parts.append(f"Expected charge '{metadata.get('new_charge')}' not found")

    # 3. Check for Old Charge Removal (30 pts)
    # The instructions imply an update/correction, not adding a second charge.
    if forbidden_old not in current_charges:
        score += 30
        feedback_parts.append(f"Old charge '{metadata.get('old_charge')}' removed")
    else:
        # If they appended instead of replacing, they lose these points
        feedback_parts.append(f"Old charge '{metadata.get('old_charge')}' still present (should be replaced)")

    # 4. Check Narrative Preservation (20 pts)
    # This prevents the agent from deleting and recreating the report with empty fields
    if expected_narrative_part in current_narrative:
        score += 20
        feedback_parts.append("Narrative preserved")
    else:
        feedback_parts.append("Narrative data missing or corrupted")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }