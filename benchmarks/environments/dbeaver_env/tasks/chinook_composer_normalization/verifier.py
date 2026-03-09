#!/usr/bin/env python3
"""
Verifier for chinook_composer_normalization task.

Evaluates:
1. Database Schema (Tables, PKs/FKs created) - 30 pts
2. Data Normalization Quality (Parsing accuracy, Counts) - 30 pts
3. View Creation - 10 pts
4. Exported Data Accuracy - 15 pts
5. Connection & SQL Script - 15 pts

Pass Threshold: 60/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_composer_normalization(traj, env_info, task_info):
    """
    Verifies that the agent correctly normalized the Composer field.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Ground Truth Data
    gt = data.get("ground_truth", {})
    exp_comp_count = gt.get("expected_composer_count", 0)
    exp_bridge_count = gt.get("expected_bridge_count", 0)
    
    # --- 1. Connection & Setup (10 pts) ---
    if data.get("connection_exists"):
        score += 10
        feedback.append("DBeaver connection confirmed.")
    else:
        feedback.append("DBeaver connection 'ChinookNormalize' not found.")

    # --- 2. Schema Structure (20 pts) ---
    has_composers = data.get("has_composers_table", False)
    has_bridge = data.get("has_bridge_table", False)
    
    if has_composers:
        score += 10
        feedback.append("Table 'composers' exists.")
    else:
        feedback.append("Missing table 'composers'.")
        
    if has_bridge:
        score += 10
        feedback.append("Table 'track_composers' exists.")
    else:
        feedback.append("Missing table 'track_composers'.")

    # --- 3. Normalization Data Quality (30 pts) ---
    # Only evaluate if tables exist
    if has_composers and has_bridge:
        # Composer Count Accuracy (10 pts)
        # Allow +/- 10% tolerance for different splitting logic handling
        act_comp = data.get("composers_count", 0)
        if exp_comp_count > 0:
            diff_pct = abs(act_comp - exp_comp_count) / exp_comp_count
            if diff_pct < 0.1:
                score += 10
                feedback.append(f"Composer count accurate ({act_comp}).")
            elif diff_pct < 0.25:
                score += 5
                feedback.append(f"Composer count acceptable ({act_comp}, expected ~{exp_comp_count}).")
            else:
                feedback.append(f"Composer count deviates significantly ({act_comp} vs {exp_comp_count}).")
        
        # Bridge Count Accuracy (10 pts)
        act_bridge = data.get("bridge_count", 0)
        if exp_bridge_count > 0:
            diff_pct = abs(act_bridge - exp_bridge_count) / exp_bridge_count
            if diff_pct < 0.1:
                score += 10
                feedback.append(f"Bridge table count accurate ({act_bridge}).")
            elif diff_pct < 0.25:
                score += 5
                feedback.append(f"Bridge table count acceptable.")
            else:
                feedback.append(f"Bridge table count deviation ({act_bridge} vs {exp_bridge_count}).")

        # Referential Integrity (10 pts)
        orphans = data.get("orphaned_refs", 0)
        if orphans == 0 and act_bridge > 0:
            score += 10
            feedback.append("Referential integrity maintained (no orphans).")
        elif orphans > 0:
            feedback.append(f"Found {orphans} orphaned references in bridge table.")

    # --- 4. View Creation (10 pts) ---
    if data.get("has_view", False):
        view_rows = data.get("view_rows", 0)
        if view_rows > 0:
            score += 10
            feedback.append("View 'v_track_composers' created and functional.")
        else:
            score += 5
            feedback.append("View created but returned 0 rows or query failed.")
    else:
        feedback.append("View 'v_track_composers' missing.")

    # --- 5. Exported Data (25 pts) ---
    if data.get("csv_exists", False):
        score += 10
        feedback.append("CSV file exported.")
        
        # Check content match
        csv_top_row = data.get("csv_top_row", [])
        gt_top_name = gt.get("top_composer_name", "")
        
        # Simple fuzzy check: does the top composer name appear in the first row?
        match = False
        if csv_top_row:
            row_str = " ".join(csv_top_row).lower()
            if gt_top_name.lower() in row_str:
                match = True
        
        if match:
            score += 15
            feedback.append(f"CSV data validated (Top composer: {gt_top_name}).")
        else:
            feedback.append(f"CSV top row mismatch. Expected top composer '{gt_top_name}'.")
    else:
        feedback.append("Exported CSV file not found.")

    # --- 6. SQL Script (5 pts) ---
    if data.get("sql_exists", False) and data.get("sql_size", 0) > 100:
        score += 5
        feedback.append("SQL script saved.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }