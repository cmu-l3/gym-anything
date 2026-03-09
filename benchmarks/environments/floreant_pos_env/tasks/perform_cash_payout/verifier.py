#!/usr/bin/env python3
"""
Verifier for perform_cash_payout task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_cash_payout(traj, env_info, task_info):
    """
    Verifies that a cash payout was correctly recorded in the DB and visually confirmed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Task requirements
    expected_amount = task_info['metadata'].get('expected_amount', 12.50)
    expected_reason = task_info['metadata'].get('expected_reason', "Emergency Limes").lower()
    
    # 1. Load exported results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Analyze DB Transactions
    transactions = result.get('transactions', [])
    found_payout = False
    amount_match = False
    reason_match = False
    
    # Search for the specific transaction
    for tx in transactions:
        tx_type = tx.get('type', '').replace('_', '').replace(' ', '').upper() # Normalize PAY_OUT, PAYOUT
        tx_amount = float(tx.get('amount', 0.0))
        tx_note = tx.get('note', '').lower()
        
        # Check if it looks like a payout (Type check or negative amount logic if type missing)
        if 'PAYOUT' in tx_type or 'PAY' in tx_type:
            found_payout = True
            
            # Check amount (absolute value to handle accounting sign differences)
            if abs(abs(tx_amount) - expected_amount) < 0.01:
                amount_match = True
            
            # Check reason text
            if expected_reason in tx_note:
                reason_match = True
                
            if amount_match and reason_match:
                break

    # Scoring - Database (Max 70)
    if found_payout:
        score += 30
        feedback.append("Payout transaction created in database.")
        if amount_match:
            score += 30
            feedback.append(f"Correct amount ({expected_amount}) recorded.")
        else:
            feedback.append(f"Incorrect amount recorded.")
        
        if reason_match:
            score += 10
            feedback.append(f"Correct reason ('{expected_reason}') recorded.")
        else:
            feedback.append("Reason text missing or incorrect in DB record.")
    else:
        feedback.append("No payout transaction found in database.")

    # 3. VLM Verification (Max 30)
    # Check if the agent actually navigated the Manager menu
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Analyze this sequence of screenshots from a POS system.
    Did the user:
    1. Access a 'Manager' or 'Admin' menu?
    2. Enter a numeric PIN?
    3. Click a 'Pay Out' or 'Payout' button?
    4. Type 'Emergency Limes' or similar text?
    
    Return JSON: {"manager_menu": bool, "payout_selected": bool, "text_typed": bool}
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('manager_menu'):
            score += 10
            feedback.append("VLM confirmed Manager menu access.")
        if parsed.get('payout_selected'):
            score += 10
            feedback.append("VLM confirmed Pay Out selection.")
        if parsed.get('text_typed'):
            score += 10
            feedback.append("VLM confirmed text entry.")
            
    except Exception as e:
        print(f"VLM error: {e}")
        # Fallback: if DB passed perfectly, give partial VLM points
        if amount_match and reason_match:
            score += 15

    # 4. Anti-Gaming / Validity
    if not result.get('app_was_running', False):
        score = 0
        feedback.append("CRITICAL: Application was closed during verification.")

    passed = (found_payout and amount_match and score >= 70)

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }