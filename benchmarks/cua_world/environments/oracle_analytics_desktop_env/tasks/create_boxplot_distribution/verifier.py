#!/usr/bin/env python3
"""
Verifier for Create Box Plot task in Oracle Analytics Desktop.

Verification Strategy:
1. File Verification (40 pts): Checks existence, timestamp, and size of the .dva workbook.
2. Internal Metadata Verification (30 pts): Parses the internal JSON of the .dva file
   to confirm the visualization type is 'boxPlot' and correct columns ('Profit', 'Product Sub Category') are used.
3. VLM Verification (30 pts): Uses trajectory frames to verify the agent actually performed the steps
   (selecting chart type, dragging columns) and the final result looks like a box plot.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_boxplot(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', 'Profit Distribution by Sub-Category')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path in container is C:\temp\task_result.json
        copy_from_env("C:\\temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. File Verification (40 pts)
    if result.get('file_exists'):
        score += 10
        feedback_parts.append("Workbook file created.")
        
        if result.get('file_created_during_task'):
            score += 20
            feedback_parts.append("File created during task session.")
        else:
            feedback_parts.append("File timestamp is old (pre-task).")
            
        if result.get('file_size_bytes', 0) > 2000: # Empty DVAs are ~1kb, populated ~10kb+
            score += 10
            feedback_parts.append("File size indicates content.")
        else:
            feedback_parts.append("File seems empty.")
    else:
        feedback_parts.append("Workbook file NOT found.")
        # If file doesn't exist, strictly limit score
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 3. Metadata Content Verification (30 pts)
    dva_json = result.get('dva_internal_json', '')
    
    # Check Visualization Type
    # Oracle Analytics internal names vary, but usually 'boxPlot', 'boxplot', or 'box-plot'
    if 'boxPlot' in dva_json or 'boxplot' in dva_json or 'box-plot' in dva_json:
        score += 15
        feedback_parts.append("Confirmed Box Plot visualization type.")
    else:
        feedback_parts.append("Could not confirm Box Plot type in metadata.")

    # Check Columns
    # Look for references to the columns in the metadata
    columns_found = 0
    if 'Profit' in dva_json:
        columns_found += 1
    if 'Product Sub Category' in dva_json or 'Product SubCategory' in dva_json:
        columns_found += 1
        
    if columns_found == 2:
        score += 10
        feedback_parts.append("Correct data columns mapped.")
    elif columns_found == 1:
        score += 5
        feedback_parts.append("Some data columns missing.")
    else:
        feedback_parts.append("Required data columns not found in metadata.")
        
    # Check Title
    if expected_title in dva_json:
        score += 5
        feedback_parts.append("Chart title set correctly.")

    # 4. VLM Verification (30 pts)
    # Using trajectory to ensure work was done and final visual is correct
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = f"""
    You are verifying an Oracle Analytics Desktop task.
    Goal: Create a Box Plot of 'Profit' by 'Product Sub Category' with title '{expected_title}'.
    
    Review the images:
    1. Do you see the user selecting 'Box Plot' or a statistical chart type?
    2. Do you see a box-and-whisker plot in the final result (boxes with lines extending out)?
    3. Is the title '{expected_title}' visible?
    
    Provide a JSON response:
    {{
        "box_plot_visible": true/false,
        "title_correct": true/false,
        "workflow_observed": true/false,
        "confidence": "high/medium/low"
    }}
    """
    
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final_screen])
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('box_plot_visible'):
            score += 15
            feedback_parts.append("VLM confirmed Box Plot visual.")
        
        if parsed.get('title_correct'):
            score += 5
            feedback_parts.append("VLM confirmed title.")
            
        if parsed.get('workflow_observed'):
            score += 10
            feedback_parts.append("VLM confirmed workflow.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification skipped due to error.")
        # Fallback: if metadata was strong, give partial credit
        if columns_found == 2 and 'boxPlot' in dva_json:
            score += 15

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }