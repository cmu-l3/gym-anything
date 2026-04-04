#!/usr/bin/env python3
"""
Verifier for delete_portfolio_transaction task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_portfolio_transaction(traj, env_info, task_info):
    """
    Verifies that MSFT transaction was deleted while AAPL and NVDA remain.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. File-based Verification
    
    # Check 1: MSFT Removed (Critical) - 35 pts
    if not result.get('contains_msft', True):
        score += 35
        feedback_parts.append("MSFT transaction removed successfully.")
    else:
        feedback_parts.append("MSFT transaction still present in file.")

    # Check 2: AAPL Preserved - 20 pts
    if result.get('contains_aapl', False):
        score += 20
        feedback_parts.append("AAPL transaction preserved.")
    else:
        feedback_parts.append("Error: AAPL transaction missing.")

    # Check 3: NVDA Preserved - 20 pts
    if result.get('contains_nvda', False):
        score += 20
        feedback_parts.append("NVDA transaction preserved.")
    else:
        feedback_parts.append("Error: NVDA transaction missing.")

    # Check 4: Row Count (Should be exactly 2) - 10 pts
    row_count = result.get('row_count', -1)
    if row_count == 2:
        score += 10
        feedback_parts.append("Portfolio has correct number of entries (2).")
    else:
        feedback_parts.append(f"Portfolio has {row_count} entries (expected 2).")

    # Check 5: File Modified Timestamp - 5 pts
    if result.get('file_modified', False):
        score += 5
    else:
        feedback_parts.append("Warning: Portfolio file timestamp not updated.")

    # 3. VLM Verification - 10 pts
    # Use trajectory to confirm the action was performed in UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        vlm_response = query_vlm(
            images=frames + [final_screen],
            prompt="Does the final screenshot show the JStock portfolio table with exactly two rows (AAPL and NVDA)? Is MSFT missing from the table?"
        )
        
        if vlm_response.get("yes", False) or "yes" in vlm_response.get("text", "").lower():
            score += 10
            feedback_parts.append("Visual verification passed.")
        else:
            feedback_parts.append("Visual verification inconclusive or failed.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if file checks passed perfectly, give full points
        if score >= 90:
            score += 10

    # 4. Final Scoring
    passed = (score >= 75 and not result.get('contains_msft', True) and 
              result.get('contains_aapl', False) and result.get('contains_nvda', False))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }