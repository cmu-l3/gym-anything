#!/usr/bin/env python3
"""
Verifier for set_work_package_hierarchy task.
Checks if the parent-child hierarchy was correctly established in OpenProject.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_work_package_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
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

    # Extract Data
    task_start_time = result.get("task_start_time", 0)
    rails_state = result.get("rails_state", {})
    
    if rails_state.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Internal verification error: {rails_state['error']}"}

    epics = rails_state.get("epics", {})
    children = rails_state.get("children", {})
    
    epic1 = epics.get("epic1")  # Search & Discovery
    epic2 = epics.get("epic2")  # Checkout & Payments

    score = 0
    feedback_lines = []

    # 1. Verify Epics Exist (30 pts)
    # ----------------------------------------------------------------
    epic1_id = None
    if epic1:
        score += 15
        epic1_id = epic1.get("id")
        feedback_lines.append(f"PASS: 'Search & Discovery Epic' exists (+15)")
    else:
        feedback_lines.append(f"FAIL: 'Search & Discovery Epic' not found")

    epic2_id = None
    if epic2:
        score += 15
        epic2_id = epic2.get("id")
        feedback_lines.append(f"PASS: 'Checkout & Payments Epic' exists (+15)")
    else:
        feedback_lines.append(f"FAIL: 'Checkout & Payments Epic' not found")

    # 2. Verify Anti-Gaming (Epics created during task) (10 pts)
    # ----------------------------------------------------------------
    anti_gaming_passed = True
    if epic1:
        created_at = epic1.get("created_at", 0)
        if created_at < task_start_time:
            anti_gaming_passed = False
            feedback_lines.append(f"FAIL: Epic 1 created before task start (Anti-gaming)")
    
    if epic2:
        created_at = epic2.get("created_at", 0)
        if created_at < task_start_time:
            anti_gaming_passed = False
            feedback_lines.append(f"FAIL: Epic 2 created before task start (Anti-gaming)")

    if anti_gaming_passed and (epic1 or epic2):
        score += 10
        feedback_lines.append(f"PASS: Epics created during task session (+10)")
    elif not (epic1 or epic2):
        feedback_lines.append(f"SKIP: Timestamp check skipped (no epics found)")
    else:
        # Score penalty implied by not adding points
        pass

    # 3. Verify Hierarchy Links (60 pts)
    # ----------------------------------------------------------------
    # Format: Key -> (Required Parent ID, Description)
    # We rely on the IDs captured in step 1
    
    # Map for easy checking
    # "child_key": (expected_parent_id, "Description")
    checks = [
        ("product_search", epic1_id, "Implement product search..."),
        ("recommendation", epic1_id, "Implement product recommendation..."),
        ("product_page",   epic1_id, "Design new product page..."),
        ("checkout_bug",   epic2_id, "Fix broken checkout...")
    ]

    for child_key, expected_pid, desc in checks:
        child_info = children.get(child_key)
        
        if not child_info:
            feedback_lines.append(f"FAIL: Child WP '{child_key}' not found in project")
            continue

        actual_pid = child_info.get("parent_id")
        
        if expected_pid is None:
            # Parent doesn't exist, so child can't be correct
            feedback_lines.append(f"FAIL: Parent epic missing for '{desc}'")
        elif actual_pid == expected_pid:
            score += 15
            feedback_lines.append(f"PASS: Correct parent for '{desc}' (+15)")
        else:
            feedback_lines.append(f"FAIL: Wrong parent for '{desc}' (Expected: {expected_pid}, Got: {actual_pid})")

    # Final tally
    passed = score >= 60  # Require substantial completion
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }