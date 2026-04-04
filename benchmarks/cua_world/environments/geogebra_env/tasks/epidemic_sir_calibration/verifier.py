#!/usr/bin/env python3
"""
Verifier for Epidemic SIR Calibration task.

Scoring (100 pts total):
1. File Created (10 pts)
2. Data Imported (20 pts): >= 10 points found
3. SIR Model (30 pts): SolveODE or similar command found
4. Curve Visible (10 pts): VLM check (trajectory) or file check
5. Calibration (30 pts): Beta ~ 1.66, Gamma ~ 0.44

Pass Threshold: 70 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_epidemic_sir_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    target_beta = metadata.get('target_beta', 1.66)
    target_gamma = metadata.get('target_gamma', 0.44)
    beta_tol = metadata.get('beta_tolerance', 0.25)
    gamma_tol = metadata.get('gamma_tolerance', 0.07)

    # 1. Retrieve Result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}

    score = 0
    feedback = []

    # 2. Score: File Creation (10 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback.append("File created successfully (+10).")
    elif result.get('file_found'):
        feedback.append("File exists but was not created during this session (0/10).")
    else:
        feedback.append("File 'sir_analysis.ggb' not found (0/10).")

    # 3. Score: Data Import (20 pts)
    # The dataset has 13 points. We expect at least 10 points in the file.
    if result.get('has_data_points') or result.get('num_points', 0) >= 10:
        score += 20
        feedback.append(f"Data imported: {result.get('num_points')} points found (+20).")
    else:
        feedback.append(f"Insufficient data points: found {result.get('num_points')}, expected >= 10 (0/20).")

    # 4. Score: SIR Model Logic (30 pts)
    # Check for SolveODE, NSolveODE, or manual integration commands
    if result.get('has_ode_command'):
        score += 30
        feedback.append(f"ODE solver command found: {result.get('command_list')} (+30).")
    else:
        # Partial credit check: Did they create sliders at least?
        if result.get('has_sliders'):
            score += 10
            feedback.append("Sliders found but no ODE solver detected (+10/30).")
        else:
            feedback.append("No ODE solver or sliders detected (0/30).")

    # 5. Score: Calibration Accuracy (30 pts)
    # Check if extracted parameters match targets
    # Beta
    beta = result.get('parameter_beta')
    gamma = result.get('parameter_gamma')
    
    calib_score = 0
    
    if beta is not None:
        if abs(beta - target_beta) <= beta_tol:
            calib_score += 15
            feedback.append(f"Beta calibrated: {beta:.3f} (Target {target_beta} +/- {beta_tol}) (+15).")
        else:
            feedback.append(f"Beta value {beta:.3f} outside tolerance ({target_beta} +/- {beta_tol}) (0/15).")
    else:
        feedback.append("Beta parameter not identified (0/15).")

    if gamma is not None:
        if abs(gamma - target_gamma) <= gamma_tol:
            calib_score += 15
            feedback.append(f"Gamma calibrated: {gamma:.3f} (Target {target_gamma} +/- {gamma_tol}) (+15).")
        else:
            feedback.append(f"Gamma value {gamma:.3f} outside tolerance ({target_gamma} +/- {gamma_tol}) (0/15).")
    else:
        feedback.append("Gamma parameter not identified (0/15).")
        
    score += calib_score

    # 6. Score: Visual Verification (10 pts)
    # Just checking if file exists effectively covers the "something was saved" part
    # A more advanced VLM check could go here, but for now we give points if model exists
    if result.get('has_ode_command') and result.get('has_data_points'):
        score += 10
        feedback.append("Model and data both present implies visual output (+10).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }