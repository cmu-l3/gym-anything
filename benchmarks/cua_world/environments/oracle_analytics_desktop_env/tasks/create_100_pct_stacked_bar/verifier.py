#!/usr/bin/env python3
"""
Verifier for create_100_pct_stacked_bar task.

Verification Strategy:
1. File Verification (30 pts): Checks if 'Segment_Mix_Analysis.dva' was saved and modified during the task.
2. VLM Trajectory Verification (70 pts): 
   - Uses Visual Language Models to analyze trajectory frames.
   - Critical: Distinguish between a standard Stacked Bar (varied heights) and a 100% Stacked Bar (uniform full height).
   - Checks for correct axes (Region on X, Segment on Color) and Title.

We prioritize trajectory analysis because inspecting the proprietary .dva binary format is unreliable,
and visually confirming the "100%" nature of the chart is the core learning objective.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_100_pct_stacked_bar(traj, env_info, task_info):
    """
    Verifies that the agent created a 100% Stacked Bar Chart in Oracle Analytics Desktop.
    """
    # 1. Setup and Imports
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 2. File Verification (from container)
    # We read the JSON result produced by export_result.ps1
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In the env, the file is at C:\workspace\task_result.json
        # The copy_from_env function usually handles container paths. 
        # For Windows containers, paths might need care, but assuming standard docker cp behavior.
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        workbook_exists = result_data.get('workbook_exists', False)
        file_created = result_data.get('file_created_during_task', False)
        
        if workbook_exists:
            score += 15
            feedback_parts.append("Workbook file 'Segment_Mix_Analysis.dva' found.")
            
            if file_created:
                score += 15
                feedback_parts.append("Workbook was saved during the task session.")
            else:
                feedback_parts.append("Warning: Workbook file timestamp is old (pre-task).")
        else:
            feedback_parts.append("Workbook file 'Segment_Mix_Analysis.dva' NOT found.")
            
    except Exception as e:
        logger.error(f"Error reading task result: {e}")
        feedback_parts.append(f"Could not verify file status: {str(e)}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. VLM Verification (Visual Analysis)
    # This is the primary verification method for chart correctness
    
    # Sample frames to capture the workflow and final state
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return {"passed": False, "score": score, "feedback": "No visual evidence (screenshots) available."}

    # Prompt specifically designed to check for 100% stacked bar characteristics
    vlm_prompt = """
    You are an expert Data Analyst verifying a task in Oracle Analytics Desktop.
    
    The user was asked to create a "100% Stacked Bar Chart".
    
    Please analyze the provided screenshots (ordered chronologically) and determine:
    1. IS A BAR CHART VISIBLE? (Yes/No)
    2. IS IT A 100% STACKED CHART? 
       - Look at the tops of the bars. 
       - In a 100% Stacked chart, ALL bars must be exactly the same height and reach the top of the plot area (filling the 100% line).
       - If bars have different heights, it is a Standard Stacked Bar (WRONG).
    3. ARE THE DIMENSIONS CORRECT?
       - X-Axis should show Regions (e.g., East, West, Central, South).
       - Legend/Colors should show Customer Segments (e.g., Consumer, Corporate).
    4. IS THE TITLE CORRECT?
       - Should read "Customer Mix by Region".
       
    Return your response in JSON format:
    {
        "chart_visible": boolean,
        "is_100_percent_stacked": boolean,
        "dimensions_correct": boolean,
        "title_correct": boolean,
        "reasoning": "string explanation"
    }
    """
    
    vlm_response = query_vlm(
        images=frames, 
        prompt=vlm_prompt
    )
    
    # Parse VLM Result
    if vlm_response and 'result' in vlm_response:
        try:
            # Clean up potential markdown formatting in response
            content = vlm_response['result'].strip()
            if content.startswith('