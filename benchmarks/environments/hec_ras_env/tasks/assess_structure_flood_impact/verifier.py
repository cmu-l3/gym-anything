#!/usr/bin/env python3
"""
Verifier for assess_structure_flood_impact task.
Compares agent's CSV output against a ground truth CSV generated from the actual HEC-RAS results.
"""

import json
import os
import tempfile
import csv
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assess_structure_flood_impact(traj, env_info, task_info):
    """
    Verify the flood impact assessment report.
    
    Criteria:
    1. Output CSV exists and was created during task (20 pts)
    2. Correct columns present (10 pts)
    3. Correct number of rows (10 pts)
    4. Interpolated WSE accuracy (25 pts)
    5. Flood Depth accuracy (25 pts)
    6. Status classification logic (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check existence
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file structure_impact_assessment.csv not found."}
    
    if not result_data.get("file_created_during_task", False):
        feedback_parts.append("Warning: Output file timestamp is older than task start.")
        # We don't fail immediately but penalize
    else:
        score += 20
        feedback_parts.append("Output file created successfully.")

    # 2. Load Agent CSV and Ground Truth CSV
    agent_csv_path = result_data.get("agent_file_path")
    gt_csv_path = result_data.get("ground_truth_path")
    
    temp_agent = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        copy_from_env(agent_csv_path, temp_agent.name)
        copy_from_env(gt_csv_path, temp_gt.name)
        
        with open(temp_agent.name, 'r') as f:
            agent_rows = list(csv.DictReader(f))
            agent_headers = agent_rows[0].keys() if agent_rows else []
            
        with open(temp_gt.name, 'r') as f:
            gt_rows = list(csv.DictReader(f))
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV files: {e}"}
    finally:
        if os.path.exists(temp_agent.name): os.unlink(temp_agent.name)
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    # Check Headers
    required_cols = ["Facility_Name", "River_Station", "FFE_ft", "Interpolated_Max_WSE_ft", "Flood_Depth_ft", "Status"]
    missing_cols = [col for col in required_cols if col not in agent_headers]
    
    if not missing_cols:
        score += 10
        feedback_parts.append("All required columns present.")
    else:
        feedback_parts.append(f"Missing columns: {', '.join(missing_cols)}")
        # If columns missing, unlikely to proceed
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check Row Count
    if len(agent_rows) == len(gt_rows):
        score += 10
        feedback_parts.append(f"Correct row count ({len(agent_rows)}).")
    else:
        feedback_parts.append(f"Row count mismatch: Expected {len(gt_rows)}, got {len(agent_rows)}.")

    # Compare Data
    # Align by Facility Name to handle potential sorting differences
    agent_dict = {row["Facility_Name"].strip(): row for row in agent_rows}
    gt_dict = {row["Facility_Name"].strip(): row for row in gt_rows}
    
    wse_correct_count = 0
    depth_correct_count = 0
    status_correct_count = 0
    total_items = len(gt_dict)
    
    tolerance = 0.05
    
    for fac_name, gt_row in gt_dict.items():
        if fac_name not in agent_dict:
            continue
            
        agent_row = agent_dict[fac_name]
        
        # Check WSE
        try:
            a_wse = float(agent_row["Interpolated_Max_WSE_ft"])
            g_wse = float(gt_row["Interpolated_Max_WSE_ft"])
            if abs(a_wse - g_wse) <= tolerance:
                wse_correct_count += 1
        except ValueError:
            pass
            
        # Check Depth
        try:
            a_depth = float(agent_row["Flood_Depth_ft"])
            g_depth = float(gt_row["Flood_Depth_ft"])
            if abs(a_depth - g_depth) <= tolerance:
                depth_correct_count += 1
        except ValueError:
            pass
            
        # Check Status
        if agent_row["Status"].strip().upper() == gt_row["Status"].strip().upper():
            status_correct_count += 1

    # Calculate subscores
    if total_items > 0:
        score += 25 * (wse_correct_count / total_items)
        score += 25 * (depth_correct_count / total_items)
        score += 10 * (status_correct_count / total_items)
        
        feedback_parts.append(f"WSE Accuracy: {wse_correct_count}/{total_items}")
        feedback_parts.append(f"Depth Accuracy: {depth_correct_count}/{total_items}")
        feedback_parts.append(f"Status Logic: {status_correct_count}/{total_items}")
    else:
        feedback_parts.append("No matching facilities found to compare.")

    passed = score >= 70 and wse_correct_count == total_items
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }