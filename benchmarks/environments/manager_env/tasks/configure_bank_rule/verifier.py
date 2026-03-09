#!/usr/bin/env python3
"""
Verifier for configure_bank_rule task.

Verifies:
1. "Rent Expense" account creation (30 pts)
2. Account grouping (Expenses) and code (10 pts)
3. Bank Rule creation (20 pts)
4. Rule condition "Downtown Properties" (20 pts)
5. Rule allocation to "Rent Expense" (20 pts)

Uses programmatic API checks from the container.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_bank_rule(traj, env_info, task_info):
    """
    Verify the bank rule configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
            
    # Extract state
    state = result.get("manager_state", {})
    errors = state.get("errors", [])
    
    if errors:
        logger.warning(f"Verification script reported errors: {errors}")

    score = 0
    feedback_parts = []
    
    # Scoring Criteria
    
    # 1. Rent Expense Account (30 pts)
    if state.get("account_exists"):
        score += 30
        feedback_parts.append("Account 'Rent Expense' created")
    else:
        feedback_parts.append("Account 'Rent Expense' NOT found")

    # 2. Account Details (10 pts)
    # We combine code and group checks
    if state.get("account_group_correct") or state.get("account_code_correct"):
        score += 10
        feedback_parts.append("Account details (Group/Code) correct")
    elif state.get("account_exists"):
        feedback_parts.append("Account created but Group/Code may be incorrect")

    # 3. Bank Rule Exists (20 pts)
    if state.get("rule_exists"):
        score += 20
        feedback_parts.append("Bank Rule created")
    else:
        feedback_parts.append("No Bank Rule found")

    # 4. Rule Condition (20 pts)
    if state.get("rule_condition_correct"):
        score += 20
        feedback_parts.append("Rule matches 'Downtown Properties'")
    elif state.get("rule_exists"):
        feedback_parts.append("Rule condition incorrect")

    # 5. Rule Allocation (20 pts)
    if state.get("rule_allocation_correct"):
        score += 20
        feedback_parts.append("Rule allocates to 'Rent Expense'")
    elif state.get("rule_exists"):
        feedback_parts.append("Rule allocation incorrect")

    # Success determination
    # Must have at least created the account and the rule to pass
    passed = (state.get("account_exists") and state.get("rule_exists")) and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "details": state
    }