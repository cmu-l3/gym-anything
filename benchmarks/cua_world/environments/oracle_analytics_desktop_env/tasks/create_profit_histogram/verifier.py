#!/usr/bin/env python3
"""
Verifier for create_profit_histogram task.

Strategy:
1. Programmatic: Check if 'ProfitDistribution.dva' workbook was saved and modified during task.
2. VLM: Check trajectory for workflow (Chart type selection, Title entry).
3. VLM: Check final screenshot for Histogram structure (bins vs simple bars) and correct title.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_profit_histogram(traj, env_info, task_info):
    """
    Verifies that the agent created a Profit Histogram in Oracle Analytics Desktop.
    """
    # 1. Setup - Get programmatic results from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Container path is Windows, but copy_from_env handles the abstraction usually.
        # If running on Linux host verifying Windows container, path format might need care.
        # Assuming copy_from_env handles the container's path string.
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Scoring (40 points)
    score = 0
    feedback_parts = []
    
    # Criterion 1: Workbook saved (20 pts)
    if result_data.get("output_exists", False):
        score += 20
        feedback_parts.append("Workbook file saved")
    else:
        feedback_parts.append("Workbook file 'ProfitDistribution' not found")

    # Criterion 2: Anti-gaming / Freshness (10 pts)
    if result_data.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("Workbook modified during task")
    elif result_data.get("output_exists", False):
        feedback_parts.append("Workbook not modified during task session")

    # Criterion 3: App running (10 pts)
    if result_data.get("app_running", False):
        score += 10
    
    # 3. VLM Verification (60 points)
    # Sampling frames to catch the workflow
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if not final_shot:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification"}
    
    all_images = frames + [final_shot]
    
    # Prompt for VLM
    prompt = """
    You are verifying an Oracle Analytics Desktop task.
    Goal: Create a Histogram of 'Profit' with the title 'Distribution of Order Profits'.
    
    Analyze the screenshots (chronological order) and the final result.
    
    Check for:
    1. HISTOGRAM_TYPE: Is the visualization a Histogram? 
       - Look for continuous bins (bars often touching or equal width intervals).
       - It should NOT be a simple bar chart with categorical labels (like product names) on the X-axis. 
       - The X-axis should show numeric ranges of Profit (e.g., -500 to 0, 0 to 500).
    
    2. AXES_SETUP:
       - X-Axis: Should be 'Profit'.
       - Y-Axis: Should be 'Count', 'Frequency', or '# of Orders'.
       
    3. TITLE: Is the title "Distribution of Order Profits" visible?
    
    4. WORKFLOW: Did the user interact with the visualization type selector or settings to choose Histogram?

    Respond in JSON:
    {
        "is_histogram": boolean,
        "is_bar_chart_of_categories": boolean,
        "x_axis_is_profit": boolean,
        "title_correct": boolean,
        "workflow_observed": boolean,
        "explanation": "string"
    }
    """
    
    vlm_result = query_vlm(images=all_images, prompt=prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Scoring VLM criteria
        if parsed.get("is_histogram", False) and not parsed.get("is_bar_chart_of_categories", False):
            score += 25
            feedback_parts.append("VLM confirmed Histogram chart type")
        else:
            feedback_parts.append("VLM did not see a valid Histogram (might be bar chart of categories)")
            
        if parsed.get("x_axis_is_profit", False):
            score += 15
            feedback_parts.append("X-axis is Profit")
            
        if parsed.get("title_correct", False):
            score += 10
            feedback_parts.append("Title is correct")
            
        if parsed.get("workflow_observed", False):
            score += 10
            feedback_parts.append("Workflow interaction observed")
            
        feedback_parts.append(f"VLM Note: {parsed.get('explanation', 'No details')}")
    else:
        feedback_parts.append("VLM verification failed to run")

    # 4. Final Assessment
    # Mandatory: Must have saved file AND created a histogram
    passed = (score >= 60) and result_data.get("output_exists", False) and vlm_result.get("success") and vlm_result.get("parsed", {}).get("is_histogram", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }