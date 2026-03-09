#!/usr/bin/env python3
"""
Verifier for identify_volatile_stock task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_volatile_stock(traj, env_info, task_info):
    """
    Verify that the agent correctly identified the most volatile stock.
    
    Expected behavior:
    1. Agent reads High, Low, Last columns from JStock.
    2. Calculates (High-Low)/Last for all stocks.
    3. Identifies AMD as the winner (Vol ~5.07%).
    4. Writes 'AMD' to ~/most_volatile_stock.txt.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_symbol = metadata.get('expected_symbol', 'AMD')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check file existence (20 points)
    output_exists = result.get("output_exists", False)
    if output_exists:
        score += 20
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file missing")
        return {"passed": False, "score": 0, "feedback": "Output file missing"}

    # 2. Check content (60 points)
    content = result.get("output_content", "").strip().upper()
    if content == expected_symbol:
        score += 60
        feedback_parts.append(f"Correct symbol identified: {content}")
    else:
        feedback_parts.append(f"Incorrect symbol: '{content}' (Expected: {expected_symbol})")

    # 3. Check anti-gaming timestamp (20 points)
    created_during_task = result.get("file_created_during_task", False)
    if created_during_task:
        score += 20
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("File timestamp invalid (created before task?)")

    # 4. Optional VLM Verification (Bonus/Validation)
    # Check if the agent actually looked at the data
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        vlm_prompt = (
            "Does the screen show a stock market application (JStock) with a list of stocks? "
            "Are columns for 'High', 'Low', and 'Last' visible? "
            "Answer yes/no."
        )
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if "yes" in vlm_result.lower():
            feedback_parts.append("VLM verified JStock visibility")
        else:
            feedback_parts.append("VLM could not verify JStock visibility")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Final verdict
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }