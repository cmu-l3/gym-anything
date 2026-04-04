#!/usr/bin/env python3
"""
Verifier for regression_manual_prediction_exam task.

Verifies:
1. Analysis file (.omv) creation.
2. Prediction report (.txt) content against ground truth calculated from data.
3. Correct calculation of predicted score using regression coefficients.
"""

import json
import os
import tempfile
import pandas as pd
import numpy as np
from scipy import stats

def calculate_ground_truth(csv_path):
    """
    Calculates OLS regression coefficients and prediction ground truth 
    from the CSV file directly using numpy/scipy.
    
    Model: Exam ~ Revise + Anxiety
    Prediction point: Revise=10, Anxiety=50
    """
    try:
        df = pd.read_csv(csv_path)
        
        # Prepare data (drop NAs if any, though Exam Anxiety dataset is usually clean)
        df = df[['Exam', 'Revise', 'Anxiety']].dropna()
        
        y = df['Exam'].values
        # Add intercept column
        X = np.column_stack([np.ones(len(df)), df['Revise'].values, df['Anxiety'].values])
        
        # OLS: beta = (X'X)^-1 X'y
        beta = np.linalg.inv(X.T @ X) @ X.T @ y
        
        intercept = beta[0]
        b_revise = beta[1]
        b_anxiety = beta[2]
        
        # Calculate standard errors for CIs
        # Residuals
        y_pred = X @ beta
        residuals = y - y_pred
        # Residual variance: sigma^2 = sum(residuals^2) / (n - k)
        # n = observations, k = parameters (predictors + intercept)
        n = len(y)
        k = 3 # Intercept, Revise, Anxiety
        sigma2 = np.sum(residuals**2) / (n - k)
        
        # Variance-Covariance Matrix: sigma^2 * (X'X)^-1
        var_cov_matrix = sigma2 * np.linalg.inv(X.T @ X)
        se = np.sqrt(np.diag(var_cov_matrix))
        
        se_revise = se[1]
        
        # t-critical for 95% CI (two-tailed)
        # alpha = 0.05, tails = 2 -> 0.975 quantile
        df_resid = n - k
        t_crit = stats.t.ppf(0.975, df_resid)
        
        revise_ci_lower = b_revise - (t_crit * se_revise)
        
        # Specific prediction
        # Pred = Intercept + (Revise * 10) + (Anxiety * 50)
        predicted_score = intercept + (b_revise * 10) + (b_anxiety * 50)
        
        return {
            "intercept": intercept,
            "b_revise": b_revise,
            "b_anxiety": b_anxiety,
            "revise_ci_lower": revise_ci_lower,
            "predicted_score": predicted_score,
            "success": True
        }
        
    except Exception as e:
        return {"success": False, "error": str(e)}

def parse_agent_report(report_text):
    """Parses the key-value text report from the agent."""
    data = {}
    for line in report_text.splitlines():
        if ':' in line:
            key, val = line.split(':', 1)
            key = key.strip()
            val = val.strip()
            try:
                data[key] = float(val)
            except ValueError:
                data[key] = None
    return data

def verify_regression_prediction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Paths
    metadata = task_info.get('metadata', {})
    dataset_path = metadata.get('dataset_path', "/home/ga/Documents/Jamovi/ExamAnxiety.csv")
    report_path = metadata.get('output_report_path', "/home/ga/Documents/Jamovi/prediction_report.txt")
    
    # Temp files
    temp_report = tempfile.NamedTemporaryFile(delete=False).name
    temp_csv = tempfile.NamedTemporaryFile(delete=False).name
    temp_result = tempfile.NamedTemporaryFile(delete=False).name
    
    score = 0
    feedback = []
    
    try:
        # 1. Get Task Result JSON
        copy_from_env("/tmp/task_result.json", temp_result)
        with open(temp_result) as f:
            task_result = json.load(f)
            
        # Check OMV existence (Proof of Analysis)
        if task_result.get("omv_exists") and task_result.get("omv_created_during_task"):
            score += 10
            feedback.append("Analysis file (.omv) created.")
        elif task_result.get("omv_exists"):
            score += 5
            feedback.append("Analysis file exists but old timestamp.")
        else:
            feedback.append("Analysis file (.omv) missing.")
            
        # Check Report existence
        if not task_result.get("report_exists"):
            return {"passed": False, "score": score, "feedback": "Prediction report file missing. " + " ".join(feedback)}
            
        # 2. Get Data and Compute Ground Truth
        copy_from_env(dataset_path, temp_csv)
        gt = calculate_ground_truth(temp_csv)
        
        if not gt["success"]:
            return {"passed": False, "score": 0, "feedback": f"Verification error: could not compute ground truth from data. {gt.get('error')}"}
            
        # 3. Parse Agent Report
        copy_from_env(report_path, temp_report)
        with open(temp_report, 'r') as f:
            report_text = f.read()
            
        agent_vals = parse_agent_report(report_text)
        
        # Verify Intercept (15pts)
        # Expected approx 87.67
        if "Intercept" in agent_vals and agent_vals["Intercept"] is not None:
            if abs(agent_vals["Intercept"] - gt["intercept"]) < 0.1:
                score += 15
                feedback.append(f"Intercept correct ({agent_vals['Intercept']}).")
            else:
                feedback.append(f"Intercept incorrect (Agent: {agent_vals['Intercept']}, True: {gt['intercept']:.2f}).")
        else:
            feedback.append("Intercept missing from report.")

        # Verify Slopes (15pts)
        # Revise approx 1.36, Anxiety approx -0.25
        slopes_ok = True
        if "Revise_B" in agent_vals and agent_vals["Revise_B"] is not None:
            if abs(agent_vals["Revise_B"] - gt["b_revise"]) > 0.1:
                slopes_ok = False
        else:
            slopes_ok = False
            
        if "Anxiety_B" in agent_vals and agent_vals["Anxiety_B"] is not None:
            if abs(agent_vals["Anxiety_B"] - gt["b_anxiety"]) > 0.1:
                slopes_ok = False
        else:
            slopes_ok = False
            
        if slopes_ok:
            score += 15
            feedback.append("Slope coefficients correct.")
        else:
            feedback.append("Slope coefficients incorrect or missing.")
            
        # Verify CI (20pts)
        # Revise Lower CI
        if "Revise_95_CI_Lower" in agent_vals and agent_vals["Revise_95_CI_Lower"] is not None:
            if abs(agent_vals["Revise_95_CI_Lower"] - gt["revise_ci_lower"]) < 0.1:
                score += 20
                feedback.append("Revise 95% CI Lower bound correct.")
            else:
                feedback.append(f"Revise CI Lower incorrect (Agent: {agent_vals['Revise_95_CI_Lower']}, True: {gt['revise_ci_lower']:.2f}).")
        else:
            feedback.append("Revise CI Lower missing.")

        # Verify Prediction Calculation (40pts)
        # Pred approx 88.6 (87.67 + 1.36*10 - 0.25*50) -> 87.67 + 13.6 - 12.5 = 88.77
        if "Predicted_Score" in agent_vals and agent_vals["Predicted_Score"] is not None:
            if abs(agent_vals["Predicted_Score"] - gt["predicted_score"]) < 0.5:
                score += 40
                feedback.append(f"Prediction calculation correct ({agent_vals['Predicted_Score']}).")
            else:
                feedback.append(f"Prediction calculation incorrect (Agent: {agent_vals['Predicted_Score']}, True: {gt['predicted_score']:.2f}).")
        else:
            feedback.append("Predicted_Score missing from report.")

        # Clean up
        for fpath in [temp_report, temp_csv, temp_result]:
            if os.path.exists(fpath):
                os.unlink(fpath)
                
        passed = score >= 65
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification exception: {str(e)}"}