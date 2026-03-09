#!/usr/bin/env python3
"""
Verifier for import_csv_transactions task.

Checks:
1. XML file modified after task start.
2. Total transaction count = 8.
3. Buy count = 6, Sell count = 2.
4. Specific transactions match expected values (Shares, Value).
5. VLM verification of the import wizard trajectory.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_csv_transactions(traj, env_info, task_info):
    """Verify CSV transactions were imported correctly."""
    
    # 1. Setup and load result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_total = metadata.get('expected_total_count', 8)
    expected_buys = metadata.get('expected_buy_count', 6)
    expected_sells = metadata.get('expected_sell_count', 2)
    check_txns = metadata.get('check_transactions', [])

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
    
    # 2. File modification check (5 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 5
        feedback.append("File saved successfully")
    else:
        feedback.append("File not saved or not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 3. Count checks (20 pts total)
    total_txns = result.get('total_txns', 0)
    buy_count = result.get('buy_count', 0)
    sell_count = result.get('sell_count', 0)

    if total_txns == expected_total:
        score += 10
        feedback.append(f"Total count correct ({total_txns})")
    else:
        feedback.append(f"Total count incorrect ({total_txns}/{expected_total})")

    if buy_count == expected_buys:
        score += 5
        feedback.append("Buy count correct")
    
    if sell_count == expected_sells:
        score += 5
        feedback.append("Sell count correct")

    # 4. Specific Transaction Validation (45 pts total, 15 each)
    imported_txns = result.get('transactions', [])
    
    for check in check_txns:
        desc = check['description']
        c_type = check['type']
        c_shares = check['shares']
        c_amount = check['amount']
        tol = check.get('tolerance', 0.05)
        
        # Find match
        match_found = False
        for t in imported_txns:
            # Check type
            if t['type'] != c_type: continue
            
            # Check values with tolerance
            shares_ok = abs(t['shares'] - c_shares) < 0.001
            amount_diff = abs(t['amount'] - c_amount)
            amount_ok = amount_diff / c_amount < tol if c_amount > 0 else amount_diff < 0.1
            
            if shares_ok and amount_ok:
                match_found = True
                break
        
        if match_found:
            score += 15
            feedback.append(f"Verified {desc}")
        else:
            feedback.append(f"Missing/Incorrect {desc}")

    # 5. Fee check (10 pts)
    # Check if at least some transactions have fees (all in CSV have fees)
    txns_with_fees = sum(1 for t in imported_txns if t.get('fees', 0) > 0)
    if txns_with_fees >= (expected_total - 2): # Allow minor errors
        score += 10
        feedback.append("Fees imported correctly")
    elif txns_with_fees > 0:
        score += 5
        feedback.append("Some fees missing")
    else:
        feedback.append("No fees imported")

    # 6. VLM Verification (20 pts)
    # Check trajectory for Import Wizard
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=8)
        
        prompt = """
        Review these screenshots of a Portfolio Performance task.
        Did the user open the 'Import CSV' wizard?
        Look for a dialog box titled 'Import' or 'CSV Import' with column mapping tables.
        
        Return JSON: {"wizard_visible": boolean}
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res and vlm_res.get('parsed', {}).get('wizard_visible'):
            score += 20
            feedback.append("VLM confirmed import wizard usage")
        else:
            feedback.append("VLM could not confirm wizard usage")
            # Fallback points if data is perfect
            if total_txns == expected_total and score >= 60:
                score += 10
                feedback.append("(Partial credit for result)")
    else:
        score += 20
        feedback.append("VLM check skipped")

    passed = score >= 55 and total_txns > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }