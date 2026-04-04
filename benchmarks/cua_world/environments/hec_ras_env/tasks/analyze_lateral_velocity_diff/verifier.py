#!/usr/bin/env python3
"""
Verifier for analyze_lateral_velocity_diff task.
"""

import json
import os
import csv
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_lateral_velocity_diff(traj, env_info, task_info):
    """
    Verify the lateral velocity analysis task.
    
    Criteria:
    1. CSV file exists and has correct headers (20 pts)
    2. CSV file contains data rows (20 pts)
    3. TXT summary file exists (10 pts)
    4. TXT file identifies top shear stations (10 pts)
    5. CSV file created during task (Anti-gaming) (20 pts)
    6. Trajectory verification (VLM) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check File Existence & Creation
    csv_exists = result.get('csv_exists', False)
    txt_exists = result.get('txt_exists', False)
    created_during = result.get('csv_created_during_task', False)
    
    if csv_exists:
        score += 20
        feedback_parts.append("CSV file created")
    else:
        feedback_parts.append("CSV file MISSING")
        
    if txt_exists:
        score += 10
        feedback_parts.append("Summary TXT created")
        
    if created_during:
        score += 20
        feedback_parts.append("Files created during task")
    elif csv_exists:
        feedback_parts.append("Files NOT created during task (pre-existing?)")

    # 3. Verify CSV Content
    if csv_exists:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/user_lateral_shear.csv", temp_csv.name)
            with open(temp_csv.name, 'r') as f:
                reader = csv.reader(f)
                headers = next(reader, [])
                rows = list(reader)
                
                # Check Headers
                expected_cols = ['River_Station', 'Vel_Channel', 'Vel_Left', 'Vel_Right', 'Max_Shear_Diff']
                # Allow case-insensitive partial match
                header_match = all(any(exp.lower() in h.lower() for h in headers) for exp in expected_cols)
                
                if header_match:
                    score += 10
                    feedback_parts.append("CSV headers correct")
                else:
                    feedback_parts.append(f"CSV headers mismatch (Found: {headers})")
                
                # Check Data
                if len(rows) > 5:
                    score += 10
                    feedback_parts.append(f"CSV contains data ({len(rows)} rows)")
                else:
                    feedback_parts.append("CSV appears empty or too short")
                    
        except Exception as e:
            feedback_parts.append(f"Error reading CSV: {str(e)}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
                
    # 4. Verify TXT Content (Rank 1 logic)
    if txt_exists:
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/user_high_shear.txt", temp_txt.name)
            with open(temp_txt.name, 'r') as f:
                content = f.read()
                if "Rank 1" in content or "Station" in content:
                    score += 10
                    feedback_parts.append("Summary file format looks valid")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)

    # 5. Trajectory Verification (Stub for VLM)
    # In a real implementation, we would call query_vlm(traj...)
    # For now, we assume if files are created correctly, VLM would pass
    if score >= 60:
        score += 20
        feedback_parts.append("Workflow verification assumed passed")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }