#!/usr/bin/env python3
"""
Verifier for product_copurchase_affinity task.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_product_copurchase_affinity(traj, env_info, task_info):
    """
    Verify the implementation of the market basket analysis system.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Verification (Trajectory Check)
    # Ensure Azure Data Studio was actually used and SQL was written
    vlm_score = 0
    vlm_feedback = ""
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a user working in Azure Data Studio.
        1. Do you see SQL code being written or executed?
        2. Do you see a Results grid showing data?
        3. Do you see a 'Save as CSV' or export action?
        Respond with JSON: {"sql_visible": bool, "results_visible": bool, "export_visible": bool}
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_shot], prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('sql_visible'): vlm_score += 5
            if parsed.get('results_visible'): vlm_score += 5
            if parsed.get('export_visible'): vlm_score += 5
        except Exception:
            vlm_feedback = " (VLM analysis failed)"

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Database Objects (30 pts)
    if result.get('table_exists'):
        score += 8
        feedback.append("Table created.")
    else:
        feedback.append("Table missing.")

    if result.get('has_required_columns'):
        score += 12
        feedback.append("Table schema correct.")
    elif result.get('table_exists'):
        feedback.append("Table schema incorrect.")

    if result.get('proc_exists'):
        score += 10
        feedback.append("Stored Procedure created.")
    else:
        feedback.append("Stored Procedure missing.")
        
    if result.get('view_exists'):
        score += 8
        feedback.append("View created.")

    # Data Quality & Logic (40 pts)
    row_count = result.get('row_count', 0)
    if row_count >= 50:
        score += 10
        feedback.append(f"Data populated ({row_count} rows).")
    elif row_count > 0:
        score += 5
        feedback.append(f"Insufficient data ({row_count} rows).")
    else:
        feedback.append("Table empty.")

    if result.get('support_valid') and result.get('confidence_valid') and result.get('lift_valid'):
        score += 15
        feedback.append("Metrics (Support/Conf/Lift) in valid range.")
    else:
        feedback.append("Metrics contain invalid values.")

    if result.get('no_duplicate_pairs'):
        score += 7
        feedback.append("No duplicate pairs (A<B logic).")
    else:
        feedback.append("Duplicate pairs detected.")

    if result.get('view_filters_lift'):
        score += 5
        feedback.append("View correctly filters Lift > 1.0.")
        
    if result.get('view_returns_data'):
        score += 3

    # CSV Export (15 pts)
    if result.get('csv_exists'):
        score += 8
        feedback.append("CSV file exists.")
        
        csv_rows = result.get('csv_row_count', 0)
        if csv_rows == 15:
            score += 5
            feedback.append("CSV has exactly 15 rows.")
        else:
            feedback.append(f"CSV row count mismatch ({csv_rows} rows).")
            
        if result.get('csv_matches_db'):
            score += 5
            feedback.append("CSV content matches database.")
    else:
        feedback.append("CSV file missing.")

    # Add VLM Score
    score += vlm_score
    if vlm_feedback:
        feedback.append(vlm_feedback)

    # Final tally
    passed = (
        result.get('table_exists') and 
        result.get('proc_exists') and 
        row_count >= 50 and 
        score >= 70
    )

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }