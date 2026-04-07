#!/usr/bin/env python3
"""Verifier for redevelopment_potential_analysis task."""

import json
import tempfile
import os
import re
import csv


def verify_redevelopment_potential(traj, env_info, task_info):
    """Verify the RPI computation task.

    Scoring (100 points total):
    - File Existence & Basic Notebook Checks (20 pts)
    - Code Logic Verification via Notebook Parsing (30 pts)
    - CSV Structure & Rules Verification (40 pts)
    - Plot Validity (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_path = metadata.get('expected_csv_path', '/home/ga/urbansim_projects/output/top_redevelopment_parcels.csv')
    
    score = 0
    feedback = []

    # =========================================
    # Part 1: Programmatic checks (20 pts)
    # =========================================
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    if result.get('notebook_exists') and result.get('notebook_modified'):
        score += 5
        feedback.append("Notebook modified.")

    nb_analysis = result.get('notebook_analysis', {})
    if nb_analysis.get('has_code') and nb_analysis.get('num_executed_cells', 0) > 0:
        score += 5
        feedback.append("Notebook has executed code cells.")

    if result.get('csv_exists') and result.get('csv_created'):
        score += 5
        feedback.append("CSV created during task.")

    if result.get('plot_exists') and result.get('plot_size_kb', 0) > 5:
        score += 5
        feedback.append("Plot created and has reasonable size.")

    # =========================================
    # Part 2: Code Analysis (30 pts)
    # =========================================
    code_score = 0
    if nb_analysis.get('has_hdf'):
        code_score += 5
    if nb_analysis.get('has_merge'):
        code_score += 5
    if nb_analysis.get('has_far'):
        code_score += 5
    if nb_analysis.get('has_minmax'):
        code_score += 5
    if nb_analysis.get('has_weights'):
        code_score += 10
        
    score += code_score
    feedback.append(f"Code syntax checks: {code_score}/30")

    # =========================================
    # Part 3: CSV Rules & Data Validity (40 pts)
    # =========================================
    csv_score = 0
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_csv_path, temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
            if len(rows) > 0:
                cols = [c.lower() for c in reader.fieldnames if c]
                expected_cols = metadata.get('expected_csv_columns', [])
                
                # Check columns (10 pts)
                missing_cols = [c for c in expected_cols if not any(c in col for col in cols)]
                if not missing_cols:
                    csv_score += 10
                    feedback.append("CSV has all expected columns.")
                else:
                    feedback.append(f"CSV missing columns: {missing_cols}")
                
                # Check Row Count (10 pts)
                if len(rows) == 50:
                    csv_score += 10
                    feedback.append("CSV has exactly 50 rows.")
                elif len(rows) > 0:
                    csv_score += 5
                    feedback.append(f"CSV has {len(rows)} rows (expected 50).")
                
                # Check Data Validity & Sorting (20 pts)
                valid_data = True
                sorted_correctly = True
                prev_rpi = float('inf')
                
                try:
                    for row in rows:
                        # Find the RPI column specifically
                        rpi_col = next((c for c in reader.fieldnames if 'rpi' in c.lower()), None)
                        if not rpi_col:
                            valid_data = False
                            break
                            
                        rpi_val = float(row[rpi_col])
                        if not (0 <= rpi_val <= 1.01): # Slight tolerance for float precision
                            valid_data = False
                        
                        if rpi_val > prev_rpi + 0.001:
                            sorted_correctly = False
                            
                        prev_rpi = rpi_val
                        
                    if valid_data:
                        csv_score += 10
                        feedback.append("RPI values are within expected [0,1] range.")
                    if sorted_correctly and valid_data:
                        csv_score += 10
                        feedback.append("Parcels correctly sorted by RPI descending.")
                        
                except Exception as e:
                    feedback.append(f"Error parsing CSV numeric values: {e}")
                    
    except Exception as e:
        feedback.append(f"Could not validate CSV contents: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    score += csv_score
    
    # =========================================
    # Part 4: Plot Verification (10 pts)
    # =========================================
    if result.get('plot_exists') and result.get('plot_size_kb', 0) >= 15:
        score += 10
        feedback.append("Plot file exceeds minimum visual size.")
    elif result.get('plot_exists'):
        score += 5

    passed = score >= 60 and result.get('csv_exists')

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }