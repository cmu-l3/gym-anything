#!/usr/bin/env python3
"""
Verifier for create_trellis_profit task (Oracle Analytics Desktop).

Verification Strategy:
1. File Verification (Secondary):
   - Check if 'Trellis_Profit_Analysis.dva' exists and was saved during the task.
   - Prevents "do nothing" gaming.

2. VLM Trajectory Verification (Primary):
   - Examine trajectory frames to confirm the specific Trellis visualization was built.
   - The .dva file format is complex/binary, so visual inspection of the grid layout is the most robust method.
   - Checks for:
     a) Grid layout (small multiples)
     b) Row headers (Region)
     c) Column headers (Product Category)
     d) Chart type (Line)

Pass Threshold: 60 points + Trellis Grid Visible
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_trellis_profit(traj, env_info, task_info):
    """
    Verify the creation of a Trellis Line Chart in Oracle Analytics Desktop.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. FILE-BASED VERIFICATION (30 Points)
    # ================================================================
    file_score = 0
    feedback_parts = []
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # PowerShell script saves to this specific path in the Windows VM
        # Note: The path inside the VM is C:\Users\Docker\AppData\Local\Temp\task_result.json
        # The copy_from_env might need the mapped path. Assuming standard mapping.
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        # If file missing, result is default fail
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check file existence
    if result.get('file_exists'):
        file_score += 10
        feedback_parts.append("Project file saved.")
        
        # Check timestamp (anti-gaming)
        if result.get('file_created_during_task'):
            file_score += 10
            feedback_parts.append("File created during task.")
        else:
            feedback_parts.append("File timestamp predates task (stale data).")
            
        # Check file size (empty file check)
        if result.get('file_size_bytes', 0) > 1000: # Arbitrary small threshold
            file_score += 10
        else:
            feedback_parts.append("File seems empty/corrupt.")
    else:
        feedback_parts.append("Project file 'Trellis_Profit_Analysis' not found.")

    # ================================================================
    # 2. VLM TRAJECTORY VERIFICATION (70 Points)
    # ================================================================
    vlm_score = 0
    
    # Sample frames to catch the workflow
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return {"passed": False, "score": file_score, "feedback": "No trajectory frames available."}

    prompt = """
    You are verifying an Oracle Analytics Desktop task. The user must create a "Trellis" (Small Multiples) Line Chart.
    
    Look at the provided screenshots of the application.
    
    I need to verify four specific things:
    1. **Trellis Grid Layout**: Do you see a grid of multiple small charts arranged in rows and columns? (Not just a single big chart).
    2. **Row Dimension**: Are the rows labeled with Regions (e.g., Central, East, South, West)?
    3. **Column Dimension**: Are the columns labeled with Product Categories (e.g., Furniture, Office Supplies, Technology)?
    4. **Chart Type**: Are the small charts Line charts (continuous lines)?
    
    Respond in JSON format:
    {
        "trellis_grid_visible": true/false,
        "region_rows_visible": true/false,
        "category_columns_visible": true/false,
        "line_chart_visible": true/false,
        "confidence": "low/medium/high",
        "reasoning": "brief explanation"
    }
    """
    
    vlm_response = query_vlm(images=frames, prompt=prompt)
    
    if vlm_response and vlm_response.get('success'):
        parsed = vlm_response.get('parsed', {})
        logger.info(f"VLM Analysis: {parsed}")
        
        # Scoring logic
        if parsed.get('trellis_grid_visible'):
            vlm_score += 30
            feedback_parts.append("Trellis grid layout confirmed.")
        else:
            feedback_parts.append("Trellis grid layout NOT visible.")

        if parsed.get('region_rows_visible'):
            vlm_score += 15
            feedback_parts.append("Region rows verified.")
        else:
            feedback_parts.append("Region rows missing/incorrect.")

        if parsed.get('category_columns_visible'):
            vlm_score += 15
            feedback_parts.append("Category columns verified.")
        else:
            feedback_parts.append("Category columns missing/incorrect.")
            
        if parsed.get('line_chart_visible'):
            vlm_score += 10
            feedback_parts.append("Line chart type confirmed.")
        else:
            feedback_parts.append("Wrong chart type (not line).")
            
    else:
        feedback_parts.append("VLM verification failed to process images.")

    # ================================================================
    # FINAL SCORING
    # ================================================================
    total_score = file_score + vlm_score
    
    # Critical criteria: Must have saved the file AND created a trellis grid
    # If the file exists but VLM sees no grid, it's likely a fail (wrong chart).
    # If VLM sees grid but file not saved, partial credit but fail.
    
    trellis_confirmed = vlm_response.get('parsed', {}).get('trellis_grid_visible', False) if vlm_response else False
    
    passed = (total_score >= 60) and trellis_confirmed and result.get('file_exists')
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }