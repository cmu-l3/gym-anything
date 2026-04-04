#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import re
import pandas as pd
import numpy as np
from scipy import stats

def verify_feature_engineering_correlation(traj, env_info, task_info):
    """
    Verifies that the agent correctly computed the 'Plasticity' variable 
    and analyzed its correlation with 'Agreeableness'.
    
    Verification steps:
    1. Retrieve the dataset and report from the environment.
    2. Re-calculate the ground truth:
       - Plasticity = (Extraversion + Openness) / 2
       - Mean(Plasticity)
       - Pearson r(Plasticity, Agreeableness)
    3. Parse the agent's text report.
    4. Compare values with tolerance.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp files for data extraction
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name

    score = 0
    feedback_parts = []
    passed = False

    try:
        # 1. Load Task Result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

        # Check if files exist and were created during task
        if not result_data.get("file_created_during_task", False):
            return {"passed": False, "score": 0, "feedback": "No new output files created during task session."}

        report_exists = result_data.get("report_exists", False)
        jasp_exists = result_data.get("jasp_exists", False)
        
        if jasp_exists:
            score += 10
            feedback_parts.append("JASP project file created.")
        
        if not report_exists:
            feedback_parts.append("Report file missing.")
            return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}
        
        score += 10
        feedback_parts.append("Report file found.")

        # 2. Compute Ground Truth
        dataset_path = result_data.get("dataset_path", "/home/ga/Documents/JASP/BigFivePersonalityTraits.csv")
        try:
            copy_from_env(dataset_path, temp_csv)
            df = pd.read_csv(temp_csv)
            
            # Feature Engineering: Plasticity = (Extraversion + Openness) / 2
            # Handle potential column name differences if JASP modified headers (usually it doesn't for CSVs)
            # Standardizing to what JASP usually imports
            cols = {c.lower(): c for c in df.columns}
            
            if 'extraversion' not in cols and 'Extraversion' not in df.columns:
                 return {"passed": False, "score": 0, "feedback": "Could not find expected columns in dataset for verification."}
            
            # Safe column access
            extraversion = df[cols.get('extraversion', 'Extraversion')]
            openness = df[cols.get('openness', 'Openness')]
            agreeableness = df[cols.get('agreeableness', 'Agreeableness')]
            
            # Compute Plasticity
            plasticity = (extraversion + openness) / 2
            
            # Ground Truth Statistics
            gt_mean = plasticity.mean()
            gt_corr, gt_p = stats.pearsonr(plasticity, agreeableness)
            
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Verification error computing ground truth: {e}"}

        # 3. Parse Agent Report
        report_b64 = result_data.get("report_content_b64", "")
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8')
        except:
            report_text = ""
            
        # Extract numbers from text using regex
        # Look for floating point numbers
        numbers = re.findall(r"[-+]?\d*\.\d+|\d+", report_text)
        floats = [float(n) for n in numbers]
        
        # We need to find values close to gt_mean and gt_corr
        # gt_mean is approx (3+3)/2 = 3ish. 
        # gt_corr is between -1 and 1.
        
        mean_found = False
        corr_found = False
        
        # Check Mean (Tolerance 0.05)
        for val in floats:
            if abs(val - gt_mean) < 0.05:
                mean_found = True
                break
        
        # Check Correlation (Tolerance 0.05)
        for val in floats:
            if abs(val - gt_corr) < 0.05:
                corr_found = True
                break
                
        if mean_found:
            score += 30
            feedback_parts.append(f"Correct Mean reported (expected ~{gt_mean:.3f}).")
        else:
            feedback_parts.append(f"Incorrect Mean reported. Expected ~{gt_mean:.3f}.")
            
        if corr_found:
            score += 30
            feedback_parts.append(f"Correct Correlation reported (expected ~{gt_corr:.3f}).")
        else:
            feedback_parts.append(f"Incorrect Correlation reported. Expected ~{gt_corr:.3f}.")
            
        # Check P-value presence (simple check if any low number or 'p' mentioned, 
        # but since we already check exact numbers, we'll verify if the p-value is close)
        # Often p-values are < 0.001, printed as 0.001 or similar.
        # If gt_p is very small, we look for 0.001 or 0.0
        p_val_correct = False
        if gt_p < 0.001:
            if "0.001" in report_text or "<.001" in report_text or "< 0.001" in report_text or "0.000" in report_text:
                p_val_correct = True
        else:
            for val in floats:
                if abs(val - gt_p) < 0.05:
                    p_val_correct = True
                    break
        
        if p_val_correct:
            score += 20
            feedback_parts.append("P-value reported correctly.")
        else:
            feedback_parts.append(f"P-value incorrect/missing (Expected ~{gt_p:.3f}).")

        # Pass threshold
        if score >= 70:
            passed = True
            
    finally:
        if os.path.exists(temp_result_json):
            os.remove(temp_result_json)
        if os.path.exists(temp_csv):
            os.remove(temp_csv)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }