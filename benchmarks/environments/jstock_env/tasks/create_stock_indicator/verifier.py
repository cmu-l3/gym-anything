#!/usr/bin/env python3
"""
Verifier for create_stock_indicator task.

Verifies that the agent:
1. Created a new indicator file (anti-gaming timestamp check).
2. Used the correct name "HighMomentum".
3. Configured the Price > 100.0 condition.
4. Configured the Volume > 1,000,000 condition.
5. Used visual verification (VLM) to confirm the editor was used.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_stock_indicator(traj, env_info, task_info):
    """
    Verify the creation of the custom stock indicator.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # Extract file-based verification results
    file_created = result.get('file_created_during_task', False)
    name_found = result.get('indicator_name_found', False)
    price_found = result.get('price_condition_found', False)
    volume_found = result.get('volume_condition_found', False)
    logic_found = result.get('logic_found', False)
    
    # 1. File Creation (Anti-Gaming) - 15 pts
    if file_created:
        score += 15
        feedback_parts.append("New indicator file created during task")
    else:
        feedback_parts.append("No new indicator file found")

    # 2. Indicator Name - 20 pts
    if name_found:
        score += 20
        feedback_parts.append("Indicator name 'HighMomentum' correct")
    else:
        feedback_parts.append("Indicator name 'HighMomentum' NOT found")

    # 3. Price Condition - 20 pts
    if price_found:
        score += 20
        feedback_parts.append("Price condition (>100) correct")
    else:
        feedback_parts.append("Price condition missing or incorrect")

    # 4. Volume Condition - 20 pts
    if volume_found:
        score += 20
        feedback_parts.append("Volume condition (>1,000,000) correct")
    else:
        feedback_parts.append("Volume condition missing or incorrect")
        
    # 5. VLM Verification - 25 pts
    # We use VLM to ensure the agent actually interacted with the editor UI
    # and didn't just paste a file (though file pasting is harder here without the exact XML schema)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of the JStock software. "
        "Did the user open the 'Stock Indicator Editor' window? "
        "Can you see a form or dialog where they are adding conditions like 'Last Price' or 'Volume'? "
        "Is there a tree structure or list showing these conditions? "
        "Answer 'YES' if the Stock Indicator Editor workflow is visible, otherwise 'NO'."
    )
    
    try:
        vlm_response = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        if "YES" in vlm_response.upper():
            score += 25
            feedback_parts.append("VLM verified editor workflow")
        else:
            feedback_parts.append("VLM did not observe Stock Indicator Editor usage")
            logger.info(f"VLM Response: {vlm_response}")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        # Fallback partial credit if file checks passed strong
        if file_created and name_found:
            score += 10
            feedback_parts.append("VLM check failed, granted partial fallback credit")

    # Final logic check (Bonus/Safety)
    if logic_found and price_found and volume_found:
        # Implicitly handled in conditions, but good for feedback
        pass

    passed = score >= 60 and name_found and file_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }