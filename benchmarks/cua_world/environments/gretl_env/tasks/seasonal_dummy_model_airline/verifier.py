#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_seasonal_dummy_model_airline(traj, env_info, task_info):
    """
    Verifies the seasonal decomposition task.
    
    Criteria:
    1. Output file exists and was created during the task.
    2. Model dependent variable is log-transformed (values < 10, not > 100).
    3. Time trend coefficient is approx 0.010 (1% monthly growth).
    4. Seasonal dummies are present (at least 10 coefficients besides const/trend).
    5. F-test result is present (seasonality is significant).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Check 1: File Existence & Timing (20 pts)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file seasonal_analysis.txt not found."}
    
    if not result_data.get("file_created_during_task", False):
        feedback.append("Warning: Output file timestamp is outside task window.")
        # We penalize but don't fail immediately if it exists
    else:
        score += 20
        feedback.append("Output file created successfully.")

    # Fetch the content of the analysis file
    output_content = ""
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Documents/gretl_output/seasonal_analysis.txt", temp_output.name)
        with open(temp_output.name, 'r', encoding='utf-8', errors='ignore') as f:
            output_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Could not read output file content: {str(e)}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # Check 2: Data Transformation (Log) (25 pts)
    # The intercept for raw data (112-622 range) would be negative or small, 
    # but for log data (4.7-6.4 range), intercept is approx 4.7-4.8.
    # Also check variable names.
    
    # Look for dependent variable line
    dep_var_match = re.search(r"Dependent variable: (\w+)", output_content, re.IGNORECASE)
    is_log = False
    
    # Heuristic 1: Variable name
    if dep_var_match:
        dep_var = dep_var_match.group(1).lower()
        if "l_" in dep_var or "log" in dep_var:
            is_log = True
            feedback.append(f"Dependent variable '{dep_var}' indicates log transformation.")
    
    # Heuristic 2: Coefficient magnitudes
    # Find constant coefficient. Pattern: "const" followed by number
    const_match = re.search(r"const\s+([0-9]+\.[0-9]+)", output_content)
    if const_match:
        const_val = float(const_match.group(1))
        # Log model const ~ 4.7-4.8
        # Linear model const ~ 80-100
        if 4.0 < const_val < 6.0:
            is_log = True
            feedback.append(f"Constant coefficient ({const_val}) is consistent with log transformation.")
            score += 25
        elif const_val > 50:
            feedback.append(f"Constant coefficient ({const_val}) suggests RAW data was used, not log transformed.")
    else:
        feedback.append("Could not parse regression coefficients.")

    if not is_log:
        feedback.append("Failed to detect log transformation.")

    # Check 3: Time Trend (20 pts)
    # Expected: ~0.010
    trend_found = False
    trend_match = re.search(r"(time|trend|t)\s+([0-9]+\.[0-9]+)", output_content, re.IGNORECASE)
    if trend_match:
        trend_coeff = float(trend_match.group(2))
        if 0.008 <= trend_coeff <= 0.012:
            score += 20
            trend_found = True
            feedback.append(f"Time trend coefficient ({trend_coeff}) is correct.")
        else:
            feedback.append(f"Time trend found but coefficient ({trend_coeff}) is outside expected range (~0.010).")
    else:
        feedback.append("Time trend variable not found in regression output.")

    # Check 4: Seasonal Dummies (20 pts)
    # Count lines with coefficients that look like dummies (dm_*, S*, etc)
    # We expect 11 dummies (12 months - 1 base)
    lines = output_content.split('\n')
    dummy_count = 0
    for line in lines:
        if re.search(r"(dm_|dq_|S[0-9]|month)", line, re.IGNORECASE) and re.search(r"[0-9]+\.[0-9]+", line):
            dummy_count += 1
            
    if dummy_count >= 10:
        score += 20
        feedback.append(f"Found {dummy_count} seasonal dummy variables.")
    else:
        feedback.append(f"Found only {dummy_count} seasonal dummies (expected >= 10).")

    # Check 5: F-test / Seasonality Significance (15 pts)
    # Look for "F-statistic" or "Test for null"
    # Or specifically "F(11, 131)" or similar degrees of freedom
    if "F-statistic" in output_content or "F(" in output_content or "Analysis of Variance" in output_content:
        score += 15
        feedback.append("Hypothesis test results detected.")
    else:
        feedback.append("No hypothesis test (F-statistic) detected in output.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }