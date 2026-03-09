#!/usr/bin/env python3
"""
Verifier for record_customer_receipt task.

Verifies that:
1. A new receipt exists in Manager.io for Ernst Handel.
2. The amount is 3,500.00.
3. The bank account is Cash on Hand.
4. The receipt count increased (anti-gaming).
5. VLM trajectory confirms the creation process.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for standalone testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None


def verify_record_customer_receipt(traj, env_info, task_info):
    """
    Verify the customer receipt creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
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

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (60 points)
    
    # Receipt Found (Payer + Amount match in list)
    if result.get("receipt_found", False):
        score += 25
        feedback_parts.append("Receipt for Ernst Handel found with correct amount.")
    else:
        if result.get("match_payer", False):
            score += 10
            feedback_parts.append("Payer found but amount/details incorrect.")
        elif result.get("match_amount", False):
            feedback_parts.append("Amount found but payer incorrect.")
        else:
            feedback_parts.append("Receipt NOT found.")

    # Bank Account
    if result.get("match_bank", False):
        score += 15
        feedback_parts.append("Correct Bank Account.")
    
    # Date
    if result.get("match_date", False):
        score += 10
        feedback_parts.append("Correct Date.")

    # Count Check (Anti-gaming)
    initial_count = int(result.get("initial_count", 0))
    current_count = int(result.get("current_count", 0))
    if current_count > initial_count:
        score += 10
        feedback_parts.append("Receipt count increased.")
    else:
        feedback_parts.append("Receipt count did NOT increase.")

    # 3. VLM Verification (40 points)
    # We use VLM to verify the trajectory (steps taken) and the final detail view if available.
    
    frames = sample_trajectory_frames(traj, n=6)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)

    vlm_prompt = """
    You are verifying an accounting task in Manager.io.
    The goal was to create a Receipt:
    - Payer: Ernst Handel
    - Amount: 3,500.00
    - Bank Account: Cash on Hand
    
    Look at the image sequence. 
    1. Did the agent navigate to the 'Receipts' tab?
    2. Did they open a 'New Receipt' form?
    3. Can you see 'Ernst Handel' selected as Payer/Customer?
    4. Can you see '3,500' entered as the amount?
    5. Did they save the form (click Create)?
    
    Respond in JSON:
    {
        "navigated_receipts": true/false,
        "form_filled_correctly": true/false,
        "payer_visible": true/false,
        "amount_visible": true/false,
        "save_clicked": true/false
    }
    """
    
    vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_res.get("success"):
        parsed = vlm_res.get("parsed", {})
        
        if parsed.get("navigated_receipts"):
            score += 10
        if parsed.get("form_filled_correctly") or (parsed.get("payer_visible") and parsed.get("amount_visible")):
            score += 20
        if parsed.get("save_clicked"):
            score += 10
        
        feedback_parts.append(f"VLM verification score: {score - (60 if score >= 60 else score)}/40")
    else:
        feedback_parts.append("VLM verification failed (technical error), checking programmatic only.")
        # Fallback: if programmatic was perfect, grant partial VLM points
        if result.get("receipt_found") and current_count > initial_count:
            score += 20 

    # 4. Final Decision
    # Pass if score >= 60 AND receipt was definitely found
    passed = (score >= 60) and result.get("receipt_found", False)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }