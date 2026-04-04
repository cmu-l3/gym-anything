#!/usr/bin/env python3
"""
Verifier for compute_wetted_perimeter task.

Checks:
1. CSV and Summary files exist and were created during the task.
2. CSV contains correct columns and monotonic Wetted Perimeter data.
3. Summary file contains required fields.
4. Breakpoint logic is consistent between CSV data and Summary report.
"""

import json
import os
import tempfile
import csv
import logging
import math

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_wetted_perimeter(traj, env_info, task_info):
    """
    Verify the wetted perimeter analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_path = metadata.get('output_csv_path', '/home/ga/Documents/hec_ras_results/wetted_perimeter_analysis.csv')
    expected_summary_path = metadata.get('output_summary_path', '/home/ga/Documents/hec_ras_results/wetted_perimeter_summary.txt')

    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Step 1: Check metadata from export_result.sh ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not task_result.get('csv_exists') or not task_result.get('summary_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Missing required output files. Both CSV and Summary text file are required."
        }
    
    score += 10 # Files exist
    feedback_parts.append("Output files found")

    if task_result.get('csv_created_during_task') and task_result.get('summary_created_during_task'):
        score += 10 # Anti-gaming
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("Files timestamp check failed (files too old)")

    # --- Step 2: Analyze CSV Content ---
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_data = []
    try:
        copy_from_env(expected_csv_path, temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            # Normalize headers (strip spaces, lowercase)
            reader.fieldnames = [name.strip() for name in reader.fieldnames]
            csv_data = list(reader)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Check Columns
    required_cols = {'stage', 'wetted_perimeter', 'depth_above_thalweg', 'dWP_dStage'}
    if not csv_data:
        return {"passed": False, "score": score, "feedback": "CSV file is empty"}
    
    actual_cols = set(csv_data[0].keys())
    # Allow loose matching on column names
    mapped_cols = {}
    for req in required_cols:
        match = next((col for col in actual_cols if req.lower() in col.lower()), None)
        if match:
            mapped_cols[req] = match
    
    if len(mapped_cols) < 4:
        missing = required_cols - set(mapped_cols.keys())
        feedback_parts.append(f"Missing columns: {missing}")
    else:
        score += 10
        feedback_parts.append("CSV structure correct")

    # Check Row Count
    if len(csv_data) == 25:
        score += 10
        feedback_parts.append("Exactly 25 data points")
    else:
        feedback_parts.append(f"Incorrect row count: {len(csv_data)} (expected 25)")

    # Check Data Validity & Monotonicity
    try:
        stages = [float(row[mapped_cols['stage']]) for row in csv_data]
        wps = [float(row[mapped_cols['wetted_perimeter']]) for row in csv_data]
        depths = [float(row[mapped_cols['depth_above_thalweg']]) for row in csv_data]
        derivs = []
        for row in csv_data:
            val = row[mapped_cols['dWP_dStage']]
            if val.lower() == 'nan':
                derivs.append(None)
            else:
                derivs.append(float(val))

        # Check positivity
        if all(wp >= 0 for wp in wps) and all(d >= 0 for d in depths):
            score += 10
            feedback_parts.append("Values are positive/valid")
        else:
            feedback_parts.append("Found negative values in WP or Depth")

        # Check monotonicity of WP (should generally increase with stage)
        # Allow small noise or minor geometry quirks, but generally WP increases
        decreases = 0
        for i in range(1, len(wps)):
            if wps[i] < wps[i-1] - 0.1: # tolerance
                decreases += 1
        
        if decreases <= 2:
            score += 10
            feedback_parts.append("Wetted Perimeter increases with stage")
        else:
            feedback_parts.append(f"Wetted Perimeter is not monotonic ({decreases} decreases found)")
        
        # Check derivative calculation (Spot check)
        # dWP/dStage approx (WP2-WP1)/(S2-S1)
        # We check if the reported derivative is reasonably close to finite difference
        valid_derivs = 0
        for i in range(1, len(wps)):
            ds = stages[i] - stages[i-1]
            if ds > 0.0001:
                calc_deriv = (wps[i] - wps[i-1]) / ds
                rept_deriv = derivs[i]
                if rept_deriv is not None and abs(calc_deriv - rept_deriv) < 5.0: # Generous tolerance for different numeric methods
                    valid_derivs += 1
        
        if valid_derivs >= len(wps) - 5: # Allow start/end discrepancies
            score += 10
            feedback_parts.append("Derivative values verified")

    except ValueError:
        feedback_parts.append("Non-numeric data found in CSV")

    # --- Step 3: Analyze Summary File ---
    temp_sum = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    summary_dict = {}
    try:
        copy_from_env(expected_summary_path, temp_sum.name)
        with open(temp_sum.name, 'r') as f:
            for line in f:
                if ':' in line:
                    key, val = line.split(':', 1)
                    summary_dict[key.strip()] = val.strip()
    except Exception as e:
        feedback_parts.append(f"Failed to read summary: {e}")
    finally:
        if os.path.exists(temp_sum.name):
            os.unlink(temp_sum.name)

    req_fields = [
        "river_station", "thalweg_elevation_ft", "max_bank_elevation_ft",
        "breakpoint_stage_ft", "breakpoint_depth_ft", "breakpoint_wetted_perimeter_ft"
    ]
    
    fields_present = all(f in summary_dict for f in req_fields)
    
    if fields_present:
        score += 10
        feedback_parts.append("Summary fields present")
        
        # Cross-Verification: Does breakpoint match CSV data?
        try:
            summ_bp_stage = float(summary_dict["breakpoint_stage_ft"])
            
            # Find max derivative in CSV
            max_deriv_val = -1.0
            max_deriv_stage = -1.0
            
            # Skip first point (NaN)
            for i in range(1, len(derivs)):
                if derivs[i] is not None and derivs[i] > max_deriv_val:
                    max_deriv_val = derivs[i]
                    max_deriv_stage = stages[i]
            
            # Check consistency
            if abs(summ_bp_stage - max_deriv_stage) < 0.5:
                score += 10
                feedback_parts.append("Breakpoint stage consistent with CSV data")
            else:
                feedback_parts.append(f"Breakpoint mismatch (Summary: {summ_bp_stage}, CSV Max Deriv: {max_deriv_stage})")
                
            # Range check
            thalweg = float(summary_dict["thalweg_elevation_ft"])
            max_bank = float(summary_dict["max_bank_elevation_ft"])
            if thalweg < summ_bp_stage < max_bank:
                score += 10
                feedback_parts.append("Breakpoint in valid range")
                
        except ValueError:
            feedback_parts.append("Non-numeric values in summary")
    else:
        feedback_parts.append("Missing fields in summary file")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }