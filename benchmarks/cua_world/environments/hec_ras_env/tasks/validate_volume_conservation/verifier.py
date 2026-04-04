#!/usr/bin/env python3
"""
Verifier for validate_volume_conservation task.
Checks the generated JSON report for schema compliance, physical consistency,
and reasonable hydraulic values for the Muncie model.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_validate_volume_conservation(traj, env_info, task_info):
    """
    Verify the mass balance analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Define scoring weights
    w_files = 20      # Files exist and created during task
    w_schema = 20     # JSON has correct keys
    w_physics = 30    # Values are physically reasonable for this model
    w_consistency = 30 # Internal math check (Error % matches volumes)

    # 1. Get Task Result Metadata
    task_result = {}
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    # Check existence
    json_exists = task_result.get("json_exists", False)
    hdf_exists = task_result.get("hdf_exists", False)
    task_start = task_result.get("task_start", 0)
    json_mtime = task_result.get("json_mtime", 0)
    hdf_mtime = task_result.get("hdf_mtime", 0)

    if not json_exists:
        return {"passed": False, "score": 0, "feedback": "Output file volume_conservation.json not found."}

    # Score File Existence & Anti-Gaming
    file_score = 0
    if hdf_exists:
        if hdf_mtime > task_start:
            file_score += 10
            feedback_parts.append("Simulation run during task.")
        else:
            file_score += 5
            feedback_parts.append("Simulation results exist but appear stale (pre-task).")
    else:
        feedback_parts.append("Simulation results (HDF) not found.")

    if json_mtime > task_start:
        file_score += 10
        feedback_parts.append("Report created during task.")
    else:
        feedback_parts.append("Report file is old (pre-task).")
    
    score += file_score

    # 2. Parse and Verify JSON Content
    user_json = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/volume_conservation.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            user_json = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + f" | Invalid JSON format: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Schema Check
    required_keys = [
        "upstream_station", "downstream_station", 
        "total_inflow_volume_ft3", "total_outflow_volume_ft3",
        "peak_inflow_ft3_per_s", "peak_outflow_ft3_per_s",
        "volume_difference_ft3", "mass_balance_error_percent",
        "simulation_duration_hours", "conservation_acceptable",
        "num_time_steps", "num_cross_sections"
    ]
    
    missing_keys = [k for k in required_keys if k not in user_json]
    if not missing_keys:
        score += w_schema
        feedback_parts.append("JSON schema correct.")
    else:
        pen = len(missing_keys) * 2
        score += max(0, w_schema - pen)
        feedback_parts.append(f"Missing JSON keys: {', '.join(missing_keys)}.")

    # Physics & Logic Check
    try:
        v_in = float(user_json.get("total_inflow_volume_ft3", 0))
        v_out = float(user_json.get("total_outflow_volume_ft3", 0))
        p_in = float(user_json.get("peak_inflow_ft3_per_s", 0))
        p_out = float(user_json.get("peak_outflow_ft3_per_s", 0))
        diff = float(user_json.get("volume_difference_ft3", 0))
        err_pct = float(user_json.get("mass_balance_error_percent", 0))
        
        # Physics Sanity (Muncie Model Specifics)
        # Peaks usually around 10k-30k cfs. Volumes usually > 1e7.
        physics_passed = True
        
        if v_in <= 1000 or v_out <= 1000:
            physics_passed = False
            feedback_parts.append("Volumes suspiciously low.")
            
        if p_in <= 100 or p_out <= 100:
            physics_passed = False
            feedback_parts.append("Peak flows suspiciously low.")
            
        if p_in < p_out:
            # Not impossible in some waves, but for Muncie flood, attenuation is expected (p_in > p_out)
            # We won't penalize heavily, just note it.
            feedback_parts.append("Note: Peak outflow > inflow (unusual for this reach).")

        if physics_passed:
            score += w_physics
            feedback_parts.append("Values physically reasonable.")
        else:
            score += 0

        # Consistency Check (Math)
        # Check 1: V_diff approx V_in - V_out
        calc_diff = v_in - v_out
        # Allow tolerance for float formatting
        if abs(calc_diff - diff) < (v_in * 0.001): # 0.1% tolerance
            pass 
        else:
            feedback_parts.append(f"Volume difference mismatch (Calculated {calc_diff:.2f} vs Reported {diff:.2f}).")
            
        # Check 2: Error % formula
        # Task defined: error = abs(V_in - V_out) / V_in * 100
        if v_in > 0:
            calc_err = (abs(v_in - v_out) / v_in) * 100.0
            if abs(calc_err - err_pct) < 0.1: # 0.1% absolute tolerance
                score += w_consistency
                feedback_parts.append("Mass balance error calculation verified.")
            else:
                score += 10 # Partial credit
                feedback_parts.append(f"Error % mismatch (Calculated {calc_err:.4f}% vs Reported {err_pct:.4f}%).")
        else:
            feedback_parts.append("Inflow volume is zero, cannot calculate error.")

    except (ValueError, TypeError):
        feedback_parts.append("Non-numeric values found in JSON fields.")

    passed = score >= 60 and json_exists and hdf_exists
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }