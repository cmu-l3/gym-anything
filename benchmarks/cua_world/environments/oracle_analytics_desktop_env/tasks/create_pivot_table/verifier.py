#!/usr/bin/env python3
"""
Verifier for create_pivot_table task in Oracle Analytics Desktop.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_pivot_table(traj, env_info, task_info):
    """
    Verifies that the agent created a Pivot Table with correct dimensions and title.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from container
    # The export script runs in Windows and saves to C:\workspace\tasks\...\task_result.json
    # In the container mapping, this might be accessible via the mapped volume or copy_from_env
    # Assuming standard path mapping for the agent environment
    
    result_path = "C:\\workspace\\tasks\\create_pivot_table\\task_result.json"
    # Linux-side path depends on how Docker mounts it. Assuming copy_from_env handles the path.
    # If the env is Windows, copy_from_env usually abstracts the path format.
    
    score = 0
    feedback_parts = []
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Adjust path separators if needed for the specific env implementation
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result = {}
        feedback_parts.append("Could not retrieve task verification data")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. File-based Verification (40 points)
    file_exists = result.get("file_exists", False)
    file_fresh = result.get("file_created_after_start", False)
    internal_keyword = result.get("internal_pivot_keyword_found", False)
    internal_title = result.get("internal_title_found", False)
    
    if file_exists:
        score += 10
        feedback_parts.append("Workbook file saved")
        
        if file_fresh:
            score += 10
            feedback_parts.append("New file created")
        else:
            feedback_parts.append("File timestamp indicates old file")
            
        if internal_keyword:
            score += 10
            feedback_parts.append("Pivot table metadata found in file")
        else:
            feedback_parts.append("Pivot table structure not detected in file")
            
        if internal_title:
            score += 10
            feedback_parts.append("Correct title found in file metadata")
        else:
            feedback_parts.append("Title mismatch in file metadata")
    else:
        feedback_parts.append("Output file 'Logistics_Revenue_Pivot.dva' not found")

    # 3. VLM Verification (60 points)
    # Analyze trajectory to confirm visual structure of a Pivot Table
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_parts.append("No trajectory frames available for VLM")
    else:
        prompt = """
        You are verifying an Oracle Analytics Desktop task.
        The user was asked to create a 'Pivot Table' showing Revenue by Product Category (rows) and Customer Segment (columns).
        
        Examine the screenshots. Look for:
        1. A visualization that looks like a grid/matrix (Pivot Table), NOT a bar chart or simple list.
        2. Row headers showing Product Categories (e.g., 'Furniture', 'Technology').
        3. Column headers showing Customer Segments (e.g., 'Consumer', 'Corporate').
        4. Numeric values in the grid cells.
        5. The title "Revenue by Category and Segment" visible on the visualization.
        
        Return JSON:
        {
            "is_pivot_table": true/false,
            "has_correct_rows": true/false,
            "has_correct_columns": true/false,
            "has_title": true/false,
            "confidence": 0-10
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('is_pivot_table', False):
                score += 20
                feedback_parts.append("VLM confirmed Pivot Table visualization")
            else:
                feedback_parts.append("VLM did not see a Pivot Table")
                
            if parsed.get('has_correct_rows', False) and parsed.get('has_correct_columns', False):
                score += 20
                feedback_parts.append("VLM confirmed correct Row/Column dimensions")
            
            if parsed.get('has_title', False):
                score += 20
                feedback_parts.append("VLM confirmed visualization title")
        else:
            feedback_parts.append("VLM verification failed to process images")

    # Final scoring
    passed = score >= 60 and file_exists and internal_keyword
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }