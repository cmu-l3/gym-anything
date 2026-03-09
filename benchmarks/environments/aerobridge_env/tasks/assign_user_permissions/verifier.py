#!/usr/bin/env python3
"""
Verifier for assign_user_permissions task.

Checks that the user 'coordinator' has exactly the specified permissions.
Anti-gaming checks included for superuser status and group assignment.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_permissions(traj, env_info, task_info):
    """
    Verify permissions for 'coordinator' user.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Expected Permissions
    # ----------------------------
    # We define the expected set based on the task description
    expected_perms = set([
        "registry.view_aircraft",
        "registry.add_flightplan",
        "registry.change_flightplan",
        "registry.view_flightplan",
        "registry.add_flightoperation",
        "registry.change_flightoperation",
        "registry.view_flightoperation",
        "registry.view_person"
    ])
    
    # 2. Get Agent Result from Container
    # ----------------------------------
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

    # 3. Evaluate Criteria
    # --------------------
    score = 0
    feedback_parts = []
    
    # Basic Checks
    if not result.get("user_exists"):
        return {"passed": False, "score": 0, "feedback": "User 'coordinator' not found in database."}

    # Anti-Gaming: Superuser Check (Immediate Fail if True)
    if result.get("is_superuser"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "CRITICAL FAIL: User was made a superuser. This bypasses permission configuration."
        }
    else:
        score += 10
        feedback_parts.append("✓ User is not a superuser (+10)")

    # Anti-Gaming: Group Check
    group_count = result.get("group_count", 0)
    if group_count > 0:
        feedback_parts.append(f"✗ User assigned to {group_count} groups. Task required direct permissions only.")
    else:
        score += 10
        feedback_parts.append("✓ User not assigned to any groups (+10)")

    # Permission Analysis
    assigned_perms = set(result.get("permissions", []))
    
    # Check for missing permissions
    missing = expected_perms - assigned_perms
    # Check for extra permissions
    extra = assigned_perms - expected_perms
    
    # Scoring specific permissions (Total 70 pts available here)
    # 8 permissions total. Let's allocate roughly 8.75 points each.
    # We'll stick to the scoring table in design:
    # View Aircraft: 10
    # Flight Plan (3): 25
    # Flight Op (3): 25
    # View Person: 10
    
    # View Aircraft
    if "registry.view_aircraft" in assigned_perms:
        score += 10
        feedback_parts.append("✓ 'Can view aircraft' assigned (+10)")
    else:
        feedback_parts.append("✗ Missing 'Can view aircraft'")
        
    # Flight Plan
    fp_score = 0
    if "registry.add_flightplan" in assigned_perms: fp_score += 8
    if "registry.change_flightplan" in assigned_perms: fp_score += 9
    if "registry.view_flightplan" in assigned_perms: fp_score += 8
    score += fp_score
    if fp_score == 25:
        feedback_parts.append("✓ All Flight Plan permissions assigned (+25)")
    else:
        feedback_parts.append(f"⚠ Partial Flight Plan permissions (+{fp_score}/25)")
        
    # Flight Operation
    fo_score = 0
    if "registry.add_flightoperation" in assigned_perms: fo_score += 8
    if "registry.change_flightoperation" in assigned_perms: fo_score += 9
    if "registry.view_flightoperation" in assigned_perms: fo_score += 8
    score += fo_score
    if fo_score == 25:
        feedback_parts.append("✓ All Flight Operation permissions assigned (+25)")
    else:
        feedback_parts.append(f"⚠ Partial Flight Operation permissions (+{fo_score}/25)")

    # View Person
    if "registry.view_person" in assigned_perms:
        score += 10
        feedback_parts.append("✓ 'Can view person' assigned (+10)")
    else:
        feedback_parts.append("✗ Missing 'Can view person'")

    # Penalty for Extra Permissions (Precision check)
    if len(extra) > 0:
        feedback_parts.append(f"✗ Found {len(extra)} incorrect extra permissions (e.g., {list(extra)[0]}). Precision required.")
        # Cap the penalty so we don't go below 0 for this section
        score = max(score - (len(extra) * 5), 0)
    else:
        score += 10
        feedback_parts.append("✓ Exact permission set match (no extras) (+10)")

    # 4. Final Verification Logic
    # ---------------------------
    # Pass threshold: 70 points AND core permissions present
    # Core means not superuser and at least some permissions assigned correctly
    passed = score >= 70 and not result.get("is_superuser")
    
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal Score: {score}/100"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }