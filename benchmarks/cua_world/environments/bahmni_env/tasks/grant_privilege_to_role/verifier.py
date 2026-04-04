#!/usr/bin/env python3
"""
Verifier for grant_privilege_to_role task.

Verification Logic:
1. Validates that the "Midwife" role exists in OpenMRS.
2. Checks that the "Add Patients" privilege is present in the role's privilege list.
3. Ensures the agent didn't accidentally change the role name or description (integrity).
4. Verifies the user actually interacted with the UI (via VLM/app state).
"""

import json
import logging
import os
import tempfile
import sys
from typing import Dict, Any

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_grant_privilege_to_role(traj, env_info, task_info):
    """
    Verify the 'Add Patients' privilege was granted to 'Midwife' role.
    """
    # 1. Setup: Get file access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 2. Load Metadata
    metadata = task_info.get('metadata', {})
    target_role = metadata.get('target_role', 'Midwife')
    target_privilege = metadata.get('target_privilege', 'Add Patients')
    
    # 3. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task results. Did the export script run?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Analyze Results
    role_data = result.get('role_data', {})
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Role Existence (20 pts)
    # If role_data has a uuid, the role exists
    role_uuid = role_data.get('uuid')
    role_name = role_data.get('name', '')
    
    if role_uuid and role_name == target_role:
        score += 20
        feedback_parts.append(f"Role '{target_role}' exists")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Role '{target_role}' was not found or was deleted.",
            "details": {"role_found": False}
        }

    # Criterion 2: Privilege Check (60 pts)
    # OpenMRS returns privileges as a list of objects: [{"name": "Add Patients", ...}, ...]
    privileges_list = role_data.get('privileges', [])
    privilege_names = [p.get('name') for p in privileges_list if isinstance(p, dict)]
    
    if target_privilege in privilege_names:
        score += 60
        feedback_parts.append(f"Privilege '{target_privilege}' successfully added")
    else:
        feedback_parts.append(f"Privilege '{target_privilege}' NOT found in role")
        logger.info(f"Found privileges: {privilege_names}")

    # Criterion 3: Integrity Check (10 pts)
    # Check if description is preserved (indicates they edited, didn't delete/recreate wrongly)
    description = role_data.get('description', '')
    if "Midwifery staff" in description:
        score += 10
        feedback_parts.append("Role description preserved")
    else:
        feedback_parts.append("Warning: Role description was modified")

    # Criterion 4: App State (10 pts)
    if result.get('app_was_running', False):
        score += 10
    else:
        feedback_parts.append("Browser was closed prematurely")

    # Final Evaluation
    passed = (target_privilege in privilege_names)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "role_exists": True,
            "privilege_found": passed,
            "privileges_count": len(privilege_names)
        }
    }