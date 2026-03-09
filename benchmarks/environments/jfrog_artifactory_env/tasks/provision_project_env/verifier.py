#!/usr/bin/env python3
"""
Verifier for provision_project_env task.

Verifies:
1. Repository 'alpha-local' exists.
2. Group 'alpha-team' exists.
3. User 'alpha-lead' exists and is in 'alpha-team'.
4. User can Upload (HTTP 201) -> Proves Auth + Write permission.
5. User cannot Delete (HTTP 403) -> Proves Delete permission denied (Security requirement).
6. Permission Target links Repo and Group correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_provision_project_env(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback = []

    # 2. Verify Repository (15 pts)
    if result.get('repo_exists'):
        score += 15
        feedback.append("Repository 'alpha-local' created.")
    else:
        feedback.append("Repository 'alpha-local' NOT found.")

    # 3. Verify Group (15 pts)
    if result.get('group_exists'):
        score += 15
        feedback.append("Group 'alpha-team' created.")
    else:
        feedback.append("Group 'alpha-team' NOT found.")

    # 4. Verify User & Membership (35 pts)
    # Checked via:
    # A. User in Group list (15 pts)
    # B. User can Authenticate & Upload (20 pts)
    if result.get('user_in_group'):
        score += 15
        feedback.append("User 'alpha-lead' is correctly in group 'alpha-team'.")
    else:
        feedback.append("User 'alpha-lead' is NOT in group 'alpha-team'.")

    upload_code = result.get('upload_http_code')
    if upload_code in [201, 200]:
        score += 20
        feedback.append("User authentication and Deploy permission verified (Upload succeeded).")
    elif upload_code == 401:
        feedback.append("User authentication failed (Wrong password or user missing).")
    elif upload_code == 403:
        feedback.append("User exists but lacks Deploy permission.")
    else:
        feedback.append(f"Upload test failed with code {upload_code}.")

    # 5. Verify Security/Permissions (35 pts)
    # A. Permission Target Exists (10 pts)
    perm_data = result.get('perm_data', {})
    if result.get('perm_exists'):
        score += 10
        feedback.append("Permission Target 'alpha-access' created.")
        
        # B. Verify Links (Repo + Group) (10 pts)
        repos = perm_data.get('repositories', [])
        # Check principals: structured as {'groups': {'alpha-team': ['r','w'...]}} or similar
        principals = perm_data.get('principals', {})
        groups = principals.get('groups', {})
        
        links_ok = 'alpha-local' in repos and 'alpha-team' in groups
        if links_ok:
            score += 10
            feedback.append("Permission correctly links 'alpha-local' and 'alpha-team'.")
        else:
            feedback.append("Permission Target does not correctly link the repository and group.")

        # C. Verify Specific Access Controls (15 pts)
        # We rely on the FUNCTIONAL test for Delete (HTTP 403 expected)
        # and checking the actions list for Delete
        
        # Functional Delete Check
        delete_code = result.get('delete_http_code')
        delete_denied_functionally = (delete_code == 403)
        
        # API Check (if available)
        # Typically returns list like ["r","w","n"]
        # 'd' is delete, 'm' is manage
        assigned_perms = groups.get('alpha-team', [])
        
        has_forbidden = 'd' in assigned_perms or 'm' in assigned_perms
        
        if delete_denied_functionally and not has_forbidden:
            score += 15
            feedback.append("Security Policy Enforced: Delete/Admin permissions correctly withheld.")
        else:
            feedback.append(f"Security Policy Failed: User could delete (Code {delete_code}) or has 'd'/'m' permissions.")

    else:
        feedback.append("Permission Target 'alpha-access' NOT found.")

    # Final tally
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }