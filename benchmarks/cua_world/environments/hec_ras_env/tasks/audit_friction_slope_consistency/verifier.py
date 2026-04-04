#!/usr/bin/env python3
"""
Verifier for audit_friction_slope_consistency task.

Verification Strategy:
1. Validates that the HEC-RAS simulation was actually run (HDF file created).
2. Parses the generated CSV report.
3. Checks for required columns.
4. Validates the physics/math:
   - Recalculates 'Calculated_Manning_n' using the reported V, R, S columns.
   - Checks if the values are consistent (math check).
5. Validates variable selection:
   - If the agent used Friction Slope (Sf), residuals should be low (< 0.001) for a converged model.
   - If the agent used Bed Slope (S0) or Energy Slope (Se), residuals will be higher.
   - Checks that the 'Status' column correctly flags PASS/FAIL based on the residual.

Score Breakdown:
- Simulation Run: 10 pts
- CSV Created & Timely: 10 pts
- Correct Columns: 10 pts
- Math Consistency (Formula correct): 20 pts
- Low Residuals (Correct Slope used): 30 pts
- Correct Status Logic: 20 pts
"""

import json
import os
import csv
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_friction_slope_consistency(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    required_columns = metadata.get('required_columns', [])
    
    # Load Export Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Simulation Run (10 pts)
    if export_result.get("simulation_run", False):
        score += 10
        feedback_parts.append("Simulation run confirmed")
    else:
        feedback_parts.append("Simulation NOT run (HDF file not updated)")

    # 2. Check CSV Existence (10 pts)
    if export_result.get("output_exists", False) and export_result.get("csv_created_during_task", False):
        score += 10
        feedback_parts.append("Audit CSV created")
    else:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | Output CSV missing or stale"}

    # 3. Process CSV Content
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/Documents/hec_ras_results/roughness_audit.csv", temp_csv.name)
        
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames
            rows = list(reader)
            
        # Check Columns (10 pts)
        missing_cols = [col for col in required_columns if col not in (headers or [])]
        if not missing_cols:
            score += 10
            feedback_parts.append("All columns present")
        else:
            feedback_parts.append(f"Missing columns: {missing_cols}")
            # If crucial data columns missing, cannot proceed with math check
            if any(x in missing_cols for x in ["Channel_Velocity_fps", "Channel_Hydraulic_Radius_ft", "Friction_Slope", "Calculated_Manning_n"]):
                return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Validate Rows
        valid_math_count = 0
        low_residual_count = 0
        correct_status_count = 0
        total_rows = len(rows)
        
        if total_rows == 0:
            return {"passed": False, "score": score, "feedback": "CSV is empty"}

        for row in rows:
            try:
                # Extract values
                v = float(row.get("Channel_Velocity_fps", 0))
                r = float(row.get("Channel_Hydraulic_Radius_ft", 0))
                sf = float(row.get("Friction_Slope", 0))
                n_input = float(row.get("Input_Manning_n", 0))
                n_reported = float(row.get("Calculated_Manning_n", 0))
                residual_reported = float(row.get("Residual", 0))
                status = row.get("Status", "").strip().upper()

                # 4. Math Consistency Check (20 pts)
                # n = (1.486 / V) * (R^(2/3)) * (Sf^(1/2))
                if v > 0 and sf >= 0:
                    n_recalc = (1.486 / v) * (r ** (2/3)) * (sf ** 0.5)
                    # Check if agent's calculation matches the formula
                    if abs(n_recalc - n_reported) < 0.001:
                        valid_math_count += 1
                elif v == 0 and n_reported == 0:
                    # Handle zero flow case
                    valid_math_count += 1
                    
                # 5. Low Residual Check (Variable Selection) (30 pts)
                # If they used Sf, n_recalc should be close to n_input (0.035 usually)
                if abs(n_reported - n_input) < 0.002:
                    low_residual_count += 1
                    
                # 6. Status Logic Check (20 pts)
                is_pass = residual_reported < 0.001
                if (is_pass and status == "PASS") or (not is_pass and status == "FAIL"):
                    correct_status_count += 1
                    
            except ValueError:
                continue

        # Award points based on percentage of correct rows
        if total_rows > 0:
            math_score = (valid_math_count / total_rows) * 20
            residual_score = (low_residual_count / total_rows) * 30
            status_score = (correct_status_count / total_rows) * 20
            
            score += math_score + residual_score + status_score
            
            feedback_parts.append(f"Math accuracy: {int((valid_math_count/total_rows)*100)}%")
            feedback_parts.append(f"Variable selection (Slope): {int((low_residual_count/total_rows)*100)}%")

    except Exception as e:
        feedback_parts.append(f"Error analyzing CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 75
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }