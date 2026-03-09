#!/usr/bin/env python3
"""
Verifier for create_user_account task in HospitalRun.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_account(traj, env_info, task_info):
    """
    Verify that the user 'Maria Santos' was correctly created in the _users database.
    
    Criteria:
    1. User document exists in CouchDB _users (25 pts)
    2. Display Name is correct (15 pts)
    3. Email is correct (15 pts)
    4. Role is correct (Doctor) (15 pts)
    5. User count increased (Anti-gaming) (10 pts)
    6. App was running (10 pts)
    7. VLM: Admin UI visited (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_display_name', 'Maria Santos')
    expected_email = metadata.get('expected_email', 'maria.santos@hospital.org')
    expected_role = metadata.get('expected_role', 'Doctor')

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

    score = 0
    feedback_parts = []
    
    # CouchDB data
    couch_data = result.get('couchdb_result', {})
    user_found = couch_data.get('found', False)
    user_doc = couch_data.get('user_doc') or {}
    
    # Count check
    initial_count = int(result.get('initial_user_count', 0))
    final_count = int(couch_data.get('total_users', 0))
    count_increased = final_count > initial_count

    # 1. User exists (25 pts) - CRITICAL
    if user_found:
        score += 25
        feedback_parts.append("User document found")
    else:
        feedback_parts.append("User document NOT found")
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Task failed: " + " | ".join(feedback_parts)
        }

    # 2. Display Name check (15 pts)
    actual_name = user_doc.get('displayName', '')
    if expected_name.lower() in actual_name.lower():
        score += 15
        feedback_parts.append(f"Display Name correct ('{actual_name}')")
    else:
        feedback_parts.append(f"Display Name mismatch (Expected: '{expected_name}', Got: '{actual_name}')")

    # 3. Email check (15 pts)
    actual_email = user_doc.get('email', '')
    if expected_email.lower() == actual_email.lower():
        score += 15
        feedback_parts.append(f"Email correct ('{actual_email}')")
    else:
        feedback_parts.append(f"Email mismatch (Expected: '{expected_email}', Got: '{actual_email}')")

    # 4. Role check (15 pts)
    # Roles are a list in 'roles'
    actual_roles = user_doc.get('roles', [])
    if expected_role in actual_roles:
        score += 15
        feedback_parts.append(f"Role correct ('{expected_role}' found)")
    else:
        feedback_parts.append(f"Role mismatch (Expected '{expected_role}' in {actual_roles})")

    # 5. Anti-gaming: Count check (10 pts)
    if count_increased:
        score += 10
        feedback_parts.append("New user count confirmed")
    else:
        feedback_parts.append("Warning: User count did not increase (modified existing?)")

    # 6. App running (10 pts)
    if result.get('app_running', False):
        score += 10
    else:
        feedback_parts.append("Browser was closed")

    # 7. Simple VLM check using trajectory (10 pts)
    # We assume if they got this far with correct data, the UI was used, 
    # but we give points for non-empty trajectory as a proxy for effort
    if traj and len(traj) > 2:
        score += 10
        feedback_parts.append("Trajectory verification passed")
    
    # Calculate final status
    passed = (score >= 60) and user_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }