#!/usr/bin/env python3
"""
Verifier for create_custom_role task.
Verifies that the "External Auditor" role exists and has the correct permissions
as defined in the policy file.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_role(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_perms = set(metadata.get('required_permissions', []))
    forbidden_perms = set(metadata.get('forbidden_permissions', []))
    
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
    feedback = []
    
    # 1. Check Role Existence (20 pts)
    if not result.get('role_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Role 'External Auditor' was not created."
        }
    
    score += 20
    feedback.append("Role 'External Auditor' created.")
    
    # 2. Check Permissions
    # The API returns a list of permission strings
    actual_perms = set(result.get('permissions', []))
    
    # Check Required Permissions
    missing_required = []
    for perm in required_perms:
        if perm in actual_perms:
            score += 10 # 6 required perms * 10 = 60 pts max (capped below)
        else:
            missing_required.append(perm)
            
    if not missing_required:
        feedback.append("All required view permissions present.")
    else:
        feedback.append(f"Missing permissions: {', '.join(missing_required)}")

    # Check Forbidden Permissions
    present_forbidden = []
    for perm in forbidden_perms:
        if perm in actual_perms:
            present_forbidden.append(perm)
        else:
            score += 4 # 5 forbidden perms * 4 = 20 pts (approx)
            
    if not present_forbidden:
        feedback.append("Correctly restricted write access.")
    else:
        feedback.append(f"SECURITY VIOLATION: Found forbidden permissions: {', '.join(present_forbidden)}")
        # Penalty for security violations
        score -= (len(present_forbidden) * 10)

    # Normalize score
    # Structure from design:
    # Role: 20
    # View Issues: 10
    # View Docs: 10
    # View Wiki: 10
    # View Repo: 10
    # No Write Issues: 10
    # No Time: 15
    # No Forum: 15
    # Total: 100
    
    # Recalculate strictly based on design table
    final_score = 20 # Role exists
    
    if 'view_issues' in actual_perms: final_score += 10
    if 'view_documents' in actual_perms: final_score += 10
    if 'view_wiki_pages' in actual_perms: final_score += 10
    if 'view_changesets' in actual_perms and 'browse_repository' in actual_perms: final_score += 10
    
    if 'edit_issues' not in actual_perms and 'add_issues' not in actual_perms: final_score += 10
    if 'log_time' not in actual_perms and 'view_time_entries' not in actual_perms: final_score += 15
    if 'add_messages' not in actual_perms: final_score += 15

    # Cap score at 100 and floor at 0
    final_score = max(0, min(100, final_score))
    
    passed = final_score >= 75
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback)
    }