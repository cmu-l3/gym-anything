#!/usr/bin/env python3
"""
Verifier for product_catalog_json_layer task.
Scoring:
- Database Objects (40 pts)
- JSON Export File (30 pts)
- Data Import Verification (30 pts)
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_product_catalog_json_layer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Database Objects (40 pts)
    if result.get('export_proc_exists'):
        score += 10
        feedback_parts.append("Export Proc Created (+10)")
    else:
        feedback_parts.append("Export Proc Missing")

    if result.get('import_proc_exists'):
        score += 10
        feedback_parts.append("Import Proc Created (+10)")
    else:
        feedback_parts.append("Import Proc Missing")

    if result.get('staging_table_exists'):
        score += 10
        feedback_parts.append("Staging Table Created (+10)")
        
        # Check columns
        cols_count = result.get('columns_found_count', 0)
        if cols_count >= 6:
            score += 10
            feedback_parts.append("Table Schema Correct (+10)")
        elif cols_count >= 4:
            score += 5
            feedback_parts.append("Table Schema Partial (+5)")
    else:
        feedback_parts.append("Staging Table Missing")

    # 2. JSON Export File (30 pts)
    if result.get('file_exists'):
        score += 5
        feedback_parts.append("File Exists (+5)")
        
        if result.get('is_valid_json'):
            score += 5
            feedback_parts.append("Valid JSON (+5)")
            
            if result.get('contains_bikes'):
                score += 10
                feedback_parts.append("Contains 'Bikes' Data (+10)")
            
            if result.get('has_nested_structure'):
                score += 10
                feedback_parts.append("Correct Nested Structure (+10)")
            else:
                feedback_parts.append("Flat/Incorrect JSON Structure")
    else:
        feedback_parts.append("Export File Missing")

    # 3. Data Import Verification (30 pts)
    row_count = result.get('staging_row_count', 0)
    data_valid = result.get('staging_data_valid', False)
    
    if row_count == 5:
        score += 15
        feedback_parts.append("Correct Row Count (5) (+15)")
    elif row_count > 0:
        score += 5
        feedback_parts.append(f"Partial Row Count ({row_count}) (+5)")
    else:
        feedback_parts.append("No Data Imported")
        
    if data_valid:
        score += 15
        feedback_parts.append("Data Content Verified (+15)")
    
    # VLM Verification (Bonus/Tie-breaker check)
    # Check if code editor was used
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_scr = get_final_screenshot(traj)
        if final_scr:
            frames.append(final_scr)
            
        vlm_res = query_vlm(
            images=frames,
            prompt="Does the user appear to be writing SQL code or executing queries in Azure Data Studio? Answer yes or no."
        )
        if vlm_res.get('success') and 'yes' in str(vlm_res.get('parsed', '')).lower():
            feedback_parts.append("(VLM Verified SQL Editing)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }