#!/usr/bin/env python3
"""
Verifier for Provision Dashboard Widget Access task.

Criteria:
1. User 'lobby_display' exists (15 pts)
2. User has exactly 'view' permissions on Site 1 (15 pts)
3. User is NOT a superuser (Security check) (10 pts)
4. Output file exists and contains iframe (10 pts)
5. Token extracted from file is functional (20 pts)
6. Token belongs to the restricted user (not an admin token) (30 pts)
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_provision_dashboard_widget_access(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Load result JSON
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/provision_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. User Exists (15 pts)
    if result.get('user_exists'):
        score += 15
        feedback.append("User 'lobby_display' created.")
    else:
        feedback.append("User 'lobby_display' NOT found.")

    # 2. Permissions (15 pts)
    perm = result.get('permission_level')
    if perm == 'view':
        score += 15
        feedback.append("User has correct 'view' permission.")
    elif perm == 'admin':
        feedback.append("SECURITY FAIL: User has 'admin' permission (too permissive).")
    else:
        feedback.append(f"User permission incorrect: {perm}")

    # 3. Not Superuser (10 pts)
    is_super = result.get('is_superuser')
    if not is_super:
        score += 10
        feedback.append("User is correctly NOT a superuser.")
    else:
        feedback.append("SECURITY FAIL: User has Super User access.")

    # 4. File Structure (10 pts)
    if result.get('file_exists') and result.get('widget_iframe_found'):
        score += 10
        feedback.append("Widget HTML file created with iframe.")
    else:
        feedback.append("Widget HTML file missing or invalid structure.")

    # 5. Token Functional (20 pts)
    token_functional = result.get('token_functional')
    if token_functional:
        score += 20
        feedback.append("Token in HTML file is valid and functional.")
    else:
        feedback.append("Token in HTML file is invalid or missing.")

    # 6. Token Ownership (30 pts)
    # Must be 'lobby_display' and definitely NOT 'superuser_token'
    token_user = result.get('token_user_determination')
    if token_user == 'lobby_display':
        score += 30
        feedback.append("Token correctly belongs to 'lobby_display'.")
    elif token_user == 'superuser_token':
        feedback.append("SECURITY FAIL: Token belongs to a Super User/Admin (Anti-gaming).")
    else:
        feedback.append(f"Token ownership verification failed: {token_user}")

    # Final Pass/Fail
    passed = (score >= 70) and token_functional and (token_user == 'lobby_display')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }