#!/usr/bin/env python3
"""
Verifier for manage_test_transaction task in Copper POS.

Verification Logic:
1. Programmatic: Checks if the application database files were modified during the task window.
   (Creation and Deletion both trigger DB writes).
2. VLM Trajectory:
   - Verifies the 'Creation' phase: Agent viewed a receipt or payment screen for USB-C Cable.
   - Verifies the 'Deletion' phase: Agent viewed the Transactions list and performed a delete action.
   - Verifies the 'Confirmation': Agent handled the deletion confirmation.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_test_transaction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Programmatic Checks (30 points)
    # We expect the DB to be modified (once for sale, once for delete)
    if result.get('db_modified', False):
        score += 30
        feedback.append("Database activity detected (Transaction processed).")
    else:
        feedback.append("No database activity detected. Did you complete the sale?")
        # Fail early if no DB changes - implies no work done
        return {"passed": False, "score": 0, "feedback": "No transaction data recorded."}

    if result.get('app_running', False):
        score += 10
        feedback.append("Application remains open.")

    # 3. VLM Trajectory Verification (60 points)
    # We need to verify the specific workflow: Sale -> List -> Delete
    
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are verifying a Point of Sale task where the agent must:
    1. Create a sale for a 'USB-C Charging Cable' and pay with Cash.
    2. Go to the 'Transactions' list.
    3. Delete (void) that transaction.

    Analyze the sequence of screenshots. Look for these specific visual evidences:
    
    STEP 1: SALE CREATION
    - Is there a screen showing 'USB-C' item or a 'Receipt' / 'Payment' confirmation?
    
    STEP 2: TRANSACTION MANAGEMENT
    - Is there a screen showing a list of transactions (rows of data)?
    
    STEP 3: DELETION
    - Is there a context menu with 'Delete' selected, or a 'Delete' button being clicked?
    - Is there a confirmation dialog (e.g., 'Are you sure you want to delete...')?

    Return a JSON object with:
    {
        "sale_created": boolean,
        "transactions_list_visited": boolean,
        "deletion_attempted": boolean,
        "item_seen": boolean,
        "confidence": "high/medium/low"
    }
    """

    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if vlm_result and 'parsed' in vlm_result:
        parsed = vlm_result['parsed']
        
        if parsed.get('sale_created', False):
            score += 20
            feedback.append("Visual evidence of sale creation found.")
        else:
            feedback.append("Could not see sale creation/payment screen.")

        if parsed.get('transactions_list_visited', False):
            score += 10
            feedback.append("Visual evidence of Transactions list found.")
        
        if parsed.get('deletion_attempted', False):
            score += 30
            feedback.append("Visual evidence of deletion/voiding action found.")
        else:
            feedback.append("Could not see the deletion action.")
            
    else:
        feedback.append("VLM verification failed to parse.")

    # 4. Final Scoring
    # Pass threshold: Needs DB modification AND visual evidence of deletion
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }