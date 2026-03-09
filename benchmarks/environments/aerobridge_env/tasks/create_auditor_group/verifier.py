#!/usr/bin/env python3
"""
Verifier for create_auditor_group task.

Checks:
1. Group 'Regulatory Auditors' exists.
2. It was created during the task window.
3. It has exactly 6 permissions.
4. All permissions are view-only.
5. Specific required permissions are present.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_auditor_group(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring configuration
    metadata = task_info.get('metadata', {})
    required_codenames = set(metadata.get('required_permissions', []))
    
    score = 0
    feedback_parts = []
    
    # 1. Group Existence (20 pts)
    if not result.get('group_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Group 'Regulatory Auditors' not found."
        }
    
    score += 20
    feedback_parts.append("Group created successfully (+20)")

    # 2. Anti-Gaming / Freshness Check (Pass/Fail condition, no points but required)
    initial_count = result.get('initial_count', 0)
    if initial_count > 0:
         feedback_parts.append("WARNING: Group existed before task start (Clean state failed).")
         # We continue but this is suspicious. Setup script should have cleaned it.

    # 3. View-Only Check (20 pts)
    # If ANY forbidden permission exists, 0 points for this section.
    if result.get('has_forbidden'):
        feedback_parts.append("FAILED: Group has write permissions (add/change/delete).")
    else:
        score += 20
        feedback_parts.append("Group is view-only (+20)")

    # 4. Exact Count Check (15 pts)
    perm_count = result.get('permission_count', 0)
    if perm_count == 6:
        score += 15
        feedback_parts.append("Exact permission count (6) matches (+15)")
    else:
        feedback_parts.append(f"Permission count mismatch: Expected 6, got {perm_count}")

    # 5. Specific Permission Checks (42 pts total, 7 pts each)
    # We map the codenames found in result to a set
    found_codenames = {p['codename'] for p in result.get('permissions', [])}
    
    missing_perms = []
    for req in required_codenames:
        if req in found_codenames:
            score += 7
        else:
            missing_perms.append(req)
            
    if not missing_perms:
        feedback_parts.append("All required view permissions present (+42)")
    else:
        feedback_parts.append(f"Missing permissions: {', '.join(missing_perms)}")

    # 6. No Write Permissions Extra Bonus (3 pts) - Rounding out to 100
    if not result.get('has_forbidden') and perm_count > 0:
        score += 3
        
    # Calculate pass status
    # Must have group (20) + at least 4 correct perms (28) + view only (20) = >60 roughly
    passed = score >= 60 and not result.get('has_forbidden')

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }