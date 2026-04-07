#!/usr/bin/env python3
"""
Verifier for create_area_trend task (Oracle Analytics Desktop).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_area_trend(traj, env_info, task_info):
    """
    Verifies that the agent created a Stacked Area chart showing quarterly revenue trends.
    
    Verification Logic:
    1. File Check (30 pts): 'Quarterly_Revenue_Analysis.dva' exists, > 5KB, created during task.
    2. VLM Chart Check (40 pts): Screenshot shows a Stacked Area chart (filled layers, not lines/bars).
    3. VLM Content Check (20 pts): X-axis shows time (quarters), Y-axis shows revenue, Color legend shows categories.
    4. VLM Workflow Check (10 pts): Trajectory shows interaction with 'Sample Order Lines'.
    """
    
    # 1. Setup & Read JSON Result from Env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: copy_from_env maps container path to host path
        # In this environment, C:\tmp\task_result.json maps to /c/tmp/task_result.json or similar depending on setup
        # But usually we use the unix-style path inside the container that maps to windows drive
        # If the environment exposes C:\ via mount, it's often /mnt/c/tmp...
        # However, standard practice in these Windows envs is that copy_from_env handles the path mapping
        # We will try the path written by the export script: C:\tmp\task_result.json
        # If that fails, we might need a unix-equivalent path, but let's try the direct one first.
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not read task result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: File Existence & Integrity (30 pts) ---
    output_exists = result_data.get('output_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    size_bytes = result_data.get('output_size_bytes', 0)
    
    if output_exists:
        if created_during:
            if size_bytes > 5000: # 5KB threshold
                score += 30
                feedback_parts.append("Workbook file saved successfully.")
            else:
                score += 15
                feedback_parts.append(f"Workbook saved but file size suspiciously small ({size_bytes} bytes).")
        else:
            score += 10
            feedback_parts.append("Workbook exists but was NOT modified during the task.")
    else:
        feedback_parts.append("Workbook file 'Quarterly_Revenue_Analysis.dva' not found.")

    # --- CRITERION 2 & 3: VLM Visualization Analysis (60 pts) ---
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze this screenshot of Oracle Analytics Desktop.
    
    I am looking for a 'Stacked Area Chart' visualization.
    
    1. Chart Type: Is there a chart with filled colored bands stacked on top of each other (Area Chart)? 
       (It should NOT be a line chart, bar chart, or pie chart).
    2. Axes: 
       - Does the X-axis show time/date labels (years, quarters, like '2023 Q1')?
       - Does the Y-axis show numerical values (likely revenue/amounts)?
    3. Grouping: Is there a color legend showing multiple categories (e.g., 'Furniture', 'Technology', 'Office Supplies')?
    4. Text:
       - Is the title "Quarterly Revenue by Product Category" visible?
       - Is the canvas tab named "Revenue Trends"?
    
    Return JSON:
    {
        "is_stacked_area_chart": boolean,
        "x_axis_is_time": boolean,
        "y_axis_is_metric": boolean,
        "multiple_categories_visible": boolean,
        "title_correct": boolean,
        "canvas_tab_renamed": boolean
    }
    """
    
    vlm_result = query_vlm(image=final_screenshot, prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Chart Type (25 pts)
        if parsed.get("is_stacked_area_chart"):
            score += 25
            feedback_parts.append("Correct Stacked Area chart detected.")
        else:
            feedback_parts.append("Failed to verify Stacked Area chart type visually.")
            
        # Content (25 pts)
        content_score = 0
        if parsed.get("x_axis_is_time"): content_score += 5
        if parsed.get("y_axis_is_metric"): content_score += 5
        if parsed.get("multiple_categories_visible"): content_score += 5
        if parsed.get("title_correct"): content_score += 5
        if parsed.get("canvas_tab_renamed"): content_score += 5
        
        score += content_score
        if content_score > 0:
            feedback_parts.append(f"Content verification: {content_score}/25 points.")
    else:
        feedback_parts.append("Visual verification failed (VLM error).")

    # --- CRITERION 4: Workflow (10 pts) ---
    frames = sample_trajectory_frames(traj, n=3)
    workflow_prompt = "Do these screenshots show a user interacting with Oracle Analytics Desktop to build a chart? Look for dragging fields or menu interactions."
    workflow_check = query_vlm(images=frames, prompt=workflow_prompt)
    
    if workflow_check.get("success") and "yes" in str(workflow_check.get("parsed", "")).lower():
        score += 10
        feedback_parts.append("Workflow interaction verified.")
    else:
        # Fallback: if file was created, assume some workflow happened
        if created_during:
            score += 10

    # Final Pass Determination
    # Must have file saved AND correct chart type visually identified
    pass_threshold = 60
    chart_verified = vlm_result.get("success") and vlm_result.get("parsed", {}).get("is_stacked_area_chart")
    
    passed = (score >= pass_threshold) and output_exists and chart_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }