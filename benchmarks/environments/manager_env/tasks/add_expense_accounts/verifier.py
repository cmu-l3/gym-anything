#!/usr/bin/env python3
"""
Verifier for add_expense_accounts task in Manager.io.

Verifies that:
1. Three specific expense accounts exist in the Chart of Accounts.
2. They have the correct Names and Codes.
3. They are assigned to the 'Expenses' group.
4. Changes happened during the task (anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_expense_accounts(traj, env_info, task_info):
    """
    Verify creation of Freight (5100), Vehicle (5200), and Professional (5300) accounts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Expected Data
    metadata = task_info.get('metadata', {})
    expected_accounts = metadata.get('accounts', [])
    
    # 2. Load Result Data from Container
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Scraping error: {result['error']}"}

    # 3. Analyze Results
    score = 0
    max_score = 100
    feedback = []
    
    final_rows = result.get("final_accounts_text_rows", [])
    initial_raw = result.get("initial_accounts_raw", [])
    
    # Anti-gaming: Check if anything changed
    # Simple check: length of text dump or direct content comparison
    if not final_rows:
        return {"passed": False, "score": 0, "feedback": "Chart of Accounts appears empty or inaccessible."}
        
    # Helper to check if an account exists in the rows
    # We look for a row that contains both the Name and the Code
    def check_account(name, code, group):
        # Manager rows often look like: "5100 Freight and Delivery Expenses"
        # We allow flexible matching since HTML layout varies
        for row in final_rows:
            if name in row and code in row:
                # Group check is harder as it might be a header, but often appears in "Type" column
                # or indented under a header. We'll be lenient on group for basic scoring,
                # but give bonus if "Expenses" is likely associated.
                return True
        return False

    # Check each expected account
    accounts_created = 0
    for acct in expected_accounts:
        name = acct['name']
        code = acct['code']
        group = acct['group']
        
        if check_account(name, code, group):
            score += 30  # 30 points per account
            accounts_created += 1
            feedback.append(f"✓ Found account: {name} ({code})")
        else:
            feedback.append(f"✗ Missing account: {name} ({code})")
            
            # Partial credit check: Name only or Code only?
            found_name = any(name in row for row in final_rows)
            found_code = any(code in row for row in final_rows)
            if found_name:
                score += 10
                feedback.append(f"  (Name '{name}' found but code mismatch/missing)")
            elif found_code:
                score += 10
                feedback.append(f"  (Code '{code}' found but name mismatch/missing)")

    # 4. Global Checks (10 points)
    # Check if 'Expenses' is mentioned in the rows (simple group verification)
    if result.get("found_Expenses_Group"):
        score += 10
        feedback.append("✓ 'Expenses' group detected")
    else:
        feedback.append("✗ 'Expenses' group not detected in page text")

    # 5. Anti-gaming check (Did we start from a clean-ish state?)
    # If the accounts were already there in initial state, we shouldn't give full credit
    # (Though setup script creates fresh Northwind usually, this protects against restart persistence issues)
    pre_existing = 0
    for acct in expected_accounts:
        # Check initial_raw (which is a list of cell strings)
        # We just concat it for searching
        initial_text = " ".join(initial_raw)
        if acct['name'] in initial_text and acct['code'] in initial_text:
            pre_existing += 1
    
    if pre_existing == len(expected_accounts):
        score = 0
        feedback.insert(0, "FAILED: Accounts already existed before task started (Anti-gaming)")
    elif pre_existing > 0:
        score = max(0, score - (pre_existing * 30))
        feedback.append(f"WARNING: {pre_existing} accounts already existed.")

    # 6. Final Decision
    passed = (accounts_created >= 2) and (score >= 60)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback)
    }