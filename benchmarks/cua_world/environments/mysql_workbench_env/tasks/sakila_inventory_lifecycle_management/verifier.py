#!/usr/bin/env python3
"""
Verifier for sakila_inventory_lifecycle_management task.
Verifies schema changes, business logic enforcement (via procedures/triggers), and data exports.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_sakila_inventory_lifecycle_management(traj, env_info, task_info):
    """
    Scoring Criteria:
    1. Schema: `status` column exists with correct ENUM type (20 pts)
    2. Procedure: `sp_set_inventory_status` exists (10 pts)
    3. Procedure Logic: Fails when updating rented item (20 pts)
    4. Trigger: `trg_prevent_renting_unavailable` exists (10 pts)
    5. Trigger Logic: Blocks renting 'Damaged' item (30 pts)
    6. Data Export: CSV exists with correct items (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    db_res = result.get('db_verification', {})
    score = 0
    feedback = []

    # 1. Schema Check (20 pts)
    if db_res.get('schema_status_col_exists'):
        if db_res.get('schema_status_type_correct'):
            score += 20
            feedback.append("Schema: Status column added with correct ENUM type.")
        else:
            score += 10
            feedback.append("Schema: Status column added but type mismatch (ENUM expected).")
    else:
        feedback.append("Schema: Status column missing from inventory table.")

    # 2. Procedure Existence (10 pts)
    if db_res.get('proc_exists'):
        score += 10
        feedback.append("Procedure: sp_set_inventory_status exists.")
    else:
        feedback.append("Procedure: sp_set_inventory_status NOT found.")

    # 3. Procedure Logic (20 pts)
    if db_res.get('proc_logic_enforced'):
        score += 20
        feedback.append("Logic: Procedure correctly blocked update on rented item.")
    else:
        feedback.append("Logic: Procedure allowed update on rented item (Security FAIL).")

    # 4. Trigger Existence (10 pts)
    if db_res.get('trigger_exists'):
        score += 10
        feedback.append("Trigger: trg_prevent_renting_unavailable exists.")
    else:
        feedback.append("Trigger: trg_prevent_renting_unavailable NOT found.")

    # 5. Trigger Logic (30 pts)
    # This is the most important part - active prevention of bad data
    if db_res.get('trigger_logic_enforced'):
        score += 30
        feedback.append("Logic: Trigger correctly blocked renting a damaged item.")
    elif db_res.get('data_item_10_status') != 'Damaged':
        feedback.append("Logic: Cannot verify trigger because Item 10 was not marked Damaged.")
    else:
        feedback.append("Logic: Trigger FAILED to block renting a damaged item.")

    # Data check (implicit in logic check, but let's verify specific items)
    if db_res.get('data_item_10_status') == 'Damaged' and db_res.get('data_item_11_status') == 'Lost':
        feedback.append("Data: Items 10 and 11 updated correctly.")
    else:
        feedback.append(f"Data: Items 10/11 status incorrect ({db_res.get('data_item_10_status')}, {db_res.get('data_item_11_status')}).")

    # 6. CSV Export (10 pts)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)
    task_start = result.get('task_start', 0)
    csv_mtime = result.get('csv_mtime', 0)

    if csv_exists and csv_rows >= 2 and int(csv_mtime) > task_start:
        score += 10
        feedback.append("Export: CSV file created with data.")
    else:
        feedback.append("Export: CSV file missing, empty, or stale.")

    passed = score >= 60 and db_res.get('trigger_logic_enforced', False) and db_res.get('proc_logic_enforced', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }