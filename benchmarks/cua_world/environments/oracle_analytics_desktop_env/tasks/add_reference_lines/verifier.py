#!/usr/bin/env python3
"""
Verifier for add_reference_lines task in Oracle Analytics Desktop.

Verifies:
1. Workbook file 'Revenue_Targets.dva' exists and was created during task.
2. VLM Trajectory: Agent navigated Analytics properties.
3. VLM Final State: Horizontal bar chart with two reference lines (Average + Constant).
"""

import json
import tempfile
import os
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed, though we use gym_anything.vlm usually
sys.path.insert(0, str(Path(__file__).parent.parent))
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_reference_lines(traj, env_info, task_info):
    """
    Verify creation of bar chart with analytical reference lines.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Verify File Existence and Timestamp (Anti-Gaming)
    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    app_running = result.get("app_was_running", False)

    if output_exists:
        score += 15
        feedback_parts.append("Workbook file 'Revenue_Targets.dva' found.")
        if file_created:
            score += 15
            feedback_parts.append("Workbook was saved during the task session.")
        else:
            feedback_parts.append("Warning: Workbook file has old timestamp (pre-task).")
    else:
        feedback_parts.append("Workbook file 'Revenue_Targets.dva' NOT found.")

    if app_running:
        score += 10
        feedback_parts.append("Oracle Analytics Desktop is running.")

    # 3. VLM Verification (Visual Content)
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    # Prompt for Trajectory (Process)
    traj_prompt = """
    You are verifying an agent working in Oracle Analytics Desktop.
    Look at this sequence of screenshots.
    Did the agent:
    1. Open the 'Analytics' or 'Properties' panel (usually an icon looking like a chart with a magnifying glass or sliders on the left/right)?
    2. Add or configure 'Reference Lines' (might see menus for 'Add Reference Line', 'Average', 'Constant')?
    
    Return JSON: {"analytics_panel_opened": bool, "reference_menu_seen": bool}
    """
    
    traj_result = query_vlm(images=frames, prompt=traj_prompt)
    
    # Prompt for Final State (Outcome)
    final_prompt = """
    Analyze this screenshot of an Oracle Analytics Desktop chart.
    
    I expect a Horizontal Bar Chart showing Revenue by Product Category.
    Crucially, it must have TWO reference lines overlaying the bars:
    1. An 'Average' line (often labeled 'Category Average' or similar).
    2. A 'Constant' line at value 300,000 (often labeled 'Target', '300K', or '300,000').
    
    Check for:
    - is_horizontal_bar_chart: boolean
    - reference_lines_count: integer (how many overlay lines seen?)
    - average_line_visible: boolean (is there a line indicating average?)
    - constant_target_line_visible: boolean (is there a line near 300k value?)
    - labels_visible: boolean (are the lines labeled?)
    """
    
    final_vlm_result = query_vlm(image=final_screenshot, prompt=final_prompt)
    
    # Scoring VLM Results
    if traj_result.get("success") and traj_result.get("parsed"):
        parsed = traj_result["parsed"]
        if parsed.get("analytics_panel_opened"):
            score += 5
        if parsed.get("reference_menu_seen"):
            score += 5
            feedback_parts.append("Evidence of Reference Line configuration found in trajectory.")

    if final_vlm_result.get("success") and final_vlm_result.get("parsed"):
        parsed = final_vlm_result["parsed"]
        
        if parsed.get("is_horizontal_bar_chart"):
            score += 10
            feedback_parts.append("Horizontal Bar Chart confirmed.")
        
        ref_count = parsed.get("reference_lines_count", 0)
        if ref_count >= 2:
            score += 10
            feedback_parts.append("Multiple reference lines detected.")
        elif ref_count == 1:
            score += 5
            feedback_parts.append("Only one reference line detected (expected 2).")
            
        if parsed.get("average_line_visible"):
            score += 10
            feedback_parts.append("Average reference line visible.")
            
        if parsed.get("constant_target_line_visible"):
            score += 10
            feedback_parts.append("Target (300k) reference line visible.")
            
        if parsed.get("labels_visible"):
            score += 10
            feedback_parts.append("Reference lines are labeled.")
    else:
        feedback_parts.append("Failed to verify chart visual state.")

    # Pass Threshold
    # Must have file created (anti-gaming) AND significant visual evidence
    passed = (score >= 60) and file_created and output_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }