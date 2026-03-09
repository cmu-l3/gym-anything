#!/usr/bin/env python3
"""
Verifier for import_bank_statement task.

Verifies:
1. A new bank statement record exists in the DB (created after task start).
2. The statement contains the specific transactions from the OFX file.
3. The statement is linked to a valid cash/bank account.
4. Uses VLM to verify the UI state if needed (optional secondary signal).
"""

import json
import os
import sys
import logging
import tempfile
from pathlib import Path

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utils if available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not found, falling back to programmatic verification only.")

def verify_import_bank_statement(traj, env_info, task_info):
    """
    Verify the bank statement import.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_transaction_count', 3)
    expected_amounts = metadata.get('expected_amounts', [4500.00, -125.50, -85.20])
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Programmatic Verification (Database)
    statement_found = result.get('statement_found', False)
    details = result.get('statement_details', {})
    
    if statement_found:
        score += 30
        feedback.append("New bank statement record created.")
        
        # Check Item Count
        item_count = details.get('item_count', 0)
        if item_count == expected_count:
            score += 25
            feedback.append(f"Correct transaction count ({item_count}).")
        else:
            feedback.append(f"Incorrect transaction count: {item_count} (expected {expected_count}).")
            
        # Check Amounts
        amounts_str = details.get('amounts', "")
        if amounts_str:
            # Convert comma-separated string to float list
            actual_amounts = [float(x) for x in amounts_str.split(',') if x]
            
            matches = 0
            for exp in expected_amounts:
                # Find matching amount with small tolerance
                if any(abs(act - exp) < 0.05 for act in actual_amounts):
                    matches += 1
            
            # 10 points per correct match (max 30)
            amount_score = matches * 10
            score += amount_score
            feedback.append(f"Matched {matches}/{len(expected_amounts)} transaction amounts.")
        else:
            feedback.append("No transactions found in statement.")
            
        # Check Account Link
        cash_id = details.get('cash_id')
        if cash_id and str(cash_id) != "":
            score += 15
            feedback.append("Statement is correctly linked to a bank account.")
        else:
            feedback.append("Statement is NOT linked to a bank account.")
            
    else:
        feedback.append("No new bank statement found in database.")

    # 3. VLM Verification (Anti-gaming / Confirmation)
    # If score is borderline or to confirm workflow
    if VLM_AVAILABLE and score > 0:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_scr = get_final_screenshot(traj)
            if final_scr:
                frames.append(final_scr)
                
            vlm_response = query_vlm(
                images=frames,
                prompt="Did the user interact with a file upload dialog to select a bank statement file (OFX/QIF/CSV)? Answer yes or no and briefly describe the action."
            )
            
            if "yes" in vlm_response.lower() or "upload" in vlm_response.lower():
                # Verify workflow was followed
                feedback.append("(VLM confirmed file upload interaction)")
            else:
                logger.warning(f"VLM did not detect upload: {vlm_response}")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")

    # Final scoring logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }