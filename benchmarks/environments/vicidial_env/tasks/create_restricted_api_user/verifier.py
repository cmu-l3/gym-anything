#!/usr/bin/env python3
"""
Verifier for create_restricted_api_user task.

Checks that the user 'leadview_api' was created with specific security restrictions.
Critical requirement: 'api_only_user' must be enabled to prevent web login.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_restricted_api_user(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    exp_user = metadata.get('expected_user', 'leadview_api')
    exp_pass = metadata.get('expected_pass', 'SecureView2026!')
    exp_name = metadata.get('expected_name', 'LeadView Dashboard')
    exp_level = str(metadata.get('expected_level', '8'))
    exp_group = metadata.get('expected_group', 'ADMIN')
    
    perms = metadata.get('required_permissions', {})
    req_api_only = perms.get('api_only_user', '1')
    req_view_reports = perms.get('view_reports', '1')
    req_mod_leads = perms.get('modify_leads', '0')
    req_mod_users = perms.get('modify_users', '0')
    req_mod_campaigns = perms.get('modify_campaigns', '0')

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback = []
    
    user_data = result.get('user_data')
    
    # CRITERION 1: User Exists (10 pts)
    if not user_data:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"User '{exp_user}' was not found in the database."
        }
    
    score += 10
    feedback.append(f"User '{exp_user}' created")
    
    # CRITERION 2: Basic Details (10 pts)
    details_ok = True
    if user_data.get('pass') != exp_pass:
        feedback.append(f"Incorrect password (expected {exp_pass})")
        details_ok = False
    if user_data.get('full_name') != exp_name:
        feedback.append(f"Incorrect full name (expected '{exp_name}')")
        details_ok = False
        
    if details_ok:
        score += 10
    
    # CRITERION 3: Level and Group (10 pts)
    config_ok = True
    if str(user_data.get('user_level')) != exp_level:
        feedback.append(f"Incorrect user level (got {user_data.get('user_level')}, expected {exp_level})")
        config_ok = False
    if user_data.get('user_group') != exp_group:
        feedback.append(f"Incorrect user group (got {user_data.get('user_group')}, expected {exp_group})")
        config_ok = False
        
    if config_ok:
        score += 10
        
    # CRITERION 4: API Only User (30 pts) - CRITICAL
    # Vicidial stores '1' or '0' typically, but sometimes 'Y'/'N' depending on version/field.
    # The JSON export script retrieves raw DB values.
    api_val = str(user_data.get('api_only_user', '0'))
    is_api_only = api_val in ['1', 'Y', 'y', 'true']
    
    if is_api_only:
        score += 30
        feedback.append("Security: API Only enabled")
    else:
        feedback.append("SECURITY FAIL: API Only User NOT enabled")
    
    # CRITERION 5: Security Restrictions (30 pts)
    # modify_leads, modify_users, modify_campaigns MUST be 0
    restrictions_score = 0
    
    # Leads
    val_leads = str(user_data.get('modify_leads', '1'))
    if val_leads in ['0', 'N', 'n', 'false']:
        restrictions_score += 10
    else:
        feedback.append("Security Fail: Can modify leads")

    # Users
    val_users = str(user_data.get('modify_users', '1'))
    if val_users in ['0', 'N', 'n', 'false']:
        restrictions_score += 10
    else:
        feedback.append("Security Fail: Can modify users")

    # Campaigns
    val_campaigns = str(user_data.get('modify_campaigns', '1'))
    if val_campaigns in ['0', 'N', 'n', 'false']:
        restrictions_score += 10
    else:
        feedback.append("Security Fail: Can modify campaigns")
        
    score += restrictions_score
    if restrictions_score == 30:
        feedback.append("Security: Modification privileges correctly revoked")
    
    # CRITERION 6: Read Permissions (10 pts)
    val_reports = str(user_data.get('view_reports', '0'))
    if val_reports in ['1', 'Y', 'y', 'true']:
        score += 10
        feedback.append("Permissions: Can view reports")
    else:
        feedback.append("Functional Fail: Cannot view reports")

    # Anti-gaming check: Was it created NOW?
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    if current_count <= initial_count:
        feedback.append("Warning: User count did not increase (modified existing user?)")
        # We don't fail strictly on this if the specific user check passes, 
        # but it suggests they might have edited an existing user instead of creating new.
        # However, setup_task deletes the user, so this shouldn't happen unless setup failed.

    # Final Pass Determination
    # Must have score >= 70 AND Critical API Only setting correct
    passed = (score >= 70) and is_api_only
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }