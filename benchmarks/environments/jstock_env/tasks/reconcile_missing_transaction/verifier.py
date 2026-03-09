#!/usr/bin/env python3
"""
Verifier for JStock Reconcile Missing Transaction Task.
Checks if the agent identified and added the missing GOOGL transaction correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reconcile_missing_transaction(traj, env_info, task_info):
    """
    Verify the portfolio reconciliation task.
    
    Expected Outcome:
    1. 'buyportfolio.csv' exists and was modified.
    2. Contains AAPL and MSFT (preserved).
    3. Contains GOOGL (added).
    4. GOOGL details match: 20 units, 148.5 price, date "Jan 22, 2024".
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_stock = metadata.get('missing_stock', 'GOOGL')
    expected_units = float(metadata.get('expected_units', 20.0))
    expected_price = float(metadata.get('expected_price', 148.5))
    expected_date = metadata.get('expected_date_str', 'Jan 22, 2024')
    
    # Setup temp file for result
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

    # Basic Checks
    if not result.get('portfolio_exists'):
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found."}
    
    if not result.get('modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "Portfolio was not modified during the task."}

    data = result.get('portfolio_data', [])
    if not data:
        return {"passed": False, "score": 0, "feedback": "Portfolio is empty or unreadable."}

    # Analyze Data
    found_stocks = {}
    for row in data:
        code = row.get('Code', '').strip().upper()
        # Clean up quotes if present (though csv reader usually handles this, JStock format can be tricky)
        code = code.replace('"', '')
        if code:
            found_stocks[code] = row

    score = 0
    feedback = []

    # Check 1: Missing Stock Found (30 pts)
    if expected_stock in found_stocks:
        score += 30
        feedback.append(f"Successfully added {expected_stock}.")
        
        googl_entry = found_stocks[expected_stock]
        
        # Check 2: Correct Units (20 pts)
        try:
            units = float(googl_entry.get('Units', '0').replace('"', ''))
            if abs(units - expected_units) < 0.01:
                score += 20
                feedback.append(f"Units correct ({units}).")
            else:
                feedback.append(f"Units incorrect. Expected {expected_units}, got {units}.")
        except ValueError:
            feedback.append("Could not parse Units.")

        # Check 3: Correct Price (20 pts)
        try:
            price = float(googl_entry.get('Purchase Price', '0').replace('"', ''))
            if abs(price - expected_price) < 0.01:
                score += 20
                feedback.append(f"Price correct ({price}).")
            else:
                feedback.append(f"Price incorrect. Expected {expected_price}, got {price}.")
        except ValueError:
            feedback.append("Could not parse Price.")

        # Check 4: Correct Date (20 pts)
        # JStock Date Format: "Jan 22, 2024"
        date_val = googl_entry.get('Date', '').replace('"', '').strip()
        if date_val == expected_date:
            score += 20
            feedback.append(f"Date correct ({date_val}).")
        else:
            # Allow minor format variations if unambiguous (e.g. 01/22/2024) - strictly JStock uses MMM dd, yyyy
            feedback.append(f"Date incorrect. Expected '{expected_date}', got '{date_val}'.")

    else:
        feedback.append(f"{expected_stock} transaction is missing from portfolio.")

    # Check 5: Integrity of other stocks (10 pts)
    existing = metadata.get('existing_stocks', ['AAPL', 'MSFT'])
    integrity_pass = True
    for s in existing:
        if s not in found_stocks:
            integrity_pass = False
            feedback.append(f"Error: Existing stock {s} was deleted.")
    
    if integrity_pass and score > 0:
        score += 10
        feedback.append("Existing portfolio entries preserved.")

    # Final Result
    passed = (score >= 70) and (expected_stock in found_stocks)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }