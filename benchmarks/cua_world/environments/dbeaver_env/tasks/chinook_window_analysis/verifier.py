#!/usr/bin/env python3
"""
Verifier for Chinook Monthly Revenue Window Analysis.

Scoring Breakdown (100 points):
1. Connection (10 pts): DBeaver connected to 'Chinook'.
2. SQL Script (10 pts): File exists and contains window function keywords.
3. CSV Structure (15 pts): File exists with correct headers and fresh timestamp.
4. Data Accuracy (65 pts):
   - Row count matches (5 pts)
   - Monthly Revenue matches (15 pts) - proves basic aggregation
   - MoM Growth matches (15 pts) - proves LAG and calculation
   - Moving Avg matches (15 pts) - proves window frame
   - Year Rank matches (15 pts) - proves PARTITION BY
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_window_analysis(traj, env_info, task_info):
    """
    Verify the window function analysis task.
    Relies on detailed data verification performed in export_result.sh.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Connection Check (10 pts)
    if result.get('connection_found'):
        if result.get('connection_name') == 'Chinook':
            score += 10
            feedback.append("DBeaver connection 'Chinook' verified.")
        else:
            score += 5
            feedback.append(f"Connection found but named '{result.get('connection_name')}' (expected 'Chinook').")
    else:
        feedback.append("No DBeaver connection found for Chinook DB.")

    # 2. SQL Script Check (10 pts)
    if result.get('sql_exists'):
        if result.get('sql_valid'):
            score += 10
            feedback.append("SQL script found with valid window function syntax.")
        else:
            score += 5
            feedback.append("SQL script found but missing window function keywords.")
    else:
        feedback.append("SQL script not saved.")

    # 3. CSV Existence & Structure (15 pts)
    verification = result.get('verification', {})
    
    if result.get('csv_exists'):
        if not result.get('csv_fresh'):
            feedback.append("Warning: CSV file timestamp predates task start.")
        
        if verification.get('headers_match'):
            score += 15
            feedback.append("CSV exported with correct columns.")
        else:
            score += 5
            feedback.append("CSV exists but headers do not match requirements.")
    else:
        feedback.append("Results CSV not exported.")
        # If CSV is missing, data checks will fail
        return {
            "passed": False,
            "score": score,
            "feedback": " ".join(feedback),
            "details": result
        }

    # 4. Data Accuracy (65 pts)
    # Row Count (5 pts)
    if verification.get('row_count_match'):
        score += 5
    else:
        feedback.append("Row count mismatch.")

    # We use a threshold of 0.9 (90% match) for data accuracy to allow for minor anomalies
    # Revenue (15 pts)
    rev_acc = verification.get('revenue_accuracy', 0)
    if rev_acc > 0.9:
        score += 15
    elif rev_acc > 0.5:
        score += 7
        feedback.append(f"Revenue accuracy partial ({rev_acc:.0%}).")
    else:
        feedback.append("Revenue calculations incorrect.")

    # Growth (15 pts) - LAG test
    growth_acc = verification.get('growth_accuracy', 0)
    if growth_acc > 0.9:
        score += 15
    elif growth_acc > 0.5:
        score += 7
        feedback.append(f"Growth calculation partial ({growth_acc:.0%}).")
    else:
        feedback.append("Month-over-Month growth calculations incorrect.")

    # Moving Avg (15 pts) - Window Frame test
    ma_acc = verification.get('moving_avg_accuracy', 0)
    if ma_acc > 0.9:
        score += 15
    elif ma_acc > 0.5:
        score += 7
        feedback.append(f"Moving average partial ({ma_acc:.0%}).")
    else:
        feedback.append("Moving average calculations incorrect.")

    # Rank (15 pts) - Partition test
    rank_acc = verification.get('rank_accuracy', 0)
    if rank_acc > 0.9:
        score += 15
    elif rank_acc > 0.5:
        score += 7
        feedback.append(f"Ranking partial ({rank_acc:.0%}).")
    else:
        feedback.append("Yearly ranking incorrect.")

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "rev_accuracy": rev_acc,
            "growth_accuracy": growth_acc,
            "ma_accuracy": ma_acc
        }
    }