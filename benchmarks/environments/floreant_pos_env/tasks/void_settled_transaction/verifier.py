#!/usr/bin/env python3
"""
Verifier for void_settled_transaction task.

Criteria:
1. A new ticket must be created (ID > initial).
2. The ticket must have at least 1 item.
3. The ticket must have a payment recorded (Transaction count > 0).
4. The ticket must be marked as VOIDED.

This distinguishes "Void Ticket" (post-payment) from "Void Order" (pre-payment).
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

# Adjust path to import gym_anything utilities if needed, 
# or assume standard environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/Mock for standalone testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not loaded"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_void_settled_transaction(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the agent voided a settled transaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    tickets = result.get('tickets', [])
    
    # 2. Evaluate Best Candidate Ticket
    # The agent might create multiple tickets. We look for ONE that meets all criteria.
    best_score = 0
    feedback = "No valid actions detected."
    
    for t in tickets:
        current_score = 0
        checks = []
        
        # Criterion 1: Created (Implied by existence in list) - 20 pts
        current_score += 20
        checks.append("Ticket Created")
        
        # Criterion 2: Items added - 10 pts
        if t.get('item_count', 0) > 0:
            current_score += 10
            checks.append("Items Added")
        else:
            checks.append("No Items (Fail)")
            
        # Criterion 3: Payment Recorded (Settled) - 30 pts
        # This is CRITICAL. Without this, it's just a cancelled order, not a voided transaction.
        if t.get('transaction_count', 0) > 0:
            current_score += 30
            checks.append("Payment Settled")
        else:
            checks.append("No Payment (Fail)")
            
        # Criterion 4: Voided - 40 pts
        if t.get('voided', False):
            current_score += 40
            checks.append("Ticket Voided")
        else:
            checks.append("Not Voided (Fail)")
            
        # Calculate total for this ticket
        if current_score > best_score:
            best_score = current_score
            feedback = f"Ticket #{t.get('id')}: " + ", ".join(checks)

    # 3. VLM Verification (Trajectory Analysis)
    # We use this to confirm the user actually interacted with the UI naturally
    # specifically looking for the PIN entry or Void confirmation dialogs.
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    if frames and best_score >= 60: # Only bother if programmatic checks mostly pass
        images_to_check = frames + ([final_img] if final_img else [])
        prompt = """
        Analyze these screenshots of a POS system interaction.
        Did the user:
        1. Access a payment screen?
        2. Access a 'Void Ticket' function or enter a Manager PIN (1111)?
        
        Answer yes/no for each and provide a confidence score (0-10).
        """
        
        try:
            # We don't rely heavily on this for the score since the DB is authoritative,
            # but we use it to validate the 'Process'
            vlm_resp = query_vlm(images=images_to_check, prompt=prompt)
            # Assuming VLM returns a structured dict or we parse text. 
            # For robustness, we just assume if we got here and DB is good, we are good.
            # This block is mainly for logging evidence.
            logger.info(f"VLM Analysis: {vlm_resp}")
        except Exception:
            pass

    # 4. Final Decision
    # Pass threshold is strict: Must be settled AND voided.
    passed = (best_score == 100)
    
    if passed:
        feedback = "Success! " + feedback
    else:
        feedback = "Task Failed. Best attempt: " + feedback

    return {
        "passed": passed,
        "score": best_score,
        "feedback": feedback
    }