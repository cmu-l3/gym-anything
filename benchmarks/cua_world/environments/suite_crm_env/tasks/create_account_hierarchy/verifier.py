#!/usr/bin/env python3
"""
Verifier for create_account_hierarchy task.

VERIFICATION STRATEGY:
1. Database query to verify existence of Parent Account (15 points).
2. Database query to verify existence of Child Accounts (5 points each, 15 total).
3. Database relationship check: verify `parent_id` of each child equals `id` of parent (15 points each, 45 total).
4. Field accuracy: check Industry and Billing City for all 4 accounts (15 points proportional).
5. Anti-gaming: ensure records were created AFTER task_start time (10 points).

Total: 100 points. Pass threshold: 75.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_account_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hierarchy_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get("task_start", 0)
    parent = result.get("parent", {})
    child_h = result.get("healthineers", {})
    child_di = result.get("digital_industries", {})
    child_m = result.get("mobility", {})

    parent_id = parent.get("id", "")

    # 1. Parent Created (15 pts)
    if parent.get("found"):
        score += 15
        feedback_parts.append("Parent account 'Siemens AG' found.")
    else:
        feedback_parts.append("Parent account 'Siemens AG' MISSING.")

    # 2. Children Created (15 pts total, 5 each)
    children_found = 0
    for name, c_data in [("Healthineers", child_h), ("Digital Industries", child_di), ("Mobility", child_m)]:
        if c_data.get("found"):
            score += 5
            children_found += 1
            feedback_parts.append(f"Child account 'Siemens {name}' found.")
        else:
            feedback_parts.append(f"Child account 'Siemens {name}' MISSING.")

    # 3. Relationship Linkage (45 pts total, 15 each)
    linked_count = 0
    if parent.get("found") and parent_id:
        for name, c_data in [("Healthineers", child_h), ("Digital Industries", child_di), ("Mobility", child_m)]:
            if c_data.get("found"):
                if c_data.get("parent_id") == parent_id:
                    score += 15
                    linked_count += 1
                    feedback_parts.append(f"'Siemens {name}' successfully linked to parent.")
                else:
                    feedback_parts.append(f"'Siemens {name}' NOT linked to parent (Member of field incorrect or missing).")

    # 4. Field Accuracy (15 pts)
    # 8 fields total to check (Industry + City for 4 accounts)
    fields_checked = 0
    fields_correct = 0

    expected_fields = [
        (parent, "Manufacturing", "Munich"),
        (child_h, "Healthcare", "Erlangen"),
        (child_di, "Technology", "Nuremberg"),
        (child_m, "Transportation", "Munich")
    ]

    for c_data, exp_ind, exp_city in expected_fields:
        if c_data.get("found"):
            fields_checked += 2
            if c_data.get("industry", "").lower() == exp_ind.lower():
                fields_correct += 1
            if c_data.get("city", "").lower() == exp_city.lower():
                fields_correct += 1

    if fields_checked > 0:
        field_score = int(15 * (fields_correct / fields_checked))
        score += field_score
        feedback_parts.append(f"Field accuracy: {fields_correct}/{fields_checked} correct (+{field_score} pts).")

    # 5. Anti-gaming / Progression (10 pts)
    # Check if all found records were created AFTER the task started
    timestamps = []
    for c_data in [parent, child_h, child_di, child_m]:
        if c_data.get("found"):
            timestamps.append(c_data.get("timestamp", 0))
    
    if len(timestamps) > 0 and all(ts >= task_start for ts in timestamps):
        score += 10
        feedback_parts.append("Timestamps validated (anti-gaming passed).")
    elif len(timestamps) > 0:
        feedback_parts.append("WARNING: Some records were created before the task started.")

    # Determine final pass/fail
    # Must have the parent, at least 2 children linked, and a minimum score of 75
    key_criteria_met = parent.get("found") and linked_count >= 2
    passed = (score >= 75) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }