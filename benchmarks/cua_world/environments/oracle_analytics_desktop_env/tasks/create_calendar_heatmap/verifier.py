#!/usr/bin/env python3
"""
Verifier for create_calendar_heatmap task in Oracle Analytics Desktop.

Verification Strategy:
1. File Verification (30%): Checks if 'Seasonal_Patterns.dva' was created.
2. VLM Verification (70%):
   - Heatmap Structure: Grid layout with Months and Days.
   - Sorting (CRITICAL): Checks if Months/Days are sorted Chronologically vs Alphabetically.
   - Canvas Name: Checks for 'Staffing Analysis'.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calendar_heatmap(traj, env_info, task_info):
    """
    Verify the Calendar Heatmap creation and sorting.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. File & Application State Verification
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Path corresponds to where export_result.ps1 saved it
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Check file creation (20 pts)
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists and created_during:
        score += 20
        feedback_parts.append("Workbook saved successfully")
    elif output_exists:
        score += 10
        feedback_parts.append("Workbook exists but timestamp is old")
    else:
        feedback_parts.append("Workbook 'Seasonal_Patterns' not found")

    # Check app state (10 pts)
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("Oracle Analytics is running")

    # ================================================================
    # 2. VLM Verification (Visual & Sorting)
    # ================================================================
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " | No screenshots available"
        }

    # Prompt focuses on the Sorting Logic which is the main difficulty
    vlm_prompt = """
    You are evaluating an Oracle Analytics Desktop task.
    The user was asked to create a 'Calendar Heatmap' showing Sales by Month and Day of Week.
    
    Analyze the final screenshot provided.
    
    1. VISUALIZATION_TYPE: Is there a Heatmap/Grid visualization visible? (A matrix of colored rectangles).
    2. AXES_LABELS: Are the axes labeled with Months (Jan, Feb...) and Days (Mon, Tue...)?
    3. CANVAS_NAME: Is the active tab/canvas named 'Staffing Analysis'?
    
    4. SORT_ORDER (CRITICAL): 
       - Look closely at the Month labels. Are they sorted Chronologically (Jan, Feb, Mar, Apr...)?
       - OR are they sorted Alphabetically (Apr, Aug, Dec, Feb...)? 
       - Look closely at the Day labels. Are they Mon, Tue, Wed...? Or Fri, Mon, Sat...?
       
    Respond in JSON:
    {
        "has_heatmap": true/false,
        "has_month_day_axes": true/false,
        "canvas_name_correct": true/false,
        "month_sort_chronological": true/false,
        "day_sort_chronological": true/false,
        "reasoning": "Explain what you see regarding sort order"
    }
    """
    
    vlm_result = query_vlm(
        prompt=vlm_prompt,
        image=final_screenshot,
        images=frames  # Include trajectory for context
    )
    
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        # Heatmap exists (20 pts)
        if parsed.get('has_heatmap', False):
            score += 20
            feedback_parts.append("Heatmap created")
        else:
            feedback_parts.append("No heatmap visible")
            
        # Axes correct (10 pts)
        if parsed.get('has_month_day_axes', False):
            score += 10
        else:
            feedback_parts.append("Axes missing Month/Day labels")
            
        # Canvas name (10 pts)
        if parsed.get('canvas_name_correct', False):
            score += 10
            feedback_parts.append("Canvas named 'Staffing Analysis'")
            
        # Sorting (30 pts) - The "Hard" part
        month_sorted = parsed.get('month_sort_chronological', False)
        day_sorted = parsed.get('day_sort_chronological', False)
        
        if month_sorted and day_sorted:
            score += 30
            feedback_parts.append("Data correctly sorted chronologically")
        elif month_sorted or day_sorted:
            score += 15
            feedback_parts.append("Partial sorting success (one axis correct)")
        else:
            feedback_parts.append("Sorting appears Alphabetical (Task Failed: Chronological sort required)")
            
    else:
        feedback_parts.append("VLM verification failed")

    # ================================================================
    # Final Scoring
    # ================================================================
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }