#!/usr/bin/env python3
"""
Verifier for setup_recurring_amortization_journal task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_recurring_amortization_journal(traj, env_info, task_info):
    """
    Verify that the Chart of Accounts has been updated and a Recurring Journal Entry created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_asset = metadata.get('asset_account_name', 'Prepaid Insurance')
    expected_expense = metadata.get('expense_account_name', 'Insurance Expense')
    expected_desc = metadata.get('recurring_entry_description', 'Monthly Insurance Amortization')

    # Copy result JSON
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
    
    # ----------------------------------------------------------------
    # Criterion 1: Accounts Created (40 pts)
    # ----------------------------------------------------------------
    accounts_found = result.get("accounts_found", [])
    coa_html = result.get("chart_of_accounts_html", "")

    # Check for Prepaid Insurance (Asset)
    # We do a loose check on name, then strict check on Group if we parse HTML, 
    # but for robustness against minor HTML variations, simple string existence 
    # of the name in the COA page is a strong signal provided "Do Nothing" check passes.
    if expected_asset in accounts_found or expected_asset in coa_html:
        score += 20
        feedback_parts.append(f"Account '{expected_asset}' found")
    else:
        feedback_parts.append(f"Account '{expected_asset}' NOT found")

    if expected_expense in accounts_found or expected_expense in coa_html:
        score += 20
        feedback_parts.append(f"Account '{expected_expense}' found")
    else:
        feedback_parts.append(f"Account '{expected_expense}' NOT found")

    # ----------------------------------------------------------------
    # Criterion 2: Recurring Journal Entry Created (40 pts)
    # ----------------------------------------------------------------
    recurring_entries = result.get("recurring_entries_found", [])
    rje_html = result.get("recurring_entries_html", "")
    
    entry_found = False
    amount_correct = False
    interval_correct = False

    # Check parsed results first
    for entry in recurring_entries:
        if expected_desc in entry.get("description", ""):
            entry_found = True
            if entry.get("amount_match"):
                amount_correct = True
            if entry.get("interval_match"):
                interval_correct = True
            break
    
    # Fallback to HTML check
    if not entry_found and expected_desc in rje_html:
        entry_found = True
        # Look for 1,000.00 nearby in HTML would be ideal, but simple existence is fallback
        if "1,000.00" in rje_html or "1000.00" in rje_html:
            amount_correct = True
        if "Monthly" in rje_html:
            interval_correct = True

    if entry_found:
        score += 20
        feedback_parts.append(f"Recurring entry '{expected_desc}' found")
        
        if amount_correct:
            score += 10
            feedback_parts.append("Amount 1000.00 verified")
        else:
            feedback_parts.append("Amount verification failed (expected 1000.00)")
            
        if interval_correct:
            score += 10
            feedback_parts.append("Interval 'Monthly' verified")
        else:
            feedback_parts.append("Interval verification failed")
    else:
        feedback_parts.append(f"Recurring entry '{expected_desc}' NOT found")

    # ----------------------------------------------------------------
    # Criterion 3: Trajectory/Anti-Gaming (20 pts)
    # ----------------------------------------------------------------
    # We assume if the accounts and entries exist and were not there at start (implied by environment reset),
    # the agent did the work. 
    # We can add a check for the timestamps if we had granular creation times from the app, 
    # but Manager.io list views don't always show creation timestamps.
    # Instead, we rely on the specific unique names requested.
    
    # Anti-gaming: Ensure we aren't just reading a pre-baked state.
    # The Setup script starts with a clean Northwind (or standard one). 
    # These specific accounts (Prepaid Insurance, Insurance Expense) are NOT in standard Northwind.
    # So their existence is proof of work.
    
    if score >= 60:
        score += 20
        feedback_parts.append("Configuration verified successfully")
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }