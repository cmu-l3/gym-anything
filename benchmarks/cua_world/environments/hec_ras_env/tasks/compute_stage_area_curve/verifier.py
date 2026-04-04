#!/usr/bin/env python3
"""
Verifier for compute_stage_area_curve task.

Checks:
1. Output files exist and were created during task (timestamps).
2. CSV file has correct structure (headers) and sufficient rows.
3. CSV data is physically consistent:
   - Values >= 0
   - Area increases monotonically with Stage
   - Hydraulic Radius ~= Area / Wetted Perimeter
4. Info text file contains key identifiers.
5. Plot file is a valid image.
"""

import json
import os
import csv
import math
import logging
import tempfile
import sys

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_compute_stage_area_curve(traj, env_info, task_info):
    """
    Verify the stage-area curve computation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # Initialize scoring
    score = 0
    max_score = 100
    feedback = []
    
    # 1. Retrieve result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # --- Check 1: File Existence & Timestamps (30 pts) ---
    csv_exists = result_data.get('csv_exists', False)
    csv_fresh = result_data.get('csv_created_during_task', False)
    info_exists = result_data.get('info_exists', False)
    plot_exists = result_data.get('plot_exists', False)

    if csv_exists and csv_fresh:
        score += 15
        feedback.append("CSV file created successfully.")
    elif csv_exists:
        score += 5
        feedback.append("CSV file exists but timestamp is old (pre-existing?).")
    else:
        feedback.append("CSV file not found.")

    if info_exists and result_data.get('info_created_during_task', False):
        score += 5
        feedback.append("Info file created.")
    
    if plot_exists and result_data.get('plot_created_during_task', False):
        score += 10
        feedback.append("Plot file created.")

    # Stop here if CSV is missing, as we can't verify content
    if not csv_exists:
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # --- Retrieve Actual CSV Content ---
    csv_rows = []
    try:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env(result_data['csv_path'], temp_csv.name)
        
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            # Normalize headers to lowercase to be lenient
            reader.fieldnames = [x.lower().strip() for x in reader.fieldnames] if reader.fieldnames else []
            csv_rows = list(reader)
            headers = reader.fieldnames
        os.unlink(temp_csv.name)
    except Exception as e:
        feedback.append(f"Failed to read CSV content: {str(e)}")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # --- Check 2: CSV Structure (15 pts) ---
    required_cols = ['stage', 'flowarea', 'wettedperimeter', 'topwidth', 'hydraulicradius']
    # Map common variations
    col_map = {
        'stage': ['stage', 'elevation', 'h'],
        'flowarea': ['flowarea', 'area', 'a'],
        'wettedperimeter': ['wettedperimeter', 'perimeter', 'p', 'wet_perim'],
        'topwidth': ['topwidth', 'width', 'top_width', 't'],
        'hydraulicradius': ['hydraulicradius', 'radius', 'hyd_radius', 'r']
    }
    
    found_cols = 0
    missing_cols = []
    
    # Helper to find column in row
    def get_val(row, col_type):
        for candidate in col_map[col_type]:
            for header in row.keys():
                if candidate in header:
                    try:
                        return float(row[header])
                    except:
                        return None
        return None

    # Check headers roughly
    for r_col in required_cols:
        matched = False
        for h in headers:
            for candidate in col_map[r_col]:
                if candidate in h:
                    matched = True
                    break
        if matched:
            found_cols += 1
        else:
            missing_cols.append(r_col)

    if found_cols == 5:
        score += 15
        feedback.append("CSV structure correct.")
    elif found_cols >= 3:
        score += 8
        feedback.append(f"CSV structure partial ({found_cols}/5 cols). Missing: {missing_cols}")
    else:
        feedback.append(f"CSV structure incorrect. Found {found_cols}/5. Missing: {missing_cols}")

    # Check row count
    if len(csv_rows) >= 20: # Expecting 25
        score += 5 # Bonus for getting steps right
        feedback.append(f"Row count sufficient ({len(csv_rows)}).")
    else:
        feedback.append(f"Row count low ({len(csv_rows)} < 20).")

    # --- Check 3: Physical Consistency (30 pts) ---
    consistency_passed = True
    consistency_msgs = []
    
    stages = []
    areas = []
    perimeters = []
    radii = []

    for i, row in enumerate(csv_rows):
        s = get_val(row, 'stage')
        a = get_val(row, 'flowarea')
        p = get_val(row, 'wettedperimeter')
        r = get_val(row, 'hydraulicradius')
        
        if None in [s, a, p, r]:
            continue
            
        stages.append(s)
        areas.append(a)
        perimeters.append(p)
        radii.append(r)

        # 3a. Non-negative
        if a < -0.01 or p < -0.01:
            consistency_passed = False
            consistency_msgs.append(f"Row {i}: Negative Area/Perimeter")
            
        # 3b. Hydraulic Radius check (R = A/P)
        if p > 0.01:
            calc_r = a / p
            if abs(calc_r - r) > 0.1 and abs(calc_r - r) / (r + 0.001) > 0.05: # 5% tolerance or 0.1 abs
                consistency_passed = False
                consistency_msgs.append(f"Row {i}: R ({r}) != A/P ({calc_r:.2f})")

    # 3c. Monotonicity
    if len(areas) > 1:
        increasing = all(y >= x for x, y in zip(areas, areas[1:]))
        if not increasing:
            consistency_passed = False
            consistency_msgs.append("Flow Area not monotonically increasing.")
    
    if consistency_passed and len(areas) > 5:
        score += 30
        feedback.append("Data is physically consistent.")
    elif len(areas) > 5:
        score += 10
        feedback.append(f"Data consistency issues: {'; '.join(consistency_msgs[:3])}...")
    else:
        feedback.append("Insufficient data to verify consistency.")

    # --- Check 4: Info Content (15 pts) ---
    if info_exists:
        try:
            temp_info = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env(result_data['info_path'], temp_info.name)
            with open(temp_info.name, 'r') as f:
                content = f.read().lower()
            os.unlink(temp_info.name)
            
            # Check for reasonable keywords
            if any(x in content for x in ['station', 'river', 'id', 'rs']):
                score += 8
            if any(x in content for x in ['point', 'count', 'number']):
                score += 7
            feedback.append("Info file content verified.")
        except:
            feedback.append("Failed to verify info file content.")

    # --- Check 5: Plot Validity (10 pts) ---
    # We rely on file existence and size check from export script
    if plot_exists and result_data['plot_size_bytes'] > 10000:
        score += 10
        feedback.append("Plot file seems valid (size > 10KB).")
    elif plot_exists:
        score += 5
        feedback.append("Plot file exists but is small.")

    # --- Final Score Calc ---
    passed = score >= 60 and csv_exists and found_cols >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }