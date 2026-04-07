#!/usr/bin/env python3
"""
Verifier for create_restricted_auditor_role task.

Checks:
1. Role 'External Auditor' exists.
2. Role has required permissions (view_project, view_work_packages, add_notes, etc.).
3. Role does NOT have forbidden permissions (edit_work_packages, log_time).
4. User 'carol.williams' is assigned 'External Auditor'.
5. User 'carol.williams' is NOT assigned 'Developer'.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_restricted_auditor_role(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    rails_data = result.get("rails_data", {})
    metadata = task_info.get("metadata", {})

    score = 0
    feedback_parts = []
    
    # 1. Check Role Existence (20 pts)
    if rails_data.get("role_exists"):
        score += 20
        feedback_parts.append("Role 'External Auditor' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Role 'External Auditor' was not found."}

    # 2. Check Permissions
    actual_perms = set(rails_data.get("role_permissions", []))
    
    # Required permissions
    required = metadata.get("required_permissions", [])
    # Map task description friendly names to internal symbols usually used by OpenProject
    # Note: Export script dumps them as strings.
    # Common mappings:
    # 'View project' -> 'view_project'
    # 'View work packages' -> 'view_work_packages'
    # 'Add notes' -> 'add_work_package_notes'
    # 'View time entries' -> 'view_time_entries'
    # 'View wiki' -> 'view_wiki_pages'
    
    req_met_count = 0
    for req in required:
        if req in actual_perms:
            req_met_count += 1
    
    # Scale score for required permissions (30 pts total)
    if required:
        score += int(30 * (req_met_count / len(required)))
    
    if req_met_count == len(required):
        feedback_parts.append("All required permissions enabled.")
    else:
        feedback_parts.append(f"Missing {len(required) - req_met_count} required permissions.")

    # 3. Check Forbidden Permissions (CRITICAL - 20 pts)
    forbidden = metadata.get("forbidden_permissions", [])
    forbidden_found = []
    for forb in forbidden:
        if forb in actual_perms:
            forbidden_found.append(forb)
            
    if not forbidden_found:
        score += 20
        feedback_parts.append("Security check passed: No forbidden permissions found.")
    else:
        feedback_parts.append(f"SECURITY FAIL: Found forbidden permissions: {', '.join(forbidden_found)}")
        # Penalty: If forbidden permissions exist, cap score or reduce significantly
        score = min(score, 40) 

    # 4. Check User Assignment (30 pts)
    user_roles = rails_data.get("user_roles", [])
    
    # Should have "External Auditor"
    if "External Auditor" in user_roles:
        score += 20
        feedback_parts.append("User assigned 'External Auditor' role.")
    else:
        feedback_parts.append("User NOT assigned 'External Auditor' role.")

    # Should NOT have "Developer"
    if "Developer" not in user_roles:
        score += 10
        feedback_parts.append("Old 'Developer' role removed.")
    else:
        feedback_parts.append("User still has 'Developer' role (access not restricted).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }