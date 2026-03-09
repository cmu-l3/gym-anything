#!/usr/bin/env python3
"""
Verifier for record_acquisition_buyout_event task.
Checks if the agent correctly recorded the ATVI buyout transaction in JStock.
"""

import json
import base64
import csv
import io
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_acquisition_buyout_event(traj, env_info, task_info):
    """
    Verifies that the agent recorded the ATVI buyout correctly.
    
    Criteria:
    1. sellportfolio.csv modified during task (anti-gaming).
    2. Record exists for ATVI.
    3. Price is 95.0.
    4. Date is 'Oct 13, 2023'.
    5. Units is 50.
    6. Comment contains acquisition keywords.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_symbol = metadata.get('target_symbol', 'ATVI')
    expected_price = metadata.get('expected_price', 95.0)
    expected_units = metadata.get('expected_units', 50)
    expected_date = metadata.get('expected_date', "Oct 13, 2023")
    comment_keywords = metadata.get('required_comment_keywords', ["msft", "acquired"])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get('sell_portfolio_exists', False):
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found. Did you save the transaction?"}

    if not result.get('sell_portfolio_modified', False):
        return {"passed": False, "score": 0, "feedback": "Portfolio file was not modified. Did you save the transaction?"}

    # Parse CSV Content
    content_b64 = result.get('sell_portfolio_b64', '')
    if not content_b64:
        return {"passed": False, "score": 0, "feedback": "Portfolio file is empty."}

    try:
        csv_content = base64.b64decode(content_b64).decode('utf-8')
        csv_reader = csv.DictReader(io.StringIO(csv_content))
        rows = list(csv_reader)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse portfolio CSV: {str(e)}"}

    # Find the specific transaction
    target_row = None
    for row in rows:
        # JStock symbols often quoted or in 'Code'/'Symbol' columns
        # Check both Code and Symbol columns
        code = row.get('Code', '').strip().upper()
        sym = row.get('Symbol', '').strip().upper()
        if expected_symbol in code or expected_symbol in sym:
            target_row = row
            break

    if not target_row:
        return {"passed": False, "score": 20, "feedback": f"File modified, but no record found for {expected_symbol}."}

    # Scoring
    score = 20 # Base points for having the record
    feedback_parts = [f"Record for {expected_symbol} found."]
    
    # Check Price (25 pts)
    try:
        price = float(target_row.get('Selling Price', '0'))
        if abs(price - expected_price) < 0.01:
            score += 25
            feedback_parts.append(f"Price correct (${expected_price}).")
        else:
            feedback_parts.append(f"Price incorrect (Found: {price}, Expected: {expected_price}).")
    except ValueError:
        feedback_parts.append("Price format invalid.")

    # Check Date (20 pts)
    # JStock format is usually MMM dd, yyyy
    date_val = target_row.get('Date', '').strip()
    if date_val == expected_date:
        score += 20
        feedback_parts.append(f"Date correct ({expected_date}).")
    else:
        # Try simplified check in case of format variations (e.g. 13 Oct vs Oct 13)
        if "Oct" in date_val and "13" in date_val and "2023" in date_val:
             score += 15 # Partial credit for format mismatch but correct day
             feedback_parts.append(f"Date close ({date_val}).")
        else:
             feedback_parts.append(f"Date incorrect (Found: {date_val}, Expected: {expected_date}).")

    # Check Units (15 pts)
    try:
        units = float(target_row.get('Units', '0'))
        if abs(units - expected_units) < 0.01:
            score += 15
            feedback_parts.append(f"Units correct ({expected_units}).")
        else:
            feedback_parts.append(f"Units incorrect (Found: {units}, Expected: {expected_units}).")
    except ValueError:
        feedback_parts.append("Units format invalid.")

    # Check Comment (20 pts)
    comment = target_row.get('Comment', '').lower()
    keyword_match = any(k in comment for k in comment_keywords)
    if keyword_match:
        score += 20
        feedback_parts.append("Comment contains buyout details.")
    elif comment:
        score += 5 # Minimal credit for any comment
        feedback_parts.append("Comment exists but misses keywords 'MSFT' or 'Acquired'.")
    else:
        feedback_parts.append("No comment added regarding acquisition.")

    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }