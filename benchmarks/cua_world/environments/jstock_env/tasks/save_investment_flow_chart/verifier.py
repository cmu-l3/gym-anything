#!/usr/bin/env python3
"""
Verifier for save_investment_flow_chart task.

Combines file-based verification (checking the exported chart image)
with VLM-based verification (checking the agent's workflow trajectory).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_save_investment_flow_chart(traj, env_info, task_info):
    """
    Verify that the agent navigated to the Investment Flow chart and saved it as a PNG.
    """
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load task metadata
    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_bytes', 5000)
    
    # 3. Retrieve and parse result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion A: File Existence & Validity (40 pts)
    output_exists = result.get('output_exists', False)
    is_png = result.get('is_png', False)
    file_size = result.get('output_size_bytes', 0)
    created_during_task = result.get('file_created_during_task', False)

    if output_exists:
        if is_png:
            score += 20
            feedback_parts.append("Valid PNG file found.")
        else:
            feedback_parts.append("File exists but is not a valid PNG.")
            
        if file_size > min_size:
            score += 10
            feedback_parts.append("File size indicates real content.")
        else:
            feedback_parts.append(f"File too small ({file_size} bytes).")
            
        if created_during_task:
            score += 10
            feedback_parts.append("File created during task execution.")
        else:
            feedback_parts.append("File timestamp predates task (anti-gaming check failed).")
    else:
        feedback_parts.append("Output file 'investment_flow.png' not found.")

    # Criterion B: Dimensions (10 pts)
    # Charts are usually not tiny thumbnails
    width = result.get('image_width', 0)
    height = result.get('image_height', 0)
    if width > 300 and height > 200:
        score += 10
        feedback_parts.append(f"Image dimensions reasonable ({width}x{height}).")
    elif output_exists:
        feedback_parts.append(f"Image dimensions suspiciously small ({width}x{height}).")

    # Criterion C: VLM Workflow Verification (50 pts)
    # Did the agent actually open the Investment Flow chart?
    # This catches "screenshotting the desktop" or other shortcuts.
    
    # Select frames
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame]
    
    prompt = (
        "Analyze these screenshots of a stock market software (JStock). "
        "Did the user perform the following steps?\n"
        "1. Open a chart or report view titled 'Investment Flow Summary' or showing 'Invested Capital' vs 'Current Value'.\n"
        "2. Interact with the chart (e.g., right-click context menu) or use a menu to save/export it.\n"
        "Answer YES or NO and explain."
    )
    
    try:
        vlm_response = query_vlm(images=images, prompt=prompt).strip()
        logger.info(f"VLM Verification Response: {vlm_response}")
        
        if "YES" in vlm_response.upper():
            score += 50
            feedback_parts.append("VLM verified workflow: Chart accessed and export action observed.")
        else:
            feedback_parts.append("VLM did not verify the workflow (chart navigation not clearly seen).")
            # If we have a perfect file, we might be lenient, but for now stick to strict verification
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("VLM verification unavailable.")

    # 5. Final Pass/Fail
    # Must have a valid file created during task AND (good size OR VLM confirmation)
    file_valid = output_exists and is_png and created_during_task
    passed = file_valid and score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }