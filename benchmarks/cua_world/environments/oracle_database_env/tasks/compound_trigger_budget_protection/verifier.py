#!/usr/bin/env python3
"""
Verifier for Compound Trigger Budget Protection task.

Evaluates the results from the in-container functional tests.
Scoring Breakdown (100 pts):
- Table DEPT_SPENDING_CAPS exists (10 pts)
- Data in table is correct (Sum * 1.2) (15 pts)
- Trigger exists and is enabled (10 pts)
- Blocks massive raise (Single Row) (15 pts)
- Allows small valid raise (15 pts)
- Blocks bulk update (Multi Row) (15 pts)
- Blocks invalid department transfer (10 pts)
- Uses Compound Trigger architecture (implied by passing tests without mutating table error) (10 pts)

Pass threshold: 65 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compound_trigger_budget_protection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "compound_trigger_result.json")
        try:
            copy_from_env("/tmp/compound_trigger_result.json", result_path)
            with open(result_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve test results: {str(e)}"
            }

    score = 0
    feedback_parts = []

    # 1. Table check (10 pts)
    if result.get("table_exists") and result.get("columns_correct"):
        score += 10
        feedback_parts.append("Budget table exists (+10)")
    else:
        feedback_parts.append("Budget table missing or invalid structure")

    # 2. Data check (15 pts)
    if result.get("data_calculation_correct"):
        score += 15
        feedback_parts.append("Budget caps calculated correctly (+15)")
    else:
        feedback_parts.append("Budget caps incorrect logic")

    # 3. Trigger check (10 pts)
    if result.get("trigger_exists") and result.get("trigger_status") == 'ENABLED':
        score += 10
        feedback_parts.append("Trigger exists and enabled (+10)")
    else:
        feedback_parts.append("Trigger missing or disabled")

    # 4. Functional Tests (55 pts total)
    
    # Check for mutating table error first (Auto-fail functional tests if present)
    if result.get("mutating_table_error"):
        feedback_parts.append("FAIL: Mutating Table Error (ORA-04091) detected. You must use a Compound Trigger or package state.")
    else:
        # 4a. Blocks massive raise (15)
        if result.get("test_massive_raise_blocked"):
            score += 15
            feedback_parts.append("Correctly blocked budget overrun (+15)")
        else:
            feedback_parts.append("Failed to block budget overrun")

        # 4b. Allows small raise (15)
        if result.get("test_small_raise_allowed"):
            score += 15
            feedback_parts.append("Correctly allowed valid update (+15)")
        else:
            feedback_parts.append("Incorrectly blocked valid update")

        # 4c. Blocks bulk update (15)
        if result.get("test_bulk_update_blocked"):
            score += 15
            feedback_parts.append("Correctly blocked bulk update (+15)")
        else:
            feedback_parts.append("Failed to block bulk update")
        
        # 4d. Blocks transfer (10)
        if result.get("test_transfer_blocked"):
            score += 10
            feedback_parts.append("Correctly blocked invalid transfer (+10)")
        else:
            feedback_parts.append("Failed to block invalid transfer")

    # 5. Architecture/Error Message (10 pts)
    # If they passed massive + bulk without mutating error, they used correct architecture
    if result.get("test_massive_raise_blocked") and not result.get("mutating_table_error"):
        if result.get("error_message_correct"):
            score += 10
            feedback_parts.append("Correct error message and architecture (+10)")
        else:
            score += 5
            feedback_parts.append("Correct architecture, generic error message (+5)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result.get("details", [])
    }