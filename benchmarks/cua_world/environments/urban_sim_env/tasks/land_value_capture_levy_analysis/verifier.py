#!/usr/bin/env python3
"""Verifier for land_value_capture_levy_analysis task."""

import json
import tempfile
import os
import re


def verify_lvc_analysis(traj, env_info, task_info):
    """Verify land value capture analysis was completed.

    Scoring (100 points total):
    - Notebook Execution (20): exists, has required logic (2.5, 0.25), no errors
    - CSV Structure (20): exists, has 4 required columns
    - Target Zones Scope (20): CSV has exactly 5 rows (for 5 zones)
    - Mathematical Logic (20): levy = uplift * 0.25 for all rows
    - Visualization (20): PNG plot exists and >3kb
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # 1. Notebook Execution (20 pts)
    nb_score = 0
    if result.get('notebook_exists'):
        nb_score += 5
        if result.get('notebook_modified'):
            nb_score += 3
    nb_a = result.get('notebook_analysis', {})
    if nb_a.get('has_upzone'):
        nb_score += 4
    if nb_a.get('has_levy'):
        nb_score += 4
    if nb_a.get('has_pandas') and nb_a.get('has_read_hdf'):
        nb_score += 4
    
    score += nb_score
    feedback.append(f"Notebook: {nb_score}/20")

    # 2. CSV Structure (20 pts)
    csv_structure_score = 0
    if result.get('csv_exists'):
        csv_structure_score += 5
        if result.get('csv_created'):
            csv_structure_score += 3
        
        expected_cols = metadata.get('expected_csv_columns', [
            "zone_id", 
            "total_parcels_assessed", 
            "total_value_uplift", 
            "projected_levy_revenue"
        ])
        csv_cols = result.get('csv_columns', [])
        
        cols_found = 0
        for exp_c in expected_cols:
            if any(exp_c in c for c in csv_cols if c is not None):
                cols_found += 1
                
        csv_structure_score += (cols_found * 3)
    
    score += csv_structure_score
    feedback.append(f"CSV Structure: {csv_structure_score}/20")

    # 3. Target Zones Scope (20 pts)
    scope_score = 0
    csv_rows = result.get('csv_rows', 0)
    if result.get('csv_exists'):
        if csv_rows == 5:
            scope_score += 20
        elif csv_rows > 0:
            scope_score += 5
            feedback.append(f"Scope: {csv_rows} rows found, expected 5")
    score += scope_score
    if scope_score == 20:
        feedback.append(f"Scope: {scope_score}/20")

    # 4. Mathematical Logic (20 pts)
    math_score = 0
    if result.get('csv_exists') and csv_rows > 0:
        csv_data = result.get('csv_data', [])
        
        # Find column keys that match our expected logic
        uplift_key = None
        levy_key = None
        for k in csv_data[0].keys():
            if k and 'uplift' in k.lower():
                uplift_key = k
            if k and 'levy' in k.lower():
                levy_key = k
                
        if uplift_key and levy_key:
            correct_rows = 0
            for row in csv_data:
                try:
                    uplift = float(row[uplift_key])
                    levy = float(row[levy_key])
                    # Check if levy is 25% of uplift (allow tiny float precision issues)
                    if abs(uplift * 0.25 - levy) < (abs(uplift) * 0.01 + 0.01):
                        correct_rows += 1
                except (ValueError, TypeError):
                    pass
            
            if len(csv_data) > 0:
                math_score += int(20 * (correct_rows / len(csv_data)))
    score += math_score
    feedback.append(f"Math Logic: {math_score}/20")

    # 5. Visualization (20 pts)
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 10
        if result.get('plot_created'):
            plot_score += 5
        if result.get('plot_size_kb', 0) >= 3:
            plot_score += 5
    score += plot_score
    feedback.append(f"Plot: {plot_score}/20")

    passed = score >= 60 and csv_structure_score >= 10 and math_score >= 10
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }