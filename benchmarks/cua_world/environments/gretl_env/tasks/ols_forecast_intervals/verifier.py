#!/usr/bin/env python3
"""
Verifier for ols_forecast_intervals task.

Checks:
1. Script file exists and contains valid commands (ols, addobs, fcast).
2. Results file exists and contains expected output.
3. Coefficients match ground truth.
4. Forecasts match ground truth.
5. Prediction intervals are present.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ols_forecast_intervals(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    script_content = result.get('script_content', '')
    results_content = result.get('results_content', '')
    ground_truth = result.get('ground_truth', {})
    
    # Fallback to metadata if ground truth missing
    metadata = task_info.get('metadata', {}).get('expected_values', {})
    gt_b0 = ground_truth.get('b0', metadata.get('intercept', 83.416))
    gt_b1 = ground_truth.get('b1', metadata.get('slope', 10.2096))
    gt_f15 = ground_truth.get('f15', metadata.get('forecast_15', 236.56))
    gt_f20 = ground_truth.get('f20', metadata.get('forecast_20', 287.61))
    gt_f25 = ground_truth.get('f25', metadata.get('forecast_25', 338.66))

    score = 0
    feedback_parts = []
    
    # Criterion 1: Script Validation (25 pts)
    script_valid = False
    if result.get('script_exists') and result.get('script_new'):
        # Check for keywords
        has_ols = re.search(r'\bols\b', script_content, re.IGNORECASE)
        has_fcast = re.search(r'\bfcast\b|\bforecast\b', script_content, re.IGNORECASE)
        has_addobs = re.search(r'\baddobs\b|\bdataset add\b', script_content, re.IGNORECASE)
        
        if has_ols and has_fcast and has_addobs:
            score += 25
            script_valid = True
            feedback_parts.append("Script contains all required commands.")
        elif has_ols:
            score += 10
            feedback_parts.append("Script has OLS but missing forecast/data steps.")
        else:
            feedback_parts.append("Script file exists but missing key commands.")
    else:
        feedback_parts.append("Script file not found or not created during task.")

    # Criterion 2: Results File Existence (10 pts)
    if result.get('results_exists') and result.get('results_new') and len(results_content) > 100:
        score += 10
        feedback_parts.append("Results file exists.")
    else:
        feedback_parts.append("Results file missing or empty.")

    # Criterion 3: Coefficients (20 pts)
    # Search for numbers near the coefficients in the results text
    # e.g. "const 83.416" or just the number appearing
    coeffs_found = 0
    
    # Flexible regex for numbers
    def find_val(text, target, tol=1.0):
        # Look for the number with some context or just the number with word boundaries
        # Note: formatting can vary widely, so we search for float patterns and check proximity
        floats = [float(x) for x in re.findall(r'-?\d+\.\d+', text)]
        for f in floats:
            if abs(f - target) <= tol:
                return True
        return False

    if find_val(results_content, gt_b0, 1.0):
        coeffs_found += 1
    if find_val(results_content, gt_b1, 0.5):
        coeffs_found += 1
        
    if coeffs_found == 2:
        score += 20
        feedback_parts.append("OLS coefficients correct.")
    elif coeffs_found == 1:
        score += 10
        feedback_parts.append("One OLS coefficient correct.")
    else:
        feedback_parts.append("OLS coefficients not found in results.")

    # Criterion 4: Point Forecasts (25 pts)
    forecasts_found = 0
    if find_val(results_content, gt_f15, 2.0): forecasts_found += 1
    if find_val(results_content, gt_f20, 2.0): forecasts_found += 1
    if find_val(results_content, gt_f25, 2.0): forecasts_found += 1
    
    if forecasts_found == 3:
        score += 25
        feedback_parts.append("All forecasts correct.")
    elif forecasts_found > 0:
        score += 10
        feedback_parts.append(f"{forecasts_found}/3 forecasts correct.")
    else:
        feedback_parts.append("Forecasts values not found.")

    # Criterion 5: Prediction Intervals (20 pts)
    # Look for interval keywords or table structure (multi-column output for forecasts)
    # fcast usually outputs: Obs, Forecast, std err, 95% Low, 95% High
    # So we look for the forecast value followed by two other numbers that bracket it
    has_intervals = False
    
    # Check for keywords
    if re.search(r'confidence|interval|lower|upper|95\%', results_content, re.IGNORECASE):
        has_intervals = True
    # Or check for the table structure: 3 rows with 4+ columns
    elif len(re.findall(r'\d+\s+\d+\.\d+\s+\d+\.\d+\s+\d+\.\d+\s+\d+\.\d+', results_content)) >= 3:
        has_intervals = True
        
    if has_intervals:
        score += 20
        feedback_parts.append("Prediction intervals present.")
    else:
        feedback_parts.append("Prediction intervals not clearly found.")

    passed = (score >= 60) and script_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }