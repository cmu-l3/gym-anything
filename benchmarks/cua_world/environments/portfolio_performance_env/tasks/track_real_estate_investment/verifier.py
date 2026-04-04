#!/usr/bin/env python3
"""Verifier for track_real_estate_investment task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_track_real_estate_investment(traj, env_info, task_info):
    """
    Verify the real estate investment task.
    
    Criteria:
    1. Security "Oak Street Rental Property" created.
    2. Buy transaction ~285,000 EUR.
    3. 6 Dividend transactions (~1,200 EUR each).
    4. 2 Historical price entries matching dates/values.
    5. File saved (modified).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_prices = metadata.get('expected_prices', [])
    
    # Copy result
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
    feedback = []

    # 1. File Status (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("Portfolio file saved.")
    elif result.get("file_exists"):
        feedback.append("Portfolio file exists but was not modified (did you save?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found."}

    # 2. Security Creation (15 pts)
    if result.get("security_found"):
        score += 15
        feedback.append(f"Security found: {result.get('security_name')}")
    else:
        feedback.append("Security 'Oak Street Rental Property' not found.")

    # 3. Buy Transaction (20 pts)
    if result.get("buy_txn_found"):
        amount = result.get("buy_amount", 0)
        # Tolerance 1%
        if abs(amount - 285000) < 2850:
            score += 20
            feedback.append("Buy transaction correct.")
        else:
            score += 10
            feedback.append(f"Buy transaction found but amount {amount} incorrect (expected 285,000).")
    else:
        feedback.append("Buy transaction not found.")

    # 4. Dividends (30 pts)
    div_count = result.get("dividend_count", 0)
    div_total = result.get("dividend_total", 0)
    
    # 5 points per dividend up to 6
    capped_count = min(div_count, 6)
    score += (capped_count * 5)
    
    if div_count >= 6:
        feedback.append(f"Recorded {div_count} rental income payments.")
    elif div_count > 0:
        feedback.append(f"Recorded {div_count}/6 rental income payments.")
    else:
        feedback.append("No rental income (dividends) recorded.")
        
    # Check average amount
    if div_count > 0:
        avg = div_total / div_count
        if abs(avg - 1200) > 12:
            feedback.append(f"Warning: Average rental income {avg} deviates from expected 1200.")

    # 5. Historical Prices (15 pts)
    # Check for presence of specific dates and values
    price_entries = result.get("price_entries", [])
    found_p1 = False
    found_p2 = False
    
    for p in price_entries:
        date = p.get("date", "")
        val = p.get("value", 0)
        
        # Check Mar 31
        if "2024-03-31" in date:
            if abs(val - 288000) < 2880: # 1% tolerance
                found_p1 = True
        
        # Check Jun 30
        if "2024-06-30" in date:
            if abs(val - 291500) < 2915:
                found_p2 = True

    if found_p1:
        score += 8
        feedback.append("Q1 Appraisal price correct.")
    if found_p2:
        score += 7
        feedback.append("Q2 Appraisal price correct.")
        
    if not (found_p1 or found_p2) and len(price_entries) > 0:
        score += 5
        feedback.append("Some price entries found but dates/values didn't match targets.")

    # 6. VLM Workflow (10 pts)
    # Verify screenshots exist (basic check)
    # In a full VLM setup we would query the trajectory, here we give points for attempting
    if result.get("file_modified"): # Proxy for interaction
        score += 10
        
    passed = score >= 60 and result.get("buy_txn_found")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }