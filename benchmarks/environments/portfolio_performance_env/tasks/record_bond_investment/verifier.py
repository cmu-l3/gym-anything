#!/usr/bin/env python3
"""
Verifier for record_bond_investment task.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_bond_investment(traj, env_info, task_info):
    """
    Verify the agent correctly set up the bond, recorded buy/interest, and prices.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_isin = metadata.get('expected_isin', 'US91282CJL54')
    expected_shares = metadata.get('expected_shares', 10)
    expected_buy_price = metadata.get('expected_buy_price', 985.00)
    expected_interest_amt = metadata.get('expected_interest_amount', 175.00)
    
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

    # 1. File Modification (10 pts)
    if result.get("file_modified"):
        score += 10
        feedback.append("Portfolio file saved.")
    else:
        feedback.append("Portfolio file NOT saved/modified.")

    # 2. Security Creation (20 pts)
    if result.get("security_found"):
        score += 10
        feedback.append("Security created.")
        if result.get("security_isin_match"):
            score += 10
            feedback.append(f"ISIN matches {expected_isin}.")
        else:
            feedback.append(f"ISIN mismatch (Expected {expected_isin}).")
    else:
        feedback.append("Security not found.")

    # 3. Buy Transaction (25 pts)
    buy = result.get("buy_details", {})
    if result.get("buy_txn_found"):
        score += 10
        feedback.append("Buy transaction recorded.")
        
        # Check shares
        # PP shares are often stored as 10^8 integers. The export script tries to convert.
        # PP Buy Amount is total value.
        shares = buy.get("shares", 0)
        amount = buy.get("amount", 0)
        
        # Allow small floating point tolerance
        if abs(shares - expected_shares) < 0.1:
            score += 5
            feedback.append(f"Shares correct ({shares}).")
        else:
            feedback.append(f"Shares incorrect (Expected {expected_shares}, Got {shares}).")

        # Check Price/Total
        # Expected Total = Shares * Price = 10 * 985 = 9850
        expected_total = expected_shares * expected_buy_price
        if abs(amount - expected_total) < 1.0:
            score += 10
            feedback.append(f"Total buy amount correct ({amount}).")
        else:
            feedback.append(f"Total buy amount incorrect (Expected {expected_total}, Got {amount}).")
            
        # Check Date
        if "2024-01-15" in buy.get("date", ""):
            score += 0 # Just for feedback, implicitly covered by it being the right txn
            pass
    else:
        feedback.append("Buy transaction NOT found.")

    # 4. Interest Payments (25 pts)
    # Expect 2 payments of 175.00
    interest_txns = result.get("interest_txns", [])
    valid_interests = [t for t in interest_txns if abs(t.get("amount", 0) - expected_interest_amt) < 1.0]
    
    if len(valid_interests) >= 2:
        score += 25
        feedback.append("Both coupon payments recorded correctly.")
    elif len(valid_interests) == 1:
        score += 10
        feedback.append("Only one valid coupon payment recorded.")
    elif len(interest_txns) > 0:
        feedback.append(f"Interest recorded but amounts incorrect (Got {[t['amount'] for t in interest_txns]}).")
    else:
        feedback.append("No interest payments recorded.")

    # 5. Historical Prices (20 pts)
    # We expect 3 prices. The export script extracts them raw.
    # PP XML prices `v` attribute scaling is tricky (can be 100, 10000, etc depending on currency/settings).
    # But usually, if user enters 985.00, PP saves it consistently.
    # The export script extracted them. Let's just check existence of 3 entries for now 
    # and rough dates/values if possible.
    prices = result.get("prices", [])
    if len(prices) >= 3:
        score += 20
        feedback.append("Historical prices added.")
    elif len(prices) > 0:
        score += 10
        feedback.append(f"Partial historical prices ({len(prices)}).")
    else:
        feedback.append("No historical prices found.")

    passed = score >= 60 and result.get("security_found") and result.get("buy_txn_found")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }