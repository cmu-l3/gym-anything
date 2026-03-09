#!/usr/bin/env python3
"""
Verifier for create_security_role task.
Checks if role and user were created with correct configuration in OrientDB.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_security_role(traj, env_info, task_info):
    """
    Verifies that the agent created the 'data_analyst' role and 'maria_garcia' user correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_role = metadata.get('role_name', 'data_analyst')
    expected_parent = metadata.get('parent_role', 'reader')
    
    # Retrieve result file
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
    feedback = []
    
    # --- Criterion 1: Role Creation (15 pts) ---
    if result.get('role_exists'):
        score += 15
        feedback.append(f"Role '{expected_role}' created.")
    else:
        feedback.append(f"Role '{expected_role}' NOT found.")
        # Critical failure path - if role doesn't exist, hard to pass other checks
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # --- Criterion 2: Inheritance (15 pts) ---
    # Parent might be reported as a list or string depending on export script parsing
    # The export script handles this, but let's be robust
    actual_parent = result.get('role_parent', '')
    if expected_parent.lower() in str(actual_parent).lower():
        score += 15
        feedback.append(f"Inheritance correct ({actual_parent}).")
    else:
        feedback.append(f"Incorrect inheritance. Expected '{expected_parent}', got '{actual_parent}'.")

    # --- Criterion 3: Permissions (20 pts) ---
    # 10 pts for database.class CREATE
    if result.get('perm_database_class_create'):
        score += 10
        feedback.append("Permission 'database.class' (Create) granted.")
    else:
        feedback.append("Permission 'database.class' (Create) missing.")

    # 10 pts for database.cluster CREATE
    if result.get('perm_database_cluster_create'):
        score += 10
        feedback.append("Permission 'database.cluster' (Create) granted.")
    else:
        feedback.append("Permission 'database.cluster' (Create) missing.")

    # --- Criterion 4: User Creation (15 pts) ---
    if result.get('user_exists'):
        score += 15
        feedback.append("User 'maria_garcia' created.")
    else:
        feedback.append("User 'maria_garcia' NOT found.")

    # --- Criterion 5: User Configuration (10 pts) ---
    # Check status and role assignment
    user_status = result.get('user_status', '')
    user_roles = result.get('user_roles', '')
    
    config_ok = True
    if user_status != 'ACTIVE':
        feedback.append(f"User status is '{user_status}', expected 'ACTIVE'.")
        config_ok = False
    
    if expected_role not in user_roles:
        feedback.append(f"User not assigned to role '{expected_role}'. Roles: {user_roles}")
        config_ok = False
        
    if config_ok and result.get('user_exists'):
        score += 10
        feedback.append("User configuration (Status/Role) correct.")

    # --- Criterion 6: Authentication Test (15 pts) ---
    if result.get('auth_success'):
        score += 15
        feedback.append("User authentication successful.")
    else:
        feedback.append("User authentication FAILED (wrong password or permissions?).")

    # --- Criterion 7: Anti-Gaming (10 pts) ---
    if result.get('created_during_task'):
        score += 10
        feedback.append("Changes verified as new.")
    else:
        feedback.append("Warning: Could not verify changes were made during this session.")

    # Final Evaluation
    passed = score >= 60 and result.get('role_exists') and result.get('user_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }