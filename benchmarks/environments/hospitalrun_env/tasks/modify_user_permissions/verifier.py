#!/usr/bin/env python3
"""
Verifier for modify_user_permissions task.

Logic:
1. Verify the user document for 'jmiller' exists in the _users database.
2. Verify the 'roles' list in that document contains 'System Administrator'.
3. Verify the document was modified during the task (rev changed from initial).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modify_user_permissions(traj, env_info, task_info):
    """
    Verifies that the agent added the 'System Administrator' role to user 'jmiller'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    required_role = metadata.get('required_role', 'System Administrator')
    
    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    user_doc = result.get('user_doc', {})
    initial_rev = result.get('initial_rev', '')
    
    feedback_parts = []
    score = 0
    passed = False

    # Criterion 1: User document exists (20 pts)
    if user_doc.get('exists'):
        score += 20
        feedback_parts.append("User record found")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "User record 'jmiller' not found in database. Did you delete it?"
        }

    # Criterion 2: Roles updated (60 pts)
    roles = user_doc.get('roles', [])
    if required_role in roles:
        score += 60
        feedback_parts.append(f"Role '{required_role}' found")
    else:
        feedback_parts.append(f"Role '{required_role}' MISSING. Current roles: {roles}")

    # Criterion 3: Modification verified via Revision Check (20 pts)
    # This ensures the agent actually hit 'Save' and updated the DB, rather than just doing nothing
    # (assuming the role wasn't already there - setup ensures it wasn't)
    current_rev = user_doc.get('current_rev', '')
    if current_rev != initial_rev and current_rev:
        score += 20
        feedback_parts.append("Database record updated successfully")
    elif current_rev == initial_rev:
        feedback_parts.append("Database record was NOT modified (revision matches initial)")
        # If they somehow have the role but didn't modify the doc, it implies setup failure or magic.
        # But realistically, if score is 80 (role found) but rev match, it means setup failed to clear it.
        # However, for the agent's actions to count, we expect a save.
        pass 

    # Final Evaluation
    if score >= 100:
        passed = True
        feedback = "Task completed successfully: User 'jmiller' is now a System Administrator."
    else:
        passed = False
        feedback = "Task failed: " + "; ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }