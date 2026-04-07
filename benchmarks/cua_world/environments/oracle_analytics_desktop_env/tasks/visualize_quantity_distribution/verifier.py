#!/usr/bin/env python3
"""
Verifier for visualize_quantity_distribution task.

Strategy:
1. File Verification (40%): Check if .dva file exists and was created during task.
2. VLM Verification (60%): Analyze trajectory frames to confirm:
   - Bar chart creation
   - X-Axis shows discrete numbers (1, 2, 3...), indicating "Attribute" treatment
   - Y-Axis shows Count (frequency)
   - Proper title and sorting
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visualize_quantity_distribution(traj, env_info, task_info):
    """
    Verify the quantity distribution visualization task.
    """
    # 1. Setup Phase
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    
    # Copy result JSON
    result_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_json:
        try:
            copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load result json: {e}")
        finally:
            if os.path.exists(temp_json.name):
                os.unlink(temp_json.name)

    # 2. File-Based Verification (30 Points)
    score = 0
    feedback_parts = []
    
    output_exists = result_data.get('output_exists', False)
    created_fresh = result_data.get('file_created_during_task', False)
    file_size = result_data.get('output_size_bytes', 0)

    if output_exists:
        if file_size > 1000: # Min valid DVA size
            score += 15
            feedback_parts.append("Workbook file created.")
            
            if created_fresh:
                score += 15
                feedback_parts.append("File created during task.")
            else:
                feedback_parts.append("File timestamp predates task (stale?).")
        else:
            feedback_parts.append("Workbook file too small/empty.")
    else:
        feedback_parts.append("Workbook file not found.")

    # 3. Content Inspection (Optional/Advanced - check DVA internals if needed)
    # DVA is a zip. We could check if it contains specific XML definitions.
    # For this task, we'll rely on VLM for content correctness to avoid fragility with internal XML formats.

    # 4. VLM Verification (70 Points)
    # We use trajectory frames to ensure the work was done and to verify the visual state.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + [final_frame] if final_frame else frames

    vlm_prompt = """
    You are evaluating an agent using Oracle Analytics Desktop.
    The goal is to create a Bar Chart showing the frequency of 'Quantity' (count of orders per quantity size).
    
    Look at the sequence of screenshots and the final state.
    
    Check for these specific criteria:
    1. CHART_TYPE: Is a Bar Chart visible? (Vertical bars)
    2. X-AXIS CONFIGURATION (CRITICAL): Does the X-axis (bottom) show a sequence of discrete numbers like "1, 2, 3, 4..."? 
       - If it shows a single bar or weird aggregations, the agent failed to treat Quantity as an Attribute.
       - If it shows "Sum of Quantity", it is WRONG.
    3. Y-AXIS CONFIGURATION: Does the Y-axis show a Count or Frequency? (Bars should be of varying heights, typically decreasing as quantity increases).
    4. SORTING: Are the bars sorted by the X-axis value (1, 2, 3...) in ascending order?
    5. TITLE: Is the title roughly "Line Item Quantity Frequency"?
    
    Respond in JSON:
    {
        "chart_visible": true/false,
        "x_axis_is_discrete_numbers": true/false,
        "y_axis_looks_like_count": true/false,
        "sorted_ascending": true/false,
        "title_correct": true/false,
        "reasoning": "..."
    }
    """
    
    vlm_result = query_vlm(images=all_images, prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("chart_visible"):
            score += 15
            feedback_parts.append("Bar chart created.")
            
            if parsed.get("x_axis_is_discrete_numbers"):
                score += 25
                feedback_parts.append("X-Axis correctly set to discrete Quantity.")
            else:
                feedback_parts.append("X-Axis incorrect (Quantity likely treated as Measure/Sum).")
                
            if parsed.get("y_axis_looks_like_count"):
                score += 15
                feedback_parts.append("Y-Axis appears to show count distribution.")
            
            if parsed.get("sorted_ascending"):
                score += 10
                feedback_parts.append("Sorted correctly.")
                
            if parsed.get("title_correct"):
                score += 5
                feedback_parts.append("Title correct.")
        else:
            feedback_parts.append("No bar chart detected in screenshots.")
    else:
        feedback_parts.append("VLM verification failed to run.")

    # 5. Final Scoring
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }