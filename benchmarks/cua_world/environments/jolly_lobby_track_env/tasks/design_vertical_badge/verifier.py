#!/usr/bin/env python3
"""
Verifier for design_vertical_badge task.

Criteria:
1. File Creation (50 pts): A file named 'Vertical_Standard' must exist and be created/modified during the task.
2. Orientation Verification (50 pts): Validated via VLM analysis of the design process (trajectory) and final state.
   - Did the agent select "Portrait"?
   - Is the badge taller than it is wide?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_vertical_badge(traj, env_info, task_info):
    """
    Verifies that the agent created a vertical/portrait badge template.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Load Programmatic Results
    task_result = {}
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data."}

    score = 0
    feedback = []
    
    # --- Check 1: File Existence & Freshness (50 pts) ---
    file_exists = task_result.get("file_exists", False)
    created_fresh = task_result.get("created_during_task", False)
    
    if file_exists:
        if created_fresh:
            score += 50
            feedback.append("Success: 'Vertical_Standard' template created during task.")
        else:
            score += 20
            feedback.append("Partial: 'Vertical_Standard' exists but was not modified during this session.")
    else:
        feedback.append("Fail: No file named 'Vertical_Standard' found.")

    # --- Check 2: Orientation via VLM (50 pts) ---
    # We rely heavily on VLM because proprietary file formats are hard to parse reliably for layout.
    
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        feedback.append("Warning: No video evidence available for visual verification.")
    else:
        prompt = """
        You are verifying a software task in a badge designer application.
        The user was asked to create a VERTICAL (Portrait) badge template.
        
        Analyze the screenshots to answer:
        1. Did the user open a "Page Setup", "Badge Properties", or "Orientation" dialog?
        2. Did the user select "Portrait" or set Height > Width?
        3. Does the badge canvas shown in the designer look strictly taller than it is wide (Vertical)?
        4. Did the user save the file?
        
        Answer JSON:
        {
            "portrait_selected_or_visible": true/false,
            "badge_is_vertical": true/false,
            "confidence": "high/medium/low",
            "reasoning": "..."
        }
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            vlm_data = vlm_response.get("parsed", {})
            
            is_vertical = vlm_data.get("badge_is_vertical", False)
            portrait_selected = vlm_data.get("portrait_selected_or_visible", False)
            
            if is_vertical or portrait_selected:
                score += 50
                feedback.append("Success: Visual evidence confirms Portrait/Vertical orientation.")
            else:
                feedback.append("Fail: Visual evidence suggests the badge is still Landscape/Horizontal.")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append("Error during visual verification.")

    # --- Final Scoring ---
    passed = score >= 80  # Requires file creation + correct orientation
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }