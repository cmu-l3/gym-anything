#!/usr/bin/env python3
"""Verifier for legacy_commercial_transition_analysis task."""

import json
import tempfile
import os
import csv


def verify_transition_analysis(traj, env_info, task_info):
    """Verify legacy commercial transition analysis was completed successfully.
    
    Scoring System:
    - Notebook Execution: 10 points
    - Code Logic Patterns: 20 points
    - CSV Structure: 15 points
    - Data Threshold Rules: 20 points
    - Index Math & Sorting: 15 points
    - Visualization Output: 20 points
    Total: 100 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_cols = [c.lower() for c in metadata.get('expected_csv_columns', ["zone_id", "legacy_nonres_sqft", "new_res_units", "transition_index"])]
    min_sqft = metadata.get('min_legacy_sqft', 50000)
    min_units = metadata.get('min_new_units', 50)
    
    score = 0
    feedback = []

    # Read base result JSON
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Criterion 1: Notebook Execution (10 points)
    nb_a = result.get('notebook_analysis', {})
    num_executed = nb_a.get('num_executed_cells', 0)
    if result.get('notebook_exists') and result.get('notebook_modified'):
        if num_executed >= 3:
            score += 10
            feedback.append("Notebook executed successfully (10/10)")
        elif num_executed > 0:
            score += 5
            feedback.append("Notebook partially executed (5/10)")
        else:
            feedback.append("Notebook not executed (0/10)")
    else:
        feedback.append("Notebook not found or not modified (0/10)")

    # Criterion 2: Code Logic Patterns (20 points)
    logic_score = 0
    if nb_a.get('has_pandas') and nb_a.get('has_hdf'): logic_score += 4
    if nb_a.get('has_groupby'): logic_score += 4
    if nb_a.get('has_1980') and nb_a.get('has_2000'): logic_score += 4
    if nb_a.get('has_50000') and nb_a.get('has_50'): logic_score += 4
    if nb_a.get('has_1000'): logic_score += 4
    
    score += logic_score
    feedback.append(f"Code logic detected: {logic_score}/20")

    # Fetch and parse CSV for structure and math verification
    csv_rows_data = []
    csv_path = metadata.get('expected_csv_path', "/home/ga/urbansim_projects/output/transitioning_zones.csv")
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(csv_path, temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            reader = csv.reader(f)
            header = next(reader, None)
            for row in reader:
                csv_rows_data.append(row)
    except Exception:
        header = None
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Criterion 3: CSV Structure (15 points)
    structure_score = 0
    header_lower = []
    if result.get('csv_exists') and result.get('csv_created'):
        structure_score += 5
        if header is not None:
            # Check if headers closely match expected
            header_lower = [h.strip().lower() for h in header]
            # Ignore index column if pandas added it without name
            if len(header_lower) > 0 and header_lower[0] == '':
                header_lower = header_lower[1:]
                csv_rows_data = [r[1:] for r in csv_rows_data if len(r) > 1]
                
            has_all_cols = all(any(expected in h for h in header_lower) for expected in expected_csv_cols)
            if has_all_cols:
                structure_score += 5
            
            # Check row count (up to 15)
            if len(csv_rows_data) > 0 and len(csv_rows_data) <= 15:
                structure_score += 5
    score += structure_score
    feedback.append(f"CSV structure: {structure_score}/15")

    # Criterion 4 & 5: Data Threshold Rules (20 points) & Index Math (15 points)
    threshold_score = 0
    math_score = 0
    
    if len(csv_rows_data) > 0 and structure_score >= 10:
        valid_thresholds = 0
        valid_math = 0
        is_sorted = True
        prev_idx_val = float('inf')
        
        # Try to map columns
        sqft_idx, units_idx, index_idx = -1, -1, -1
        for i, h in enumerate(header_lower):
            if 'sqft' in h: sqft_idx = i
            elif 'units' in h: units_idx = i
            elif 'index' in h: index_idx = i
            
        if sqft_idx >= 0 and units_idx >= 0 and index_idx >= 0:
            for row in csv_rows_data:
                try:
                    sqft = float(row[sqft_idx])
                    units = float(row[units_idx])
                    idx_val = float(row[index_idx])
                    
                    if sqft >= min_sqft and units >= min_units:
                        valid_thresholds += 1
                        
                    expected_idx = units / (sqft / 1000.0)
                    if abs(idx_val - expected_idx) < 0.1: # Allow rounding
                        valid_math += 1
                        
                    if idx_val > prev_idx_val + 0.01:
                        is_sorted = False
                    prev_idx_val = idx_val
                except (ValueError, IndexError):
                    pass
            
            # Award threshold points proportionally
            prop_t = valid_thresholds / len(csv_rows_data)
            threshold_score = int(prop_t * 20)
            
            # Award math points
            prop_m = valid_math / len(csv_rows_data)
            math_score = int(prop_m * 10)
            if is_sorted: math_score += 5
            
    score += threshold_score
    score += math_score
    feedback.append(f"Threshold rules: {threshold_score}/20")
    feedback.append(f"Math & Sorting: {math_score}/15")

    # Criterion 6: Visualization Output (20 points)
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 10
        if result.get('plot_created'):
            plot_score += 5
        if result.get('plot_size_kb', 0) >= 15:
            plot_score += 5
    score += plot_score
    feedback.append(f"Plot output: {plot_score}/20")

    # Determine final pass/fail
    # Requires minimum score and key CSV elements to be right
    passed = score >= 70 and structure_score >= 10 and math_score >= 10

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }