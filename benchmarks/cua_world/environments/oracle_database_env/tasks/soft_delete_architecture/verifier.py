#!/usr/bin/env python3
"""
Verifier for Soft Delete Architecture task.

Criteria:
1. Base table structure (renamed + new columns)
2. View structure (filters active, hides audit columns)
3. Trigger existence and logic
4. Agent's manual test (Policy 1005 soft deleted)
5. Verifier's functional test (Policy 1010 soft deleted via view)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_soft_delete_architecture(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/soft_delete_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Base Table Structure (15 pts)
    # Check if INSURANCE_POLICIES_BASE exists and has new columns
    base_exists = result.get("base_table_exists", False)
    cols = result.get("base_table_columns", [])
    col_names = [c["name"] for c in cols]
    
    audit_cols_present = all(c in col_names for c in ["IS_ACTIVE", "DELETED_AT", "DELETED_BY"])
    
    if base_exists and audit_cols_present:
        score += 15
        feedback_parts.append("Base table structure correct (+15)")
    elif base_exists:
        score += 5
        feedback_parts.append("Base table renamed but missing audit columns (+5)")
    else:
        feedback_parts.append("Base table INSURANCE_POLICIES_BASE not found (0)")

    # 2. View Creation and Structure (25 pts)
    view_exists = result.get("view_exists", False)
    view_valid = result.get("view_is_valid", False)
    view_col_count = result.get("view_column_count", 0)
    
    # Original table had 5 columns. View should have 5. Base table has 8.
    if view_exists and view_valid:
        score += 15
        feedback_parts.append("View created and valid (+15)")
        
        if view_col_count == 5:
            score += 10
            feedback_parts.append("View correctly hides audit columns (+10)")
        else:
            feedback_parts.append(f"View exposes {view_col_count} columns (expected 5) (0)")
    else:
        feedback_parts.append("View INSURANCE_POLICIES not found or invalid (0)")

    # 3. Trigger Existence (15 pts)
    trigger_exists = result.get("trigger_exists", False)
    trigger_status = result.get("trigger_status", "UNKNOWN")
    
    if trigger_exists and trigger_status == "VALID":
        score += 15
        feedback_parts.append("INSTEAD OF DELETE trigger exists (+15)")
    elif trigger_exists:
        score += 5
        feedback_parts.append("Trigger exists but is invalid/disabled (+5)")
    else:
        feedback_parts.append("Trigger not found (0)")

    # 4. Agent's Manual Test (Policy 1005) (25 pts)
    # IS_ACTIVE should be 'N', DELETED_BY should be populated
    p1005_status = result.get("policy_1005_status", "UNKNOWN")
    p1005_user = result.get("policy_1005_deleted_by")
    
    if p1005_status == 'N':
        score += 15
        feedback_parts.append("Policy 1005 soft-deleted correctly (IS_ACTIVE='N') (+15)")
        if p1005_user:
            score += 10
            feedback_parts.append(f"Audit trail recorded (Deleted by: {p1005_user}) (+10)")
        else:
            feedback_parts.append("Audit trail missing DELETED_BY (0)")
    elif p1005_status == "MISSING":
        feedback_parts.append("Policy 1005 was physically deleted (Failed soft delete) (0)")
    else:
        feedback_parts.append(f"Policy 1005 status is '{p1005_status}' (expected 'N') (0)")

    # 5. Functional Test (Policy 1010) (20 pts)
    # The verification script attempted to delete 1010 via the view.
    func_passed = result.get("functional_test_passed", False)
    func_details = result.get("functional_test_details", "")
    
    if func_passed:
        score += 20
        feedback_parts.append("Functional verification test passed (+20)")
    else:
        feedback_parts.append(f"Functional verification failed: {func_details} (0)")

    # Final check
    passed = (score >= 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }