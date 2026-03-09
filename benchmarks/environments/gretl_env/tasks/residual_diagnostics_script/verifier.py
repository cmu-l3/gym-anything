#!/usr/bin/env python3
"""
Verifier for residual_diagnostics_script task.

Scoring Criteria:
1. Script file exists and executes successfully (25 pts)
2. Residual vs Fitted plot created (15 pts)
3. Residual Histogram created (15 pts)
4. Report file contains correct OLS coefficients (20 pts)
5. Report file contains R-squared (10 pts)
6. Report file contains Normality Test results (15 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_residual_diagnostics_script(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vals = metadata.get('expected_values', {})
    tolerances = metadata.get('tolerance', {})
    
    score = 0
    feedback = []
    
    # 1. Retrieve JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Report File for Content Analysis
    report_content = ""
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        if result.get('report_exists'):
            copy_from_env(metadata['report_path'], temp_report.name)
            with open(temp_report.name, 'r', errors='ignore') as f:
                report_content = f.read()
    except Exception:
        pass # Report might not exist
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # --- SCORING ---

    # Criterion 1: Script Validity (25 pts)
    if result.get('script_exists'):
        if result.get('script_valid'):
            score += 25
            feedback.append("Script exists and executes successfully.")
        else:
            score += 10
            feedback.append("Script exists but failed to execute (syntax error?).")
    else:
        feedback.append("Script file not found.")

    # Criterion 2: Plots (30 pts total)
    if result.get('plot1_valid'):
        score += 15
        feedback.append("Residual vs Fitted plot created.")
    else:
        feedback.append("Residual vs Fitted plot missing or empty.")

    if result.get('plot2_valid'):
        score += 15
        feedback.append("Residual Histogram created.")
    else:
        feedback.append("Residual Histogram missing or empty.")

    # Criterion 3: Report Content (45 pts total)
    if result.get('report_exists') and result.get('report_created_during_task'):
        # Check Coefficients (20 pts)
        # Regex to find numbers near keywords or just floating point numbers
        # We look for numbers roughly matching 83.4 and 10.2
        
        # Intercept ~ 83.42
        intercept_found = False
        slope_found = False
        
        floats = [float(x) for x in re.findall(r"-?\d+\.\d+", report_content)]
        
        for num in floats:
            if abs(num - expected_vals.get('intercept', 83.42)) < tolerances.get('coeff', 1.0):
                intercept_found = True
            if abs(num - expected_vals.get('slope', 10.21)) < tolerances.get('coeff', 1.0):
                slope_found = True
        
        if intercept_found and slope_found:
            score += 20
            feedback.append("Report contains correct OLS coefficients.")
        elif intercept_found or slope_found:
            score += 10
            feedback.append("Report contains partial coefficient data.")
        else:
            feedback.append("Report does not appear to contain correct coefficients.")

        # Check R-squared (10 pts)
        r2_found = False
        for num in floats:
            if abs(num - expected_vals.get('r_squared', 0.385)) < tolerances.get('r_squared', 0.05):
                r2_found = True
                break
        
        if r2_found:
            score += 10
            feedback.append("Report contains correct R-squared.")
        
        # Check Normality Test (15 pts)
        # Look for keywords like "Jarque-Bera", "Normality", "JB", "p-value"
        if re.search(r"Jarque-Bera|Normality|JB", report_content, re.IGNORECASE):
            score += 15
            feedback.append("Report contains Normality test results.")
        else:
            feedback.append("Report missing Normality test keywords.")

    else:
        feedback.append("Report file missing or not created during task.")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }