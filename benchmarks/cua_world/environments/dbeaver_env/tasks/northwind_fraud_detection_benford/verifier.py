#!/usr/bin/env python3
"""
Verifier for northwind_fraud_detection_benford task.

Verifies:
1. DBeaver Connection 'Northwind' created.
2. SQL Script saved.
3. CSV Report saved and formatted correctly.
4. CSV Data accuracy (counts per digit match ground truth).
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_northwind_fraud_detection_benford(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result artifacts
    result_data = {}
    ground_truth = {}
    agent_data = {}

    try:
        # Load main result
        with tempfile.NamedTemporaryFile(suffix='.json') as f:
            copy_from_env("/tmp/benford_task_result.json", f.name)
            f.seek(0)
            result_data = json.load(f)

        # Load ground truth
        with tempfile.NamedTemporaryFile(suffix='.json') as f:
            copy_from_env(result_data.get('ground_truth_path'), f.name)
            f.seek(0)
            ground_truth = json.load(f)

        # Load extracted agent CSV data
        with tempfile.NamedTemporaryFile(suffix='.json') as f:
            copy_from_env(result_data.get('agent_data_path'), f.name)
            f.seek(0)
            agent_data = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result files: {str(e)}"}

    score = 0
    feedback = []
    
    # 1. Connection Check (10 pts)
    if result_data.get('connection_exists', False):
        score += 10
        feedback.append("DBeaver connection 'Northwind' confirmed.")
    else:
        feedback.append("Failed to create DBeaver connection 'Northwind'.")

    # 2. SQL Script Check (10 pts)
    if result_data.get('sql_exists', False):
        score += 10
        feedback.append("SQL script file found.")
    else:
        feedback.append("SQL script file missing.")

    # 3. CSV Existence & Structure (20 pts)
    csv_exists = result_data.get('csv_exists', False)
    csv_recent = result_data.get('csv_created_during_task', False)
    row_count = result_data.get('csv_row_count', 0)
    cols_valid = result_data.get('csv_columns_valid', False)

    if csv_exists and csv_recent:
        score += 10
        feedback.append("CSV output file created.")
        
        if row_count == 9:
            score += 5
            feedback.append("CSV has correct number of data rows (9).")
        else:
            feedback.append(f"CSV row count incorrect (found {row_count}, expected 9).")
            
        if cols_valid:
            score += 5
            feedback.append("CSV header columns look correct.")
    else:
        feedback.append("CSV output file missing or not created during task.")

    # 4. Data Accuracy (60 pts)
    # Compare agent's counts with ground truth counts
    
    gt_counts = ground_truth.get('digit_counts', {})
    
    if not agent_data or "error" in agent_data:
        feedback.append("Could not read data from CSV for verification.")
    else:
        matches = 0
        total_digits = 9
        total_error = 0
        
        for digit in range(1, 10):
            d_str = str(digit)
            gt_val = gt_counts.get(d_str, 0)
            agent_val = agent_data.get(d_str, 0)
            
            # Allow small tolerance (e.g. +/- 1) due to rounding differences in line total
            if abs(gt_val - agent_val) <= 1:
                matches += 1
            else:
                total_error += abs(gt_val - agent_val)
        
        # Scoring logic for accuracy
        if matches == 9:
            score += 60
            feedback.append("All digit counts match ground truth perfectly.")
        elif matches >= 7:
            score += 40
            feedback.append(f"Most digit counts match ({matches}/9). Error sum: {total_error}.")
        elif matches >= 5:
            score += 20
            feedback.append(f"Some digit counts match ({matches}/9). Error sum: {total_error}.")
        else:
            feedback.append(f"Data accuracy low. Only {matches}/9 digits matched ground truth.")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }