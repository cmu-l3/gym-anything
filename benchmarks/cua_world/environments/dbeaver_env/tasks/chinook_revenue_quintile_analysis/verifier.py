#!/usr/bin/env python3
"""
Verifier for Chinook Revenue Quintile Analysis Task

Scoring Breakdown (100 pts total):
1. CSV Existence & Timestamp (10 pts)
   - File must exist and be created during the task.
2. CSV Structure & Format (15 pts)
   - Must be a valid CSV with correct headers (detected via content parsing).
   - Must have exactly 5 data rows.
3. Analytical Logic / Monotonicity (30 pts)
   - The revenue of Quintile 1 must be > Quintile 2 > ... > Quintile 5.
   - This proves the agent correctly sorted/ranked customers.
4. Data Accuracy (35 pts)
   - Quintile 1 Total Revenue matches ground truth (approx $880) within 5% tolerance.
   - This proves the aggregation logic was correct.
5. SQL Script (10 pts)
   - SQL file exists.

Pass Threshold: 70 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_revenue_quintile_analysis(traj, env_info, task_info):
    """Verify the revenue quintile analysis task."""
    
    # 1. Setup & Read Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

    # Extract metrics
    csv_exists = result.get("csv_exists", False)
    file_fresh = result.get("file_created_during_task", False)
    row_count = result.get("row_count", 0)
    q1_rev = result.get("q1_revenue", 0)
    q5_rev = result.get("q5_revenue", 0)
    is_monotonic = result.get("is_monotonic", False)
    sql_exists = result.get("sql_exists", False)
    gt_q1_rev = result.get("gt_q1_revenue", 0)

    score = 0
    feedback = []

    # Criterion 1: File Existence (10 pts)
    if csv_exists and file_fresh:
        score += 10
        feedback.append("CSV file exported successfully.")
    elif csv_exists:
        score += 5
        feedback.append("CSV file exists but timestamp suggests it wasn't created during this session.")
    else:
        feedback.append("Missing 'revenue_quintiles.csv' file.")

    # Criterion 2: Structure & Rows (15 pts)
    if row_count == 5:
        score += 15
        feedback.append("CSV contains exactly 5 quintile rows.")
    elif row_count > 0:
        score += 5
        feedback.append(f"CSV has {row_count} rows (expected 5).")
    else:
        feedback.append("CSV is empty or unreadable.")

    # Criterion 3: Monotonicity (30 pts)
    # Revenue should drop from Q1 to Q5
    if is_monotonic and q1_rev > q5_rev:
        score += 30
        feedback.append("Quintile segmentation logic appears correct (revenue decreases from Q1 to Q5).")
    else:
        feedback.append("Segmentation logic error: Revenue does not strictly decrease from Quintile 1 to 5. Did you sort correctly?")

    # Criterion 4: Accuracy (35 pts)
    # Check Q1 revenue against ground truth (tolerance 5%)
    # Q1 revenue is the most sensitive metric for correctness
    if gt_q1_rev > 0:
        diff = abs(q1_rev - gt_q1_rev)
        percent_error = (diff / gt_q1_rev) * 100
        
        if percent_error <= 5.0:
            score += 35
            feedback.append(f"Data accuracy verified (Q1 Revenue ${q1_rev:.2f} within 5% of ground truth).")
        elif percent_error <= 15.0:
            score += 15
            feedback.append(f"Data accuracy partial (Q1 Revenue ${q1_rev:.2f} is {percent_error:.1f}% off from ground truth).")
        else:
            feedback.append(f"Data accuracy failed: Q1 Revenue ${q1_rev:.2f} deviates significantly from expected ${gt_q1_rev:.2f}.")
    else:
        # Fallback if GT missing (shouldn't happen)
        if q1_rev > 800 and q1_rev < 1000:
            score += 35
            feedback.append("Data accuracy verified (heuristic).")

    # Criterion 5: SQL Script (10 pts)
    if sql_exists:
        score += 10
        feedback.append("SQL analysis script saved.")
    else:
        feedback.append("SQL script not found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }