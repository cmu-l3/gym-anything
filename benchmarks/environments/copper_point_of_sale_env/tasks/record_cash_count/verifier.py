#!/usr/bin/env python3
"""
Verifier for record_cash_count task.

Verifies:
1. Anti-gaming: App was running and data files were modified during task.
2. VLM Trajectory: Agent navigated to Cash Count screen and entered correct values.
3. VLM Final: Final state shows the recorded count or success message.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_cash_count(traj, env_info, task_info):
    """
    Verify the cash count was correctly recorded in Copper POS.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Container path is Windows path, but copy_from_env usually handles abstraction
        # or we might need to adjust based on how the runner mounts paths.
        # Assuming copy_from_env takes the internal path as string.
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Checks (Anti-gaming)
    
    # Check if app was running (10 pts)
    if result.get('app_running'):
        score += 10
        feedback_parts.append("Copper POS was running.")
    else:
        feedback_parts.append("Copper POS was NOT running.")
        
    # Check if files were modified (20 pts)
    # This proves the "Save" button was likely clicked and DB updated
    if result.get('files_modified'):
        score += 20
        feedback_parts.append("Data files were modified (evidence of saved work).")
    else:
        feedback_parts.append("No data files modified (did you save?).")

    # 3. VLM Trajectory Verification (70 pts)
    # We verify the workflow steps using visual evidence
    
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying a user performing a 'Cash Count' task in a Point of Sale software (Copper POS).
    The user is supposed to:
    1. Open the Cash Count / Register Count window.
    2. Enter specific quantities for bills/coins (Total should be roughly $347.85).
    3. Save the count.

    Examine the sequence of screenshots.
    
    Q1: Is the 'Cash Count' or 'Till Count' window visible in any frame? (Look for a grid of denominations like $1, $5, $10, $20)
    Q2: Can you see numbers entered into the denomination fields?
    Q3: Does the Total amount shown match approximately $347.85 (or visible parts sum to it)?
    Q4: Did the user appear to click 'Save' or 'OK'?
    
    Return JSON:
    {
        "cash_count_window_seen": true/false,
        "values_entered": true/false,
        "total_match": true/false,
        "save_action_seen": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and isinstance(vlm_result, dict):
        vlm_data = vlm_result.get('parsed', {})
        
        # Scoring VLM
        if vlm_data.get('cash_count_window_seen'):
            score += 20
            feedback_parts.append("Cash count window detected.")
        else:
            feedback_parts.append("Could not find Cash Count window in screenshots.")
            
        if vlm_data.get('values_entered'):
            score += 20
            feedback_parts.append("Values entered into fields.")
            
        if vlm_data.get('total_match'):
            score += 20
            feedback_parts.append("Total amount appears correct ($347.85).")
        
        if vlm_data.get('save_action_seen'):
            score += 10
            feedback_parts.append("Save action observed.")
            
    else:
        feedback_parts.append("VLM verification failed to process images.")

    # 4. Final Decision
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }