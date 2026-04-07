#!/usr/bin/env python3
"""
Verifier for configure_secure_client_role task.

Verifies:
1. Role "External Reviewer" exists.
2. Role has 'issues_visibility' set to 'own' (Created by or assigned to user).
3. Role has 'time_entries_visibility' set to 'none'.
4. Role has 'users_visibility' set to 'members_of_visible_projects'.
5. Permissions are strictly scoped (View/Add issues/notes/files ONLY).
6. User 'jordan.lee' is a member of 'mobile-banking' with this role.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_secure_client_role(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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
    feedback = []
    
    # 1. Verify Role Existence (10 pts)
    role_found = result.get('role_found', False)
    role_data = result.get('role_data', {})
    
    if role_found:
        score += 10
        feedback.append("Role 'External Reviewer' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Role 'External Reviewer' not found."}

    # 2. Verify Issues Visibility (CRITICAL - 30 pts)
    # Expected: 'own' (which corresponds to "Issues created by or assigned to the user")
    issues_vis = role_data.get('issues_visibility')
    if issues_vis == 'own':
        score += 30
        feedback.append("Issues visibility correctly restricted to 'own'.")
    else:
        feedback.append(f"Incorrect issues visibility: expected 'own', found '{issues_vis}'.")

    # 3. Verify Time/User Visibility (10 pts)
    time_vis = role_data.get('time_entries_visibility')
    users_vis = role_data.get('users_visibility')
    
    if time_vis == 'none':
        score += 5
        feedback.append("Time logs hidden.")
    else:
        feedback.append(f"Time entries visibility incorrect: found '{time_vis}'.")
        
    if users_vis == 'members_of_visible_projects':
        score += 5
        feedback.append("Users visibility correct.")
    else:
        feedback.append(f"Users visibility incorrect: found '{users_vis}'.")

    # 4. Verify Permissions (20 pts total)
    permissions = set(role_data.get('permissions', []))
    required = set(['view_issues', 'add_issues', 'add_notes', 'view_files'])
    forbidden = set(['edit_issues', 'delete_issues', 'view_wiki_pages', 'browse_repository'])

    # Check required
    missing = required - permissions
    if not missing:
        score += 20
        feedback.append("All required permissions present.")
    else:
        score += max(0, 20 - (len(missing) * 5))
        feedback.append(f"Missing permissions: {', '.join(missing)}.")

    # 5. Verify Forbidden Permissions (10 pts)
    # If any forbidden permission is present, deduct points
    found_forbidden = forbidden.intersection(permissions)
    if not found_forbidden:
        score += 10
        feedback.append("Security check passed: No forbidden permissions found.")
    else:
        feedback.append(f"SECURITY FAIL: Found forbidden permissions: {', '.join(found_forbidden)}.")
        # Deduct from total score heavily for security violations if needed, or just don't award these 10 pts.
        # Here we just don't award the 10 points.

    # 6. Verify Member Assignment (20 pts)
    membership_found = result.get('membership_found', False)
    membership_roles = result.get('membership_roles', [])
    
    if membership_found and "External Reviewer" in membership_roles:
        score += 20
        feedback.append("Jordan Lee is correctly assigned to Mobile Banking App with the role.")
    elif membership_found:
        feedback.append(f"Jordan Lee is a member but has wrong roles: {membership_roles}.")
    else:
        feedback.append("Jordan Lee is NOT a member of the project.")

    passed = score >= 80 and issues_vis == 'own'

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }