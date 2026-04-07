#!/usr/bin/env python3
"""
Verifier for Oracle Analytics Desktop task: Segment Customers by Sales.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_segment_customers(traj, env_info, task_info):
    """
    Verify the customer segmentation task using File Checks and VLM.
    
    Criteria:
    1. Output DVA file exists and was created during task (25 pts)
    2. DVA file contains evidence of "Gold", "Silver", "Bronze" logic (20 pts)
    3. VLM: Bar chart is visible (15 pts)
    4. VLM: Customer Tier segments are visible (15 pts)
    5. VLM: Sorting is correct (Bronze -> Silver -> Gold) (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. File Verification (from export_result.ps1)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Score File Checks
    if result.get('output_exists'):
        if result.get('file_created_during_task'):
            score += 25
            feedback_parts.append("Project saved successfully.")
        else:
            score += 10
            feedback_parts.append("Project file exists but timestamp suggests it wasn't created now.")
    else:
        feedback_parts.append("Project file 'Customer_Segmentation_Analysis.dva' not found.")

    if result.get('tiers_found_in_file'):
        score += 20
        feedback_parts.append("Segmentation logic (Gold/Silver/Bronze) found in project file.")
    elif result.get('output_exists'):
        feedback_parts.append("Project saved, but couldn't verify segmentation keywords in file.")

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if not final:
        feedback_parts.append("No screenshots available for verification.")
    else:
        # Prompt for Visual Analysis
        prompt = """
        You are verifying an Oracle Analytics Desktop task.
        The user was asked to create a Bar Chart of Customer Counts by 'Customer Tier' (Gold, Silver, Bronze).
        
        Look at the final screenshot (and trajectory history).
        1. Is there a Bar Chart visible?
        2. Do the bars represent 'Gold', 'Silver', and 'Bronze'?
        3. CHECK THE SORT ORDER CAREFULLY:
           - Correct: Bronze -> Silver -> Gold (Ascending value: <1k, 1k-5k, >5k)
           - Correct: Gold -> Silver -> Bronze (Descending value)
           - Incorrect: Bronze -> Gold -> Silver (Alphabetical sorting, which is the default/wrong)
           
        Return JSON:
        {
            "bar_chart_visible": boolean,
            "segments_visible": boolean,
            "sort_order": "logical" | "alphabetical" | "random" | "unknown",
            "feedback": "string explaining what you see"
        }
        """
        
        vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_resp and vlm_resp.get('parsed'):
            parsed = vlm_resp['parsed']
            
            if parsed.get('bar_chart_visible'):
                score += 15
                feedback_parts.append("VLM confirmed Bar Chart presence.")
            else:
                feedback_parts.append("VLM did not see a bar chart.")
                
            if parsed.get('segments_visible'):
                score += 15
                feedback_parts.append("VLM confirmed Gold/Silver/Bronze segments.")
            else:
                feedback_parts.append("VLM did not see the specific tiers (Gold/Silver/Bronze).")
                
            sort_order = parsed.get('sort_order', 'unknown')
            if sort_order == 'logical':
                score += 25
                feedback_parts.append("VLM confirmed logical sort order (Bronze-Silver-Gold).")
            elif sort_order == 'alphabetical':
                feedback_parts.append("VLM detected Alphabetical sorting (Bronze-Gold-Silver). Logic sort was required.")
            else:
                feedback_parts.append(f"VLM could not determine logical sort order. Observed: {sort_order}")
                
            if parsed.get('feedback'):
                feedback_parts.append(f"VLM Note: {parsed['feedback']}")

    # Pass logic
    passed = score >= 70  # Requires most steps to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }