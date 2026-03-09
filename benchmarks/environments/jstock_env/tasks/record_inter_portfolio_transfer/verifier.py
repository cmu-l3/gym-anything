#!/usr/bin/env python3
"""
Verifier for record_inter_portfolio_transfer task.

Checks:
1. Safe Harbor: Withdrawal of 12500.0 on Aug 15, 2024 with correct comment.
2. Growth Fund: Deposit of 12500.0 on Aug 15, 2024 with correct comment.
3. Both files modified during task execution.
"""

import json
import os
import tempfile
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_content(content):
    """Parse CSV string into list of dicts."""
    if not content:
        return []
    
    # JStock CSVs often have quoted fields.
    # Format: "Date","Amount","Comment"
    try:
        f = io.StringIO(content.strip())
        reader = csv.DictReader(f)
        rows = list(reader)
        return rows
    except Exception as e:
        logger.error(f"Error parsing CSV: {e}")
        return []

def check_transaction(rows, expected_amount, expected_date, expected_comment, trans_type):
    """
    Search for a transaction matching criteria.
    JStock date format is typically "MMM dd, yyyy" (e.g. "Aug 15, 2024").
    """
    for row in rows:
        # Check Amount
        try:
            amt = float(row.get('Amount', '0').replace(',', ''))
        except ValueError:
            continue
            
        if abs(amt - expected_amount) > 0.01:
            continue
            
        # Check Date
        row_date = row.get('Date', '').strip()
        # Loose match on date components if exact match fails
        if row_date != expected_date:
            # Try partial matching if format differs slightly
            if expected_date not in row_date:
                continue

        # Check Comment
        row_comment = row.get('Comment', '').strip()
        if expected_comment.lower() not in row_comment.lower():
            continue
            
        return True, f"Found {trans_type}: {row_date} | ${amt} | {row_comment}"

    return False, f"Missing {trans_type}: Exp {expected_date} | ${expected_amount} | {expected_comment}"

def verify_record_inter_portfolio_transfer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_amount = metadata.get('transfer_amount', 12500.0)
    expected_date = metadata.get('transfer_date', "Aug 15, 2024")
    expected_comment = metadata.get('transfer_comment', "Allocation Adjustment")

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

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Check Safe Harbor (Withdrawal)
    # ---------------------------------------------------------
    safe_data = result.get('safe_harbor', {})
    safe_passed = False
    
    if safe_data.get('modified'):
        rows = parse_csv_content(safe_data.get('content', ''))
        found, msg = check_transaction(rows, expected_amount, expected_date, expected_comment, "Withdrawal")
        if found:
            score += 40
            safe_passed = True
            feedback.append(msg)
        else:
            feedback.append(msg)
    else:
        feedback.append("Safe Harbor file not modified/created.")

    # ---------------------------------------------------------
    # Check Growth Fund (Deposit)
    # ---------------------------------------------------------
    growth_data = result.get('growth_fund', {})
    growth_passed = False
    
    if growth_data.get('modified'):
        rows = parse_csv_content(growth_data.get('content', ''))
        found, msg = check_transaction(rows, expected_amount, expected_date, expected_comment, "Deposit")
        if found:
            score += 40
            growth_passed = True
            feedback.append(msg)
        else:
            feedback.append(msg)
    else:
        feedback.append("Growth Fund file not modified/created.")

    # ---------------------------------------------------------
    # Secondary Checks
    # ---------------------------------------------------------
    # Both sides must be present for consistency bonus
    if safe_passed and growth_passed:
        score += 20
        feedback.append("Consistency check passed: Transfer recorded on both sides.")
    
    # Verify app was running (anti-gaming check, low weight but good practice)
    if not result.get('app_was_running', False):
        feedback.append("Warning: JStock was not running at verification time.")

    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }