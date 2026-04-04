#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import pandas as pd
import numpy as np
import re

def calculate_cronbach_alpha(df):
    """
    Calculate Cronbach's Alpha for a pandas DataFrame.
    """
    # Number of items
    k = df.shape[1]
    # Sum of item variances
    sum_item_vars = df.var(axis=0, ddof=1).sum()
    # Variance of total score
    total_var = df.sum(axis=1).var(ddof=1)
    
    if total_var == 0:
        return 0.0
        
    alpha = (k / (k - 1)) * (1 - (sum_item_vars / total_var))
    return alpha

def verify_psychometrics_scale_construction(traj, env_info, task_info):
    """
    Verify the psychometrics task:
    1. Report and OMV file existence.
    2. Correctness of Cronbach's Alpha (indicating proper reverse coding identification).
    3. Correctness of the calculated variable for the first participant (indicating proper formula).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_data = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')

    score = 0
    feedback = []
    
    try:
        # 1. Load Task Result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # 2. Check Files Existence
        if not result.get('omv_exists') or not result.get('report_exists'):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Missing required output files (OMV project or report text)."
            }
        
        score += 10
        feedback.append("Output files found.")

        # 3. Retrieve Data and Calculate Ground Truth
        # We need the raw data to verify the math
        copy_from_env(result['data_path'], temp_data.name)
        df = pd.read_csv(temp_data.name)
        
        # Extraversion Items: E1, E2, E3, E4, E5
        # Scale 1-6. E1 and E2 are reverse coded.
        # Reverse formula: 7 - x
        
        # Calculate Ground Truth Alpha
        # Reverse items E1 and E2 for the alpha calculation
        df_alpha = df[['E1', 'E2', 'E3', 'E4', 'E5']].copy()
        df_alpha['E1'] = 7 - df_alpha['E1']
        df_alpha['E2'] = 7 - df_alpha['E2']
        
        expected_alpha = calculate_cronbach_alpha(df_alpha)
        
        # Calculate Ground Truth Row 1 Score
        # Row 1 (index 0)
        row1 = df.iloc[0]
        # Formula: Mean of (7-E1, 7-E2, E3, E4, E5)
        e_items = [7 - row1['E1'], 7 - row1['E2'], row1['E3'], row1['E4'], row1['E5']]
        expected_score = sum(e_items) / 5.0

        feedback.append(f"Ground Truths -> Alpha: {expected_alpha:.3f}, Row1 Score: {expected_score:.2f}")

        # 4. Parse User Report
        copy_from_env(result['report_path'], temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
        
        # Extract values using regex
        # Expected format:
        # Corrected_Alpha: [value]
        # Row1_Score: [value]
        
        alpha_match = re.search(r"Alpha[:\s]+([0-9.]+)", report_content, re.IGNORECASE)
        score_match = re.search(r"Score[:\s]+([0-9.]+)", report_content, re.IGNORECASE)
        
        user_alpha = float(alpha_match.group(1)) if alpha_match else None
        user_score = float(score_match.group(1)) if score_match else None

        # 5. Evaluate Alpha (30 pts)
        if user_alpha is not None:
            if abs(user_alpha - expected_alpha) < 0.02:
                score += 30
                feedback.append("Reported Alpha is correct.")
            else:
                feedback.append(f"Reported Alpha ({user_alpha}) incorrect. Expected ~{expected_alpha:.3f}. (Did you reverse scale E1 and E2?)")
        else:
            feedback.append("Could not parse Alpha from report.")

        # 6. Evaluate Computed Score (50 pts)
        if user_score is not None:
            if abs(user_score - expected_score) < 0.1:
                score += 50
                feedback.append("Reported Row 1 Score is correct.")
            else:
                # Check common error: forgot to reverse code in formula
                raw_mean = df.iloc[0][['E1','E2','E3','E4','E5']].mean()
                if abs(user_score - raw_mean) < 0.1:
                    feedback.append("Reported Score matches raw mean. You likely forgot to apply the '7-x' formula to E1/E2 in the Compute Variable step.")
                else:
                    feedback.append(f"Reported Score ({user_score}) incorrect. Expected ~{expected_score:.2f}.")
        else:
            feedback.append("Could not parse Row1_Score from report.")

        # 7. OMV Validity Check (10 pts)
        # We just check if it's a valid zip and looks like a jamovi file
        try:
            copy_from_env(result['omv_path'], temp_omv.name)
            if zipfile.is_zipfile(temp_omv.name):
                with zipfile.ZipFile(temp_omv.name, 'r') as z:
                    if 'meta.json' in z.namelist() or 'index.json' in z.namelist():
                        score += 10
                        feedback.append("OMV file is valid.")
        except Exception:
            feedback.append("OMV file check failed.")

    except Exception as e:
        feedback.append(f"Verification error: {str(e)}")
    finally:
        # Cleanup
        for f in [temp_result, temp_report, temp_data, temp_omv]:
            if os.path.exists(f.name):
                os.unlink(f.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }