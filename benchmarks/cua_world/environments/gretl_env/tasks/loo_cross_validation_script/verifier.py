#!/usr/bin/env python3
"""
Verifier for Gretl LOO Cross-Validation Task.
Calculates exact ground truth using OLS Hat Matrix shortcut.
"""

import json
import base64
import re
import numpy as np
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground Truth Data (Principles of Econometrics 5th Ed, Table 2.1)
# Food Exp (Y), Income (X)
RAW_DATA = [
    [115.22, 3.69], [135.98, 4.39], [119.34, 4.75], [114.96, 6.03],
    [187.05, 12.47], [243.43, 12.98], [109.71, 3.15], [197.23, 12.00],
    [263.29, 16.31], [251.84, 12.13], [147.22, 7.99], [230.77, 12.63],
    [182.43, 8.93], [248.13, 10.01], [220.84, 8.79], [337.62, 19.06],
    [167.38, 9.09], [217.37, 10.91], [327.28, 15.18], [355.76, 20.01],
    [176.17, 9.69], [352.86, 20.00], [192.43, 7.63], [207.39, 12.80],
    [321.62, 15.29], [274.54, 15.72], [312.05, 22.66], [261.74, 13.59],
    [263.99, 11.51], [296.24, 17.70], [265.30, 13.85], [313.18, 14.12],
    [300.68, 21.23], [279.22, 16.54], [374.22, 24.22], [377.52, 24.16],
    [260.35, 17.32], [382.14, 25.51], [374.76, 25.08], [404.90, 26.75]
]

def calculate_ground_truth():
    """Calculates LOO-CV metrics analytically."""
    data = np.array(RAW_DATA)
    y = data[:, 0]  # Food Exp
    x = data[:, 1]  # Income
    n = len(y)
    
    # Add constant term to X
    X = np.column_stack((np.ones(n), x))
    
    # OLS Estimator: beta = (X'X)^-1 X'y
    XtX_inv = np.linalg.inv(X.T @ X)
    beta = XtX_inv @ X.T @ y
    
    # Predicted values (in-sample)
    y_hat = X @ beta
    
    # Residuals
    residuals = y - y_hat
    
    # Hat Matrix diagonal: h_ii = diag(X(X'X)^-1 X')
    # Efficient calculation: sum of (X @ XtX_inv) * X over axis 1
    h = np.sum((X @ XtX_inv) * X, axis=1)
    
    # LOO Residuals: e_i / (1 - h_i)
    loo_residuals = residuals / (1 - h)
    
    # Metrics
    mspe = np.mean(loo_residuals**2)
    rmspe = np.sqrt(mspe)
    
    return {
        "mspe": mspe,
        "rmspe": rmspe,
        "loo_residuals": loo_residuals,
        "y": y
    }

def verify_loo_cv(traj, env_info, task_info):
    """Verifies the LOO Cross-Validation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Load results from agent
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 2. Decode files
    results_txt = ""
    predictions_csv = ""
    
    if result_data.get("results_file_exists"):
        try:
            results_txt = base64.b64decode(result_data.get("results_file_content_b64", "")).decode('utf-8')
            if result_data.get("results_file_created_during_task"):
                score += 5  # Timestamp points
        except:
            feedback.append("Failed to decode results file.")

    if result_data.get("predictions_file_exists"):
        try:
            predictions_csv = base64.b64decode(result_data.get("predictions_file_content_b64", "")).decode('utf-8')
        except:
            feedback.append("Failed to decode predictions file.")

    # 3. Calculate Ground Truth
    gt = calculate_ground_truth()
    
    # 4. Verify Results File (MSPE/RMSPE)
    rmspe_agent = None
    mspe_agent = None
    
    if result_data.get("results_file_exists"):
        score += 5 # Exists
        
        # Parse MSPE
        mspe_match = re.search(r"MSPE[:\s=]+([0-9\.]+)", results_txt, re.IGNORECASE)
        if mspe_match:
            try:
                mspe_agent = float(mspe_match.group(1))
                score += 5 # Reported
                
                # Check accuracy (within 2%)
                if abs(mspe_agent - gt["mspe"]) / gt["mspe"] < 0.02:
                    score += 15
                    feedback.append(f"MSPE Correct: {mspe_agent:.2f} (Ref: {gt['mspe']:.2f})")
                else:
                    feedback.append(f"MSPE Incorrect: {mspe_agent:.2f} (Expected: {gt['mspe']:.2f})")
            except:
                pass
        else:
            feedback.append("MSPE not found in results file.")
            
        # Parse RMSPE
        rmspe_match = re.search(r"RMSPE[:\s=]+([0-9\.]+)", results_txt, re.IGNORECASE)
        if rmspe_match:
            try:
                rmspe_agent = float(rmspe_match.group(1))
                score += 10 # Reported
                
                # Check accuracy (within 2%)
                if abs(rmspe_agent - gt["rmspe"]) / gt["rmspe"] < 0.02:
                    score += 25
                    feedback.append(f"RMSPE Correct: {rmspe_agent:.2f} (Ref: {gt['rmspe']:.2f})")
                else:
                    feedback.append(f"RMSPE Incorrect: {rmspe_agent:.2f} (Expected: {gt['rmspe']:.2f})")
            except:
                pass
        else:
            feedback.append("RMSPE not found in results file.")
    else:
        feedback.append("Results file not found.")

    # 5. Verify Predictions File
    if result_data.get("predictions_file_exists"):
        score += 5 # Exists
        
        lines = predictions_csv.strip().split('\n')
        # Simple CSV parsing (handle possible header)
        data_rows = []
        for line in lines:
            parts = line.strip().split(',')
            # Skip header if it contains text
            try:
                vals = [float(p) for p in parts if p.strip()]
                if len(vals) >= 2:
                    data_rows.append(vals)
            except:
                continue
                
        if len(data_rows) == 40:
            score += 10 # Correct count
            
            # Check values
            data_rows = np.array(data_rows)
            
            # Verify Actuals (usually column 0 or 1, we check correlation)
            # Find which column matches ground truth Y
            col_match = -1
            for i in range(data_rows.shape[1]):
                if np.allclose(data_rows[:, i], gt["y"], atol=1.0):
                    col_match = i
                    break
            
            if col_match != -1:
                score += 10 # Actuals match
                
                # Check predictions plausibility (range 50-500)
                # Assuming the other column is prediction
                pred_col = 1 if col_match == 0 else 0
                if data_rows.shape[1] > 1:
                    preds = data_rows[:, pred_col]
                    if np.all(preds > 50) and np.all(preds < 500):
                        score += 10 # Plausible
                    else:
                        feedback.append("Predictions out of plausible range.")
            else:
                feedback.append("Could not identify 'Actual' values in CSV.")
        else:
            feedback.append(f"Incorrect row count in CSV: {len(data_rows)} (Expected 40)")
    else:
        feedback.append("Predictions CSV not found.")

    passed = score >= 60 and (rmspe_agent is not None and abs(rmspe_agent - gt["rmspe"]) / gt["rmspe"] < 0.02)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }