#!/usr/bin/env python3
"""
Verifier for Split Payment Sale task in Copper POS.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_split_payment_sale(traj, env_info, task_info):
    """
    Verify the split payment task using file checks and VLM.
    
    Criteria:
    1. Receipt screenshot exists and was created during task.
    2. VLM verifies the workflow (items added -> payment -> split).
    3. VLM verifies the receipt/final screen shows split payment details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load result from container
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Receipt File Evidence (30 pts)
    if result.get('receipt_exists'):
        if result.get('receipt_created_during_task'):
            score += 30
            feedback.append("Receipt screenshot saved successfully.")
        else:
            score += 10
            feedback.append("Receipt screenshot exists but has old timestamp.")
    else:
        feedback.append("Receipt screenshot NOT found.")

    # Criterion 2: App Running (10 pts)
    if result.get('app_was_running'):
        score += 10
        feedback.append("Copper POS was running at end of task.")

    # Criterion 3: VLM Workflow Verification (30 pts)
    # Check if we see the payment screen with split tender
    frames = sample_trajectory_frames(traj, n=6)
    
    workflow_prompt = """
    Analyze these screenshots of a Point of Sale system interaction.
    I am looking for a 'Split Payment' workflow.
    
    Key events to look for:
    1. Items being added to the list (Speaker, Cable, Case).
    2. The 'Payment' or 'Check Out' window opening.
    3. A PARTIAL payment being entered (e.g., $50 Cash).
    4. A remaining balance being shown.
    5. The remaining balance being paid (e.g., by Card).
    
    Did the user perform a split payment?
    Reply with JSON: {"split_payment_detected": bool, "items_added": bool, "explanation": "string"}
    """
    
    vlm_workflow = query_vlm(images=frames, prompt=workflow_prompt)
    if vlm_workflow and vlm_workflow.get('parsed', {}).get('split_payment_detected'):
        score += 30
        feedback.append("VLM confirmed split payment workflow.")
    elif vlm_workflow and vlm_workflow.get('parsed', {}).get('items_added'):
        score += 15
        feedback.append("VLM saw items added but missed clear split payment.")
    else:
        feedback.append("VLM did not detect valid sale workflow.")

    # Criterion 4: Receipt/Final Verification (30 pts)
    # Check the specific receipt screenshot saved by the agent (if available) or the final frame
    final_frame = get_final_screenshot(traj)
    
    receipt_prompt = """
    Analyze this final screen or receipt.
    Does it show a completed transaction with TWO payment methods?
    Look for:
    - Total Amount (approx $83.97)
    - Cash: $50.00
    - Card/Credit: Remainder ($33.97)
    
    Reply with JSON: {"two_payment_methods": bool, "cash_50": bool, "explanation": "string"}
    """
    
    vlm_receipt = query_vlm(image=final_frame, prompt=receipt_prompt)
    
    receipt_score = 0
    if vlm_receipt:
        parsed = vlm_receipt.get('parsed', {})
        if parsed.get('two_payment_methods'):
            receipt_score += 20
        if parsed.get('cash_50'):
            receipt_score += 10
    
    score += receipt_score
    if receipt_score > 0:
        feedback.append(f"VLM confirmed receipt details ({receipt_score} pts).")
    else:
        feedback.append("VLM could not verify receipt details on final screen.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }