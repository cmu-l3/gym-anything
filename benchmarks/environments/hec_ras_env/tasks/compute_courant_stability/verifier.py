#!/usr/bin/env python3
"""
Verifier for compute_courant_stability task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_courant_stability(traj, env_info, task_info):
    """
    Verify the Courant number analysis.
    
    Criteria:
    1. CSV output exists and has correct columns (20 pts)
    2. Data volume (at least 5 rows) (10 pts)
    3. Values are physically reasonable (Vel > 0, C > 0) (10 pts)
    4. Internal Calculation Consistency (C = V*dt/dx) (30 pts)
       - Checked by verifying the implied timestep is constant across rows
    5. Report exists and summarizes data (20 pts)
    6. Files created during task (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    validation = result.get("validation", {})
    task_start = result.get("task_start", 0)
    
    score = 0
    feedback = []
    
    # 1. CSV Existence and Columns (20 pts)
    if validation.get("csv_exists"):
        if validation.get("columns_correct"):
            score += 20
            feedback.append("CSV exists with correct columns.")
        else:
            score += 5
            feedback.append("CSV exists but missing required columns.")
    else:
        feedback.append("CSV file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Data Volume (10 pts)
    rows = validation.get("csv_rows", 0)
    if rows >= 5:
        score += 10
        feedback.append(f"Data volume good ({rows} rows).")
    else:
        feedback.append(f"Insufficient data rows ({rows}).")

    # 3. Reasonable Values (10 pts)
    v_stats = validation.get("velocity_stats", {})
    c_stats = validation.get("courant_stats", {})
    if v_stats.get("max", 0) > 0 and c_stats.get("max", 0) > 0:
        score += 10
        feedback.append("Values appear within physical ranges.")
    else:
        feedback.append("Values appear invalid (zeros or negative).")

    # 4. Consistency Check (30 pts)
    # The validation script calculates if dt is consistent across rows
    consistency = validation.get("internal_consistency", 0.0)
    if consistency > 0.9:
        score += 30
        feedback.append("Courant calculation is mathematically consistent across cross-sections.")
    elif consistency > 0.5:
        score += 15
        feedback.append("Courant calculation has some inconsistencies.")
    else:
        feedback.append("Courant numbers do not match Velocity/DeltaX relationship (inconsistent dt).")

    # 5. Report Existence (20 pts)
    if validation.get("report_exists"):
        content = validation.get("report_content", {})
        if content.get("has_max") and content.get("has_stable"):
            score += 20
            feedback.append("Report exists and contains required stability assessment.")
        else:
            score += 10
            feedback.append("Report exists but missing key summary items.")
    else:
        feedback.append("Summary report not found.")

    # 6. Anti-gaming (10 pts)
    csv_mtime = validation.get("csv_mtime", 0)
    if csv_mtime > task_start:
        score += 10
    else:
        feedback.append("File timestamp indicates it was not created during this task.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }