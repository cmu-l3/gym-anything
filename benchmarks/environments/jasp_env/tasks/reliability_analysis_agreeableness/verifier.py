#!/usr/bin/env python3
"""
Verifier for JASP Reliability Analysis Task.
Calculates ground truth metrics from the raw dataset and compares with user report.
"""

import json
import os
import sys
import tempfile
import logging
import re
import numpy as np
import pandas as pd

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_cronbach_alpha(df):
    """Calculate Cronbach's alpha for a DataFrame."""
    # Rows with NaN are usually dropped or handled pairwise. 
    # JASP default is often listwise deletion for the variables involved.
    df = df.dropna()
    item_scores = df.values
    item_variances = item_scores.var(axis=0, ddof=1)
    total_score_variance = item_scores.sum(axis=1).var(ddof=1)
    n_items = df.shape[1]
    
    if total_score_variance == 0:
        return 0.0
        
    alpha = (n_items / (n_items - 1)) * (1 - (item_variances.sum() / total_score_variance))
    return alpha

def parse_report(report_text):
    """Extract key-value pairs from the user's text report."""
    data = {}
    # Regex for various fields
    patterns = {
        "alpha": r"Cronbach'?s\s*Alpha[:\s]+([\d\.]+)",
        "omega": r"McDonald'?s\s*Omega[:\s]+([\d\.]+)",
        "mean": r"Scale\s*Mean[:\s]+([\d\.]+)",
        "sd": r"Scale\s*SD[:\s]+([\d\.]+)",
        "weakest_item": r"Weakest\s*Item[:\s]+([A-Za-z0-9]+)",
        "alpha_dropped": r"Alpha\s*If\s*Weakest\s*Dropped[:\s]+([\d\.]+)"
    }
    
    for key, pattern in patterns.items():
        match = re.search(pattern, report_text, re.IGNORECASE)
        if match:
            try:
                # Handle numeric conversion
                if key == "weakest_item":
                    data[key] = match.group(1).strip()
                else:
                    data[key] = float(match.group(1))
            except ValueError:
                data[key] = None
    return data

def verify_reliability_analysis(traj, env_info, task_info):
    """
    Verify the reliability analysis task.
    
    1. Validate files exist (project and report).
    2. Load dataset from env (to ensure ground truth).
    3. Calculate expected stats (accounting for reverse coding).
    4. Compare reported stats with expected stats.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Files to fetch
    RESULT_JSON_PATH = "/tmp/task_result.json"
    REPORT_PATH = "/home/ga/Documents/JASP/reliability_report.txt"
    DATASET_PATH = "/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"
    
    # Temporary files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    temp_data = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    
    try:
        # 1. Fetch Task Result JSON
        try:
            copy_from_env(RESULT_JSON_PATH, temp_result)
            with open(temp_result, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
            
        # Check files existence
        if task_result.get("project_exists") and task_result.get("project_created_during_task"):
            score += 10
            feedback_parts.append("JASP project file saved.")
        else:
            feedback_parts.append("JASP project file missing or not saved.")
            
        if task_result.get("report_exists") and task_result.get("report_created_during_task"):
            score += 10
            feedback_parts.append("Report file saved.")
        else:
            feedback_parts.append("Report file missing.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # 2. Fetch and Parse Report
        try:
            copy_from_env(REPORT_PATH, temp_report)
            with open(temp_report, 'r') as f:
                report_content = f.read()
            reported_data = parse_report(report_content)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read report: {str(e)}"}

        # 3. Calculate Ground Truth
        try:
            copy_from_env(DATASET_PATH, temp_data)
            df_full = pd.read_csv(temp_data)
            
            # Select Agreeableness items
            items = ["A1", "A2", "A3", "A4", "A5"]
            df = df_full[items].copy()
            
            # Handle missing values (listwise deletion is standard for Alpha)
            df = df.dropna()
            
            # Calculate metrics WITHOUT reverse coding (Trap Check)
            alpha_raw = calculate_cronbach_alpha(df)
            
            # Apply Reverse Coding to A1 (Scale 1-6 -> 7 - x)
            df['A1'] = 7 - df['A1']
            
            # Calculate CORRECT metrics
            alpha_true = calculate_cronbach_alpha(df)
            
            # Calculate Scale Mean and SD
            # Scale score = mean of items (standard in JASP) or sum? 
            # JASP "Scale Mean" usually refers to the mean of the sum scores or mean of means.
            # Let's check JASP defaults. JASP Descriptive Statistics for Scale usually gives Mean of the *sum scores* or the items?
            # Actually, typically "Scale Mean" in reliability output refers to the mean of the composite score.
            # If "Scale" is sum of items:
            df['score'] = df.sum(axis=1)
            scale_mean = df['score'].mean()
            scale_sd = df['score'].std(ddof=1)
            
            # McDonald's Omega is harder to calc manually without factor analysis library.
            # We will use a flexible tolerance or proxy check, or rely on Alpha as the primary rigorous check.
            # However, we can approximate or use pre-calculated known values for this standard dataset if calculation is complex.
            # Using standard known value for Big5 A-scale with A1 reversed: Omega is typically close to Alpha.
            # For this verification, we will verify Alpha strictly. Omega we'll check range.
            # Ground truth for this dataset (bfi): Alpha ~ 0.70-0.72.
            
            # Calculate "If Item Dropped"
            if_dropped = {}
            for drop_col in items:
                temp_cols = [c for c in items if c != drop_col]
                temp_df = df[temp_cols]
                if_dropped[drop_col] = calculate_cronbach_alpha(temp_df)
            
            # Identify weakest item (dropping it increases Alpha the most, or decreases it the least if all good)
            # Usually "weakest" means the one that, if dropped, results in highest Alpha.
            best_drop_item = max(if_dropped, key=if_dropped.get)
            best_drop_val = if_dropped[best_drop_item]

        except Exception as e:
            logger.error(f"Calculation error: {e}")
            return {"passed": False, "score": score, "feedback": f"Verifier calculation error: {str(e)}"}

        # 4. Compare Values
        
        # Check Cronbach's Alpha (Critical)
        rep_alpha = reported_data.get("alpha")
        if rep_alpha is not None:
            if abs(rep_alpha - alpha_true) < 0.02:
                score += 25
                feedback_parts.append(f"Correct Alpha ({rep_alpha}).")
            elif abs(rep_alpha - alpha_raw) < 0.02:
                feedback_parts.append(f"Incorrect Alpha ({rep_alpha}). It matches the value WITHOUT reverse coding A1. Did you reverse code A1?")
            else:
                feedback_parts.append(f"Incorrect Alpha. Expected ~{alpha_true:.3f}, got {rep_alpha}.")
        else:
            feedback_parts.append("Alpha not found in report.")

        # Check Omega (Lenient check)
        rep_omega = reported_data.get("omega")
        if rep_omega is not None:
            # Omega is usually slightly higher than Alpha
            if abs(rep_omega - alpha_true) < 0.1: 
                score += 15
                feedback_parts.append(f"Omega present ({rep_omega}).")
            else:
                feedback_parts.append(f"Omega value suspicious ({rep_omega}).")
        else:
            feedback_parts.append("Omega not found.")

        # Check Mean/SD
        rep_mean = reported_data.get("mean")
        rep_sd = reported_data.get("sd")
        if rep_mean and abs(rep_mean - scale_mean) < 1.0:
            score += 5
            feedback_parts.append("Mean correct.")
        if rep_sd and abs(rep_sd - scale_sd) < 1.0:
            score += 5
            feedback_parts.append("SD correct.")
            
        # Check Weakest Item
        rep_weak = reported_data.get("weakest_item")
        if rep_weak:
            if rep_weak.upper() == best_drop_item.upper():
                score += 15
                feedback_parts.append(f"Correctly identified weakest item ({rep_weak}).")
            else:
                feedback_parts.append(f"Wrong weakest item. Expected {best_drop_item}, got {rep_weak}.")
        
        # Check Alpha if dropped
        rep_alpha_drop = reported_data.get("alpha_dropped")
        if rep_alpha_drop is not None:
            if abs(rep_alpha_drop - best_drop_val) < 0.02:
                score += 15
                feedback_parts.append("Correct 'Alpha if dropped' value.")
            else:
                feedback_parts.append(f"Incorrect 'Alpha if dropped'. Expected ~{best_drop_val:.3f}, got {rep_alpha_drop}.")

    finally:
        # Cleanup
        for fpath in [temp_result, temp_report, temp_data]:
            if os.path.exists(fpath):
                os.unlink(fpath)

    passed = score >= 60 and "Correct Alpha" in " ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }