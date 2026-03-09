#!/usr/bin/env python3
"""
Verifier for configure_group_alias_cnam task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_group_alias_cnam(traj, env_info, task_info):
    """
    Verifies that the Group Alias 'RETENTION_HQ' was created correctly
    and assigned to the 'RETENTION' campaign.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_alias_id = metadata.get('target_alias_id', 'RETENTION_HQ')
    expected_campaign_id = metadata.get('target_campaign_id', 'RETENTION')
    expected_cid_name = metadata.get('expected_cid_name', 'RETENTION SVC')
    expected_cid_number = metadata.get('expected_cid_number', '8005550155')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic error check
    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback = []

    # 1. Verify Alias Existence (20 pts)
    alias_data = result.get('alias_data')
    if result.get('alias_found') and alias_data:
        score += 20
        feedback.append("Group Alias created")
    else:
        feedback.append("Group Alias 'RETENTION_HQ' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Verify Caller ID Number (20 pts)
    actual_number = str(alias_data.get('caller_id_number', '')).strip()
    if actual_number == expected_cid_number:
        score += 20
    else:
        feedback.append(f"Incorrect CID Number (expected {expected_cid_number}, got {actual_number})")

    # 3. Verify Caller ID Name (20 pts) - Exact match required
    actual_name = str(alias_data.get('caller_id_name', '')).strip()
    if actual_name == expected_cid_name:
        score += 20
    else:
        feedback.append(f"Incorrect CID Name (expected '{expected_cid_name}', got '{actual_name}')")

    # 4. Verify Active Status (10 pts)
    actual_active = str(alias_data.get('active', '')).strip()
    if actual_active == 'Y':
        score += 10
    else:
        feedback.append("Alias is not set to Active")

    # 5. Verify Campaign Assignment (30 pts)
    campaign_data = result.get('campaign_data')
    if campaign_data:
        actual_alias_setting = str(campaign_data.get('default_group_alias', '')).strip()
        if actual_alias_setting == expected_alias_id:
            score += 30
            feedback.append("Campaign correctly assigned to Alias")
        else:
            feedback.append(f"Campaign 'RETENTION' not assigned to '{expected_alias_id}' (current: '{actual_alias_setting}')")
    else:
        feedback.append("Campaign 'RETENTION' could not be found to verify assignment")

    # Final Pass Logic
    # Must have alias created + campaign assigned to pass
    key_criteria_met = (result.get('alias_found') and 
                        str(campaign_data.get('default_group_alias', '')) == expected_alias_id)
    
    passed = (score >= 80) and key_criteria_met

    if passed:
        feedback.insert(0, "Task Complete")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }