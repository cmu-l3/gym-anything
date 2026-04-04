#!/usr/bin/env python3
"""
Verifier for record_drip_transaction task (JStock).
Verifies that a dividend and a buy transaction were recorded correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_drip_transaction(traj, env_info, task_info):
    """
    Verify the DRIP transaction task.
    
    Criteria:
    1. Dividend recorded: AAPL, ~$96.00, Mar 2024
    2. Buy recorded: AAPL, ~0.55 units, ~$174.55, Mar 2024
    3. Consistency: Date matches, Comment mentions DRIP
    4. Anti-gaming: Files modified during task
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Extract data
    data = result.get('data', {})
    div_modified = result.get('div_file_modified', False)
    buy_modified = result.get('buy_file_modified', False)
    
    score = 0
    feedback = []

    # --- 1. Verify Dividend Record (35 points) ---
    div_found = data.get('dividend_found', False)
    div_details = data.get('dividend_details', {})
    
    if div_found:
        score += 20
        feedback.append("Dividend record found.")
        
        # Amount check ($96.00)
        try:
            amt = float(div_details.get('amount', '0'))
            if 95.0 <= amt <= 97.0:
                score += 10
            else:
                feedback.append(f"Dividend amount mismatch: expected ~96.00, got {amt}")
        except:
            feedback.append("Invalid dividend amount format.")

        # Date check (Mar 2024)
        date_str = div_details.get('date', '')
        if 'Mar' in date_str and '2024' in date_str:
            score += 5
        else:
            feedback.append(f"Dividend date mismatch: expected Mar 2024, got {date_str}")
    else:
        feedback.append("No AAPL dividend record found.")

    # --- 2. Verify Buy Record (45 points) ---
    buy_found = data.get('buy_found', False)
    buy_details = data.get('buy_details', {})
    
    if buy_found:
        score += 20
        feedback.append("Reinvestment buy record found.")
        
        # Units check (0.55)
        try:
            units = float(buy_details.get('units', '0'))
            if 0.54 <= units <= 0.56:
                score += 10
            else:
                feedback.append(f"Buy units mismatch: expected 0.55, got {units}")
        except:
            pass

        # Price check (174.55)
        try:
            price = float(buy_details.get('price', '0'))
            if 173.0 <= price <= 176.0:
                score += 5
            else:
                feedback.append(f"Buy price mismatch: expected ~174.55, got {price}")
        except:
            pass

        # Date check
        date_str = buy_details.get('date', '')
        if 'Mar' in date_str and '2024' in date_str:
            score += 5
        else:
            feedback.append(f"Buy date mismatch: expected Mar 2024, got {date_str}")
            
        # Comment check
        comment = buy_details.get('comment', '').lower()
        if 'drip' in comment or 'reinvest' in comment:
            score += 5
        else:
            feedback.append("Buy comment missing 'DRIP' keyword.")
    else:
        feedback.append("No AAPL reinvestment buy record found.")

    # --- 3. Anti-Gaming / Consistency (20 points) ---
    
    # Original holdings preserved
    if data.get('original_preserved', False):
        score += 10
    else:
        feedback.append("Original portfolio holdings were modified or deleted.")

    # Files actually modified
    if div_modified and buy_modified:
        score += 10
        feedback.append("Portfolio files modified during task.")
    elif div_modified or buy_modified:
        score += 5
        feedback.append("Partial file modification detected.")
    else:
        feedback.append("No file modifications detected during task time.")

    passed = (score >= 60) and div_found and buy_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }