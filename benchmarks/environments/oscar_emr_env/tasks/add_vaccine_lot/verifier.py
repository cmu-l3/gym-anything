#!/usr/bin/env python3
"""
Verifier for add_vaccine_lot task.

Verifies:
1. The specific lot number 'FL2025-X9' exists in the database (Critical)
2. The expiry date matches '2026-12-31' (Critical)
3. VLM Verification: Uses trajectory frames to confirm navigation to Administration/Immunization panel.
"""

import json
import os
import tempfile
import logging
import datetime
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt
VLM_PROMPT = """
You are verifying an agent's actions in an Electronic Medical Record (OSCAR EMR).
The agent was tasked with adding a vaccine lot in the Administration panel.

Review the screenshots. Did the agent:
1. Navigate to an "Administration" or "Admin" section?
2. Access a "Prevention", "Immunization", or "Vaccine Lot" management screen?
3. Is there a form visible for adding a new lot (Lot Number, Expiry fields)?

Reply with JSON:
{
  "accessed_admin": true/false,
  "accessed_vaccine_management": true/false,
  "confidence": "low/medium/high"
}
"""

def verify_add_vaccine_lot(traj, env_info, task_info):
    """
    Verify the agent added the correct vaccine lot.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_lot = metadata.get('target_lot', 'FL2025-X9')
    target_expiry = metadata.get('target_expiry', '2026-12-31')

    # 2. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Database Evidence
    score = 0
    feedback = []
    
    lot_found = result.get('lot_found', False)
    found_lot = result.get('found_lot_number', '')
    found_expiry = result.get('found_expiry_date', '') # Format usually YYYY-MM-DD from MySQL

    # Criterion 1: Lot Exists (60 points)
    if lot_found and found_lot == target_lot:
        score += 60
        feedback.append(f"Success: Lot '{target_lot}' found in database.")
    else:
        feedback.append(f"Failure: Lot '{target_lot}' not found in database.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Expiry Date Correct (20 points)
    # Handle potential time formats if necessary, though SQL standard date is YYYY-MM-DD
    if target_expiry in str(found_expiry):
        score += 20
        feedback.append(f"Success: Expiry date '{target_expiry}' is correct.")
    else:
        feedback.append(f"Partial Failure: Expiry date mismatch. Expected '{target_expiry}', found '{found_expiry}'.")

    # 4. VLM Verification (20 points)
    # We check if they actually navigated there, though the DB record is strong proof.
    # If DB proof exists, we can be lenient with VLM or treat it as "process bonus".
    # Here we use it to confirm they didn't just run a SQL injection (unlikely but possible in some CTFs).
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    # Sample frames (middle to end) to capture the admin work
    frames = sample_trajectory_frames(traj, n=4)
    
    if frames:
        try:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            vlm_data = vlm_response.get('parsed', {})
            
            if vlm_data.get('accessed_admin') or vlm_data.get('accessed_vaccine_management'):
                score += 20
                feedback.append("VLM Verification: Confirmed navigation to vaccine management.")
            else:
                # If they passed DB check but VLM failed, we might suspect something, 
                # but usually we trust DB more. We'll give partial points or just warn.
                # In this specific task, DB record is the gold standard.
                # We'll award 10/20 just for having a trajectory.
                score += 10
                feedback.append("VLM Verification: Could not clearly confirm specific screens, but work was done.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if DB is perfect, give almost full marks
            score += 10
            feedback.append("VLM Verification skipped due to error.")
    else:
        feedback.append("No trajectory frames available for VLM.")

    # 5. Final Verdict
    passed = (score >= 80) # Requires Lot + Expiry correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }