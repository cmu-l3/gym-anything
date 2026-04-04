#!/usr/bin/env python3
"""
Verifier for Chinook Data Recovery Task
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_data_recovery(traj, env_info, task_info):
    """
    Verifies that the agent restored 2009 data while preserving 2025 data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Ground Truths
    GT_2009_INVOICES = 83
    GT_2009_ITEMS = 438  # Approx check
    GT_2025_INVOICES = 5
    GT_2009_REVENUE = 449.46
    
    # Load Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Anti-Gaming Check: 2025 Data Preservation (20 pts)
    # If this fails, the agent likely just overwrote the file.
    cnt_2025 = result.get("count_2025_invoices", 0)
    if cnt_2025 == GT_2025_INVOICES:
        score += 20
        feedback.append("Success: 2025 data preserved.")
    elif cnt_2025 > 0:
        score += 10
        feedback.append(f"Partial: Some 2025 data preserved ({cnt_2025}/{GT_2025_INVOICES}).")
    else:
        feedback.append("Fail: 2025 data lost (likely overwrote database file).")
        # Critical failure implies bad methodology, but we check other stats for partial credit logic
        # strictly speaking, usually this invalidates the whole task, but we'll cap score.

    # 2. Restoration of 2009 Invoices (25 pts)
    cnt_2009_inv = result.get("count_2009_invoices", 0)
    if cnt_2009_inv == GT_2009_INVOICES:
        score += 25
        feedback.append(f"Success: All {GT_2009_INVOICES} 2009 invoices restored.")
    elif cnt_2009_inv > 0:
        # Scale score
        partial = int((cnt_2009_inv / GT_2009_INVOICES) * 25)
        score += partial
        feedback.append(f"Partial: {cnt_2009_inv}/{GT_2009_INVOICES} 2009 invoices restored.")
    else:
        feedback.append("Fail: No 2009 invoices restored.")

    # 3. Restoration of 2009 Items (25 pts)
    cnt_2009_items = result.get("count_2009_items", 0)
    # Allow small variance just in case, though it should be exact
    if abs(cnt_2009_items - GT_2009_ITEMS) <= 5:
        score += 25
        feedback.append(f"Success: 2009 invoice items restored ({cnt_2009_items}).")
    elif cnt_2009_items > 0:
        partial = int((cnt_2009_items / GT_2009_ITEMS) * 25)
        score += partial
        feedback.append(f"Partial: {cnt_2009_items}/{GT_2009_ITEMS} invoice items restored.")
    else:
        feedback.append("Fail: No 2009 invoice items restored.")

    # 4. Revenue Integrity (15 pts)
    # Checks that the data wasn't corrupted during insert
    try:
        rev_2009 = float(result.get("revenue_2009", 0))
    except (ValueError, TypeError):
        rev_2009 = 0.0

    if abs(rev_2009 - GT_2009_REVENUE) < 1.0:
        score += 15
        feedback.append("Success: 2009 Revenue matches ground truth.")
    else:
        feedback.append(f"Fail: Revenue mismatch (Got {rev_2009}, Expected ~{GT_2009_REVENUE}).")

    # 5. Script Existence (15 pts)
    if result.get("script_exists", False):
        score += 15
        feedback.append("Success: SQL recovery script found.")
    else:
        feedback.append("Fail: SQL recovery script not found.")

    passed = score >= 60 and (cnt_2025 == GT_2025_INVOICES) and (cnt_2009_inv > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }