#!/usr/bin/env python3
"""Verifier for reconcile_missing_dividends task."""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reconcile_missing_dividends(traj, env_info, task_info):
    """
    Verify that the user correctly identified and added the two missing dividend transactions.
    
    Expected:
    - 4 Dividend transactions total in 2023.
    - Specifically checking for 2023-09-05 and 2023-12-05.
    - Amounts (Gross) and Taxes must match CSV.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    missing_targets = metadata.get('missing_dividends', [])
    expected_total = metadata.get('expected_total_dividends', 4)
    tolerance = metadata.get('tolerance_amount', 0.05)

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/reconcile_final_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: File Modification (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("Portfolio file saved.")
    elif result.get("file_exists"):
        feedback.append("Portfolio file exists but wasn't saved/modified.")
    else:
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found."}

    # Check 2: Total Count (30 pts)
    # User should have added 2 to the existing 2, making 4 total.
    actual_count = result.get("total_dividends_count", 0)
    
    if actual_count == expected_total:
        score += 30
        feedback.append(f"Correct total dividend count ({expected_total}).")
    elif actual_count > expected_total:
        score += 10 # Partial credit, likely duplicates
        feedback.append(f"Too many dividend transactions ({actual_count} > {expected_total}). Check for duplicates.")
    else:
        score += int((actual_count / expected_total) * 15)
        feedback.append(f"Found {actual_count} dividends (expected {expected_total}).")

    # Check 3 & 4: Specific Missing Dividends (20 pts each for existence, +10 for accuracy)
    dividends_found = result.get("dividends", [])
    
    for target in missing_targets:
        target_date = target["date"]
        target_gross = target["gross_amount"]
        target_tax = target["tax_amount"]
        
        # Find match by date
        match = None
        for div in dividends_found:
            # Simple string match YYYY-MM-DD
            if div.get("date") == target_date:
                match = div
                break
        
        if match:
            score += 20
            feedback.append(f"Found dividend for {target_date}.")
            
            # Check Amounts
            actual_gross = match.get("gross_amount", 0)
            actual_tax = match.get("tax_amount", 0)
            
            gross_ok = abs(actual_gross - target_gross) <= tolerance
            tax_ok = abs(actual_tax - target_tax) <= tolerance
            
            if gross_ok:
                score += 5
                feedback.append(f"  - Gross amount correct (${actual_gross:.2f}).")
            else:
                feedback.append(f"  - Gross amount mismatch: Got ${actual_gross:.2f}, expected ${target_gross:.2f}.")
                
            if tax_ok:
                score += 5
                feedback.append(f"  - Tax amount correct (${actual_tax:.2f}).")
            else:
                feedback.append(f"  - Tax amount mismatch: Got ${actual_tax:.2f}, expected ${target_tax:.2f}.")
        else:
            feedback.append(f"Missing dividend for {target_date} NOT found.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }