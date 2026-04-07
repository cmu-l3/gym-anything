#!/usr/bin/env python3
"""
Verifier for visualize_log_scale_distribution task in Oracle Analytics Desktop.

Verifies:
1. Workbook existence and modification timestamp (Programmatic).
2. Logarithmic scale application and correct chart configuration (VLM).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visualize_log_scale_distribution(traj, env_info, task_info):
    """
    Verify that the user created a scatter plot with a logarithmic X-axis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # Criterion 1: Workbook Saved (20 pts)
    if result_data.get("output_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback.append("Workbook saved successfully.")
    else:
        feedback.append("Workbook 'Distribution_Analysis' not found or not saved during task.")

    # 3. VLM Verification (80 pts)
    # Use trajectory to see if they opened properties, and final screen for result
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
         return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}
    
    all_images = frames + [final_screen]
    
    prompt = """
    You are evaluating an agent using Oracle Analytics Desktop.
    The goal is to create a Scatter Plot of Sales (X) vs Profit (Y) and set the X-axis to a LOGARITHMIC scale.
    
    Analyze the screenshots (chronological order) and the final result:
    
    1. **Chart Type**: Is there a Scatter plot (dots/bubbles)?
    2. **Variables**: Does the X-axis appear to be Sales and Y-axis Profit?
    3. **Logarithmic Scale**: This is the most important check.
       - Look at the X-axis grid lines and labels.
       - On a LOG scale, the spacing between grid lines is non-uniform (wide then narrow), or the labels jump by orders of magnitude (e.g., 10, 100, 1k, 10k).
       - On a LINEAR scale, the spacing is even (0, 10k, 20k, 30k).
       - Does the data look spread out across the chart (Good/Log), or is it all squashed into a vertical line on the left side (Bad/Linear)?
    4. **Color**: Are the points colored (Product Category)?
    
    Respond in JSON:
    {
        "chart_type_correct": true/false,
        "measures_correct": true/false,
        "log_scale_applied": true/false,
        "color_applied": true/false,
        "reasoning": "Explain why you think it is/is not log scale based on grid lines/labels/data shape"
    }
    """
    
    vlm_response = query_vlm(images=all_images, prompt=prompt)
    
    if vlm_response.get("success"):
        analysis = vlm_response.get("parsed", {})
        
        if analysis.get("chart_type_correct"):
            score += 20
            feedback.append("Correct scatter plot type created.")
        else:
            feedback.append("Incorrect chart type.")
            
        if analysis.get("measures_correct"):
            score += 10
            feedback.append("Correct axes (Sales/Profit) detected.")
            
        if analysis.get("color_applied"):
            score += 10
            feedback.append("Color encoding applied.")
            
        if analysis.get("log_scale_applied"):
            score += 40
            feedback.append("Logarithmic scale successfully applied (verified visually).")
        else:
            feedback.append("Logarithmic scale NOT detected. Data appears linear or clustered at origin.")
            
        logger.info(f"VLM Analysis: {analysis.get('reasoning')}")
    else:
        feedback.append("VLM verification failed to process images.")

    # Final Pass Logic
    passed = score >= 70 and analysis.get("log_scale_applied", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }