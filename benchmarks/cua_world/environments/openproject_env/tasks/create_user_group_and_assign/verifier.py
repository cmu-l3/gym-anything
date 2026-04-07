#!/usr/bin/env python3
"""
Verifier for create_user_group_and_assign task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_user_group_and_assign(traj, env_info, task_info):
    """
    Verifies that the user group 'QA Team' was created, members added,
    and assigned to the project.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Metadata expectations
    metadata = task_info.get("metadata", {})
    expected_members = set(metadata.get("expected_members", ["alice.johnson", "bob.smith"]))
    excluded_members = set(metadata.get("excluded_members", ["carol.williams"]))
    expected_role = metadata.get("target_role", "Developer").lower()

    # Extract result data
    group_found = result.get("group_found", False)
    group_created_at = result.get("group_created_at", 0)
    task_start_time = result.get("task_start_time", 0)
    member_logins = set(result.get("member_logins", []))
    project_member = result.get("project_member", False)
    role_names = [r.lower() for r in result.get("role_names", [])]

    # ---- Criterion 1: Group exists (20 pts) ----
    if group_found:
        score += 20
        feedback_parts.append("✓ Group 'QA Team' exists (20 pts)")
    else:
        feedback_parts.append("✗ Group 'QA Team' not found (0/20 pts)")
        # Critical failure
        return {
            "passed": False,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }

    # ---- Criterion 2: Members Correctness (40 pts total) ----
    # Check expected members
    missing_members = expected_members - member_logins
    if not missing_members:
        score += 30
        feedback_parts.append(f"✓ All expected members found: {', '.join(expected_members)} (30 pts)")
    else:
        # Partial credit? No, simplicity first.
        feedback_parts.append(f"✗ Missing members in group: {', '.join(missing_members)} (0/30 pts)")
        
    # Check excluded members
    found_excluded = excluded_members.intersection(member_logins)
    if not found_excluded:
        score += 10
        feedback_parts.append(f"✓ No excluded members found (10 pts)")
    else:
        feedback_parts.append(f"✗ Incorrectly added members: {', '.join(found_excluded)} (0/10 pts)")

    # ---- Criterion 3: Project Assignment (20 pts) ----
    if project_member:
        score += 20
        feedback_parts.append("✓ Group assigned to 'Mobile Banking App' project (20 pts)")
    else:
        feedback_parts.append("✗ Group NOT assigned to 'Mobile Banking App' project (0/20 pts)")

    # ---- Criterion 4: Role Assignment (15 pts) ----
    if any(r == expected_role or r == "member" for r in role_names):
        score += 15
        feedback_parts.append(f"✓ Correct role assigned: {role_names} (15 pts)")
    elif project_member:
        feedback_parts.append(f"✗ Wrong role assigned. Expected '{expected_role}', got {role_names} (0/15 pts)")
    else:
        feedback_parts.append("✗ No role verified (group not in project)")

    # ---- Criterion 5: Timestamp Anti-Gaming (5 pts) ----
    # Ensure the group was created AFTER the task started
    if task_start_time > 0 and group_created_at >= task_start_time:
        score += 5
        feedback_parts.append("✓ Group created during task session (5 pts)")
    elif task_start_time == 0:
        score += 5
        feedback_parts.append("△ Timestamp verification skipped (no start time), awarding points (5 pts)")
    else:
        feedback_parts.append(f"✗ Group creation time {group_created_at} is before task start {task_start_time} (0/5 pts)")

    # Final logic
    passed = score >= 65 and group_found and project_member
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }