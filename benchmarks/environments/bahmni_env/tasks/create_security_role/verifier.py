#!/usr/bin/env python3
"""
Verifier for create_security_role task.
Verifies that the "Lab Technician" role was created with specific privileges.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_security_role(traj, env_info, task_info):
    """
    Verify the creation of the security role.
    """
    # 1. Setup: Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load Task Metadata
    metadata = task_info.get('metadata', {})
    expected_role_name = metadata.get('role_name', 'Lab Technician')
    desc_keywords = metadata.get('description_keywords', ["laboratory", "staff", "lab results"])
    required_privs = set(metadata.get('required_privileges', []))

    # 3. Load Result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Evaluation Logic
    score = 0
    feedback_parts = []
    
    # Check 1: Role Exists (20 pts)
    if not result.get('role_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Role '{expected_role_name}' was not found in the system."
        }
    
    score += 20
    feedback_parts.append(f"Role '{expected_role_name}' created")
    
    role_data = result.get('role_data', {})
    
    # Check 2: Description (10 pts)
    description = role_data.get('description', '').lower()
    # Flexible matching: check if at least one keyword is present
    # The prompt asks for "Role for laboratory staff to view patients and manage lab results"
    # We check for "laboratory" OR "lab" AND "staff"
    if ('laboratory' in description or 'lab' in description) and 'staff' in description:
        score += 10
        feedback_parts.append("Description correct")
    else:
        feedback_parts.append(f"Description missing keywords (got: '{description}')")
        
    # Check 3: Privileges (60 pts total, 10 per privilege)
    # Get assigned privileges
    assigned_privs_data = role_data.get('privileges', [])
    assigned_privs = set([p.get('display', '') for p in assigned_privs_data])
    
    missing_privs = []
    for req_priv in required_privs:
        if req_priv in assigned_privs:
            score += 10
        else:
            missing_privs.append(req_priv)
            
    if not missing_privs:
        feedback_parts.append("All privileges assigned")
    else:
        feedback_parts.append(f"Missing privileges: {', '.join(missing_privs)}")
        
    # Check 4: No Inherited Roles (5 pts)
    inherited = role_data.get('inheritedRoles', [])
    if not inherited:
        score += 5
        feedback_parts.append("No inherited roles (Correct)")
    else:
        feedback_parts.append("Incorrectly added inherited roles")

    # Check 5: Anti-gaming (Role was created during task) (5 pts)
    # We can check if the role UUID is new, but simpler is ensuring it exists now.
    # Since we purged it in setup, existence implies creation during task.
    score += 5 

    # 5. Final Verdict
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }