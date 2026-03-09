#!/usr/bin/env python3
"""
Verifier for bem_characteristic_tsr_sweep task.
"""

import json
import tempfile
import os
import re
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bem_characteristic_tsr_sweep(traj, env_info, task_info):
    """
    Verify the agent successfully ran a BEM TSR Sweep and exported valid data.
    
    Criteria:
    1. Output file exists and was created during task (Anti-gaming).
    2. File contains tabular numeric data.
    3. Data covers the requested TSR range (1 to 10).
    4. Data contains physically plausible Cp values (Power Coefficient).
    5. Sufficient data points (at least 15 for a step of 0.5).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not verify: Result metadata missing."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence and Timing (20 pts)
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Result file not found at expected path."}
    
    if not task_result.get("file_created_during_task", False):
        feedback_parts.append("File timestamp indicates it was not created during this task session.")
        # We continue but penalty applies
    else:
        score += 20
        feedback_parts.append("File created successfully.")

    # 3. Retrieve and Parse Output File Content
    output_path = task_result.get("output_path", "/home/ga/Documents/projects/cp_tsr_results.txt")
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env(output_path, temp_txt.name)
        with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output file: {e}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    # Parse tabular data
    lines = content.strip().splitlines()
    data_rows = []
    
    for line in lines:
        # Skip comments or empty lines
        if not line.strip() or line.strip().startswith(('#', '%', '//', 'TSR')):
            continue
            
        # Split by whitespace or comma
        parts = re.split(r'[,\s\t]+', line.strip())
        try:
            # Try to convert to floats
            nums = [float(p) for p in parts if p]
            if len(nums) >= 2:
                data_rows.append(nums)
        except ValueError:
            continue

    num_rows = len(data_rows)
    
    # 4. Check Data Quantity (20 pts)
    # Requested: TSR 1 to 10 step 0.5 -> ~19 points
    if num_rows >= 15:
        score += 20
        feedback_parts.append(f"Sufficient data points found ({num_rows}).")
    elif num_rows >= 5:
        score += 10
        feedback_parts.append(f"Some data found, but fewer than expected ({num_rows} < 15).")
    else:
        feedback_parts.append(f"Insufficient data rows ({num_rows}).")

    # 5. Analyze Data Content (TSR and Cp) (60 pts)
    if num_rows > 0:
        # We need to identify columns. 
        # Usually TSR is monotonically increasing from ~1 to ~10.
        # Cp is usually between -0.5 and 0.6 (Betz limit 0.59).
        
        tsr_col_idx = -1
        cp_col_idx = -1
        
        # Heuristic to find columns
        cols = list(zip(*data_rows)) # Transpose
        
        for i, col in enumerate(cols):
            col_min = min(col)
            col_max = max(col)
            
            # Check for TSR-like column (Range approx 1-10)
            if 0.5 <= col_min <= 2.0 and 8.0 <= col_max <= 15.0:
                # Check strict monotonicity for TSR
                is_monotonic = all(x <= y for x, y in zip(col, col[1:]))
                if is_monotonic:
                    tsr_col_idx = i
            
            # Check for Cp-like column (Range -0.5 to 0.6)
            if -1.0 <= col_min and col_max <= 0.65:
                # Cp usually has a peak inside, not just monotonic
                # This is a weak check but separates it from e.g. Power (kW) which is >> 1
                cp_col_idx = i

        # Verify TSR Range (30 pts)
        if tsr_col_idx != -1:
            tsr_vals = cols[tsr_col_idx]
            if min(tsr_vals) <= 1.5 and max(tsr_vals) >= 9.5:
                score += 30
                feedback_parts.append("TSR range covers 1 to 10 as requested.")
            else:
                score += 15
                feedback_parts.append(f"TSR range partial ({min(tsr_vals):.1f}-{max(tsr_vals):.1f}).")
        else:
            feedback_parts.append("Could not identify a valid TSR column (1-10).")

        # Verify Cp Values (30 pts)
        if cp_col_idx != -1:
            cp_vals = cols[cp_col_idx]
            max_cp = max(cp_vals)
            if 0.1 < max_cp < 0.6: # Reasonable peak Cp for a wind turbine
                score += 30
                feedback_parts.append(f"Cp values look physically plausible (Peak: {max_cp:.3f}).")
            else:
                score += 10 # Found column, but values odd
                feedback_parts.append(f"Cp values found but suspicious (Peak: {max_cp:.3f}).")
        else:
            # Fallback: if we found TSR but missed Cp, maybe check if ANY other column looks like Cp
            valid_cp_candidates = [c for i, c in enumerate(cols) if i != tsr_col_idx and max(c) < 1.0]
            if valid_cp_candidates:
                score += 15
                feedback_parts.append("Found possible Cp data column.")
            else:
                feedback_parts.append("Could not identify a valid Cp column.")
    else:
        feedback_parts.append("No numeric data to analyze.")

    # Final Pass Logic
    # We require the file to exist, have data, and roughly correct ranges
    passed = (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }