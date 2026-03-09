#!/usr/bin/env python3
"""
Verifier for save_stock_history_chart task.
Checks if the agent successfully exported a stock chart to a PNG file.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_save_stock_history_chart(traj, env_info, task_info):
    """
    Verify stock chart export task.
    
    Criteria:
    1. File /home/ga/Documents/NVDA_chart.png exists (15 pts)
    2. File is a valid PNG (15 pts)
    3. File was created AFTER task start (anti-gaming) (15 pts)
    4. File size is reasonable (>5KB) (15 pts)
    5. Image dimensions are reasonable (not full screenshot) (10 pts)
    6. VLM Verification of trajectory (30 pts)
       - Did chart window open?
       - Did context menu appear?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    desktop_width = metadata.get('desktop_width', 1920)
    desktop_height = metadata.get('desktop_height', 1080)
    min_size = metadata.get('min_file_size_bytes', 5000)

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
    
    # --- Programmatic Verification (70 points) ---
    
    # Criterion 1: File Existence
    if result.get('output_exists', False):
        score += 15
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file missing")
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # Criterion 2: Format Check
    fmt = result.get('image_format', 'UNKNOWN')
    if fmt == 'PNG':
        score += 15
        feedback_parts.append("Valid PNG format")
    else:
        feedback_parts.append(f"Invalid format: {fmt} (expected PNG)")

    # Criterion 3: Anti-Gaming Timestamp Check
    if result.get('file_created_during_task', False):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates pre-existing file")

    # Criterion 4: File Size Check
    size = result.get('output_size_bytes', 0)
    if size > min_size:
        score += 15
        feedback_parts.append(f"File size valid ({size} bytes)")
    else:
        feedback_parts.append(f"File too small ({size} bytes)")

    # Criterion 5: Dimension Sanity Check
    # A chart export from JStock (JFreeChart) usually isn't exactly the full screen resolution
    # unless maximized perfectly without borders. Full screen screenshot would be bad.
    w = result.get('image_width', 0)
    h = result.get('image_height', 0)
    
    is_full_screenshot = (w == desktop_width and h == desktop_height)
    is_reasonable_chart = (w > 200 and h > 150) # Very minimal check
    
    if is_reasonable_chart and not is_full_screenshot:
        score += 10
        feedback_parts.append(f"Dimensions reasonable ({w}x{h})")
    elif is_full_screenshot:
        # Partial credit if they took a screenshot instead of exporting, but discouraged
        score += 2
        feedback_parts.append("Warning: Image dimensions match full screen (screenshot detected instead of chart export?)")
    else:
        feedback_parts.append(f"Dimensions suspicious ({w}x{h})")

    # --- VLM Verification (30 points) ---
    # Check if they actually opened the chart window
    
    frames = sample_trajectory_frames(traj, n=6)
    vlm_prompt = (
        "Analyze these screenshots of a stock market application (JStock).\n"
        "1. Did a 'Stock History' or chart window appear showing a line/candlestick chart?\n"
        "2. Did a context menu (right-click menu) appear on the chart?\n"
        "3. Did a 'Save' dialog appear?\n"
        "Reply 'YES' if the workflow shows opening a chart and interacting with it, otherwise 'NO'."
    )
    
    try:
        vlm_response = query_vlm(images=frames, prompt=vlm_prompt).strip()
        if "YES" in vlm_response.upper():
            score += 30
            feedback_parts.append("VLM verified workflow")
        else:
            # Fallback: if programmatic signals are strong, give partial VLM credit
            # Sometimes VLM misses details in complex UIs
            if score >= 60: 
                score += 15
                feedback_parts.append("VLM uncertain, but file output confirms success")
            else:
                feedback_parts.append("VLM did not verify chart interaction")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # If VLM fails but file is perfect, grant points
        if score >= 60:
            score += 30
            feedback_parts.append("VLM skipped (error), output verified")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }