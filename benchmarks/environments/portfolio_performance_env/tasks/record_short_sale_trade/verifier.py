#!/usr/bin/env python3
"""
Verifier for record_short_sale_trade task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_short_sale_trade(traj, env_info, task_info):
    """
    Verify the short sale workflow in Portfolio Performance.
    1. Check if PTON security was added.
    2. Verify Short Sale (Sell) transaction details.
    3. Verify Cover (Buy) transaction details.
    4. Ensure Net Position is 0 (Trade closed).
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    metadata = task_info.get('metadata', {})
    expected_short_price = metadata.get('short_price', 124.00)
    expected_cover_price = metadata.get('cover_price', 18.50)
    expected_short_fee = metadata.get('short_fee', 25.00)
    expected_cover_fee = metadata.get('cover_fee', 15.00)

    # 1. File Modification (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("Portfolio saved successfully.")
    else:
        feedback.append("Portfolio file not found or not saved.")

    # 2. Security Added (10 pts)
    if result.get("pton_security_found"):
        score += 10
        feedback.append("Peloton (PTON) security found.")
    else:
        feedback.append("Peloton security not found.")

    # 3. Short Sale Record (30 pts)
    sell_found = result.get("sell_txn_found")
    if sell_found:
        score += 15
        sell_data = result.get("sell_details", {})
        
        # Check amount (Price * Shares = 12400)
        # PP stores gross amount usually
        amount = sell_data.get("amount", 0)
        expected_amt = 100 * expected_short_price
        if abs(amount - expected_amt) < 1.0:
            score += 10
            feedback.append("Short sale price correct.")
        else:
            feedback.append(f"Short sale amount mismatch: {amount} vs {expected_amt}.")
            
        # Check fees
        fee = sell_data.get("fee", 0)
        if abs(fee - expected_short_fee) < 0.1:
            score += 5
            feedback.append("Short sale fee correct.")
        else:
            feedback.append(f"Short sale fee mismatch: {fee} vs {expected_short_fee}.")
    else:
        feedback.append("Opening short sale (Sell) on 2021-07-01 not found.")

    # 4. Cover Buy Record (30 pts)
    buy_found = result.get("buy_txn_found")
    if buy_found:
        score += 15
        buy_data = result.get("buy_details", {})
        
        # Check amount
        amount = buy_data.get("amount", 0)
        expected_amt = 100 * expected_cover_price
        if abs(amount - expected_amt) < 1.0:
            score += 10
            feedback.append("Cover buy price correct.")
        else:
            feedback.append(f"Cover buy amount mismatch: {amount} vs {expected_amt}.")
            
        # Check fees
        fee = buy_data.get("fee", 0)
        if abs(fee - expected_cover_fee) < 0.1:
            score += 5
            feedback.append("Cover buy fee correct.")
        else:
            feedback.append(f"Cover buy fee mismatch: {fee} vs {expected_cover_fee}.")
    else:
        feedback.append("Closing cover trade (Buy) on 2022-05-02 not found.")

    # 5. Net Position (20 pts)
    # The agent must have actually closed the position
    net_shares = result.get("net_shares", -999)
    if sell_found and buy_found and abs(net_shares) < 0.01:
        score += 20
        feedback.append("Position successfully closed (Net shares: 0).")
    elif sell_found and not buy_found:
        feedback.append(f"Position remains open (Net shares: {net_shares}).")
    elif buy_found and not sell_found:
        feedback.append("Only buy recorded (Long position).")

    passed = score >= 80  # Requires both legs to be substantially correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }