#!/usr/bin/env python3
"""
Verifier for Share the Candies task.

Verification Strategy:
1. File-based: Check if 'candy_problem.txt' exists, was created during task, and has valid format.
2. File-based: Check if 'candy_success.png' exists and was created during task.
3. VLM-based: Analyze trajectory to verify:
   - Agent found the "Share the candies" activity.
   - Agent performed distribution (drag-and-drop).
   - Agent achieved success state.
   - The counts in text file roughly match visual reality.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_share_candies(traj, env_info, task_info):
    """
    Verify the Share the Candies task using file checks and VLM trajectory analysis.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 2. File-Based Verification (40 points max)
    
    # Check Text File (20 pts)
    text_exists = result.get("text_file_exists", False)
    text_fresh = result.get("text_created_during_task", False)
    text_content = result.get("text_content", "")
    
    candies_reported = None
    children_reported = None
    
    if text_exists and text_fresh:
        score += 10
        # Check format "Candies: X, Children: Y"
        match = re.search(r"Candies:\s*(\d+).*Children:\s*(\d+)", text_content, re.IGNORECASE)
        if match:
            score += 10
            candies_reported = int(match.group(1))
            children_reported = int(match.group(2))
            feedback_parts.append(f"Problem recorded: {candies_reported} candies, {children_reported} children")
        else:
            feedback_parts.append("Text file exists but format incorrect (Expected 'Candies: X, Children: Y')")
    else:
        feedback_parts.append("Problem text file missing or not created during task")

    # Check Agent Screenshot (20 pts)
    screenshot_exists = result.get("agent_screenshot_exists", False)
    screenshot_fresh = result.get("agent_screenshot_created_during_task", False)
    
    if screenshot_exists and screenshot_fresh:
        score += 20
        feedback_parts.append("Success screenshot saved")
    else:
        feedback_parts.append("Success screenshot missing")

    # 3. VLM Verification (60 points max)
    
    # Prepare images: trajectory frames + final system screenshot
    frames = sample_trajectory_frames(traj, n=4)
    final_sys_screenshot = get_final_screenshot(traj)
    
    # If we have no visual evidence, we can't award VLM points
    if not frames and not final_sys_screenshot:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " (No visual evidence for VLM)"
        }
    
    all_images = frames + [final_sys_screenshot] if final_sys_screenshot else frames

    prompt = f"""
    You are verifying an agent playing the 'Share the candies' activity in GCompris.
    
    Task requirements:
    1. Navigate to 'Share the candies' (looks like candies/sweets icon).
    2. Count candies and children (Agent reported: Candies={candies_reported if candies_reported else 'Unknown'}, Children={children_reported if children_reported else 'Unknown'}).
    3. Distribute candies equally (drag from pile to children).
    4. Finish with empty pile and happy/success state.

    Analyze the sequence of screenshots:
    - ACTIVITY_FOUND: Is the 'Share the candies' activity visible in any frame? (Look for a central pile of sweets/candies and characters/children around it).
    - DISTRIBUTION_ACTION: Is there evidence of items being moved/distributed? (e.g., pile getting smaller, candies appearing near children).
    - SUCCESS_STATE: Does the final state show an empty source pile and a success indicator (flower, smiley, or 'OK' button)?
    - COUNTS_PLAUSIBLE: If the activity is visible, do the reported counts ({candies_reported}, {children_reported}) look roughly correct? (Just answer 'yes' if plausible or if you can't count them precisely).

    Respond in JSON:
    {{
        "activity_found": true/false,
        "distribution_action": true/false,
        "success_state": true/false,
        "counts_plausible": true/false,
        "reasoning": "brief explanation"
    }}
    """

    vlm_result = query_vlm(prompt=prompt, images=all_images)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("activity_found"):
            score += 15
            feedback_parts.append("VLM: Activity found")
        
        if parsed.get("distribution_action"):
            score += 15
            feedback_parts.append("VLM: Distribution action observed")
            
        if parsed.get("success_state"):
            score += 20
            feedback_parts.append("VLM: Success state confirmed")
            
        if parsed.get("counts_plausible") and candies_reported is not None:
            score += 10
            feedback_parts.append("VLM: Counts plausible")
            
        feedback_parts.append(f"VLM Reasoning: {parsed.get('reasoning', 'None')}")
    else:
        feedback_parts.append("VLM analysis failed")

    # Final Pass/Fail logic
    # Pass if score >= 70 AND essential criteria met
    passed = (score >= 70) and (candies_reported is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }