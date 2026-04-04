#!/usr/bin/env python3
"""
Verifier for reset_functional_form task.

Verifies:
1. Output file exists and was created during task
2. File contains Linear Model results (correct coeffs)
3. File contains RESET test results
4. File contains Log-Linear Model results (correct coeffs)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reset_functional_form(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/gretl_output/reset_comparison.txt')
    
    # Tolerances and Expected Values
    exp_lin_int = metadata.get('linear_intercept', 83.42)
    exp_lin_slope = metadata.get('linear_slope', 10.21)
    exp_lin_r2 = metadata.get('linear_r2', 0.385)
    exp_log_int = metadata.get('log_intercept', 3.69)
    exp_log_elas = metadata.get('log_elasticity', 0.38)
    exp_log_r2 = metadata.get('log_r2', 0.36)
    
    tols = metadata.get('tolerances', {})
    tol_int = tols.get('intercept', 10.0)
    tol_slope = tols.get('slope', 2.0)
    tol_r2 = tols.get('r2', 0.10)
    tol_log_int = tols.get('log_intercept', 0.5)
    tol_log_slope = tols.get('log_slope', 0.10)
    tol_log_r2 = tols.get('log_r2', 0.15)

    score = 0
    feedback_parts = []
    
    # 1. Get task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check file existence and creation
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created"}
    
    if not result_data.get('file_created_during_task', False):
        feedback_parts.append("Warning: Output file timestamp indicates it wasn't created during this run")
        # We penalize but don't fail immediately, in case clock sync issues
    else:
        score += 10
        feedback_parts.append("Output file created successfully")

    if result_data.get('output_size_bytes', 0) < 50:
        return {"passed": False, "score": score, "feedback": "Output file is empty or too small"}
    else:
        score += 5

    # 3. Get and Parse Output Content
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(expected_path, temp_output.name)
        with open(temp_output.name, 'r', errors='ignore') as f:
            content = f.read()
            content_lower = content.lower()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve output file content: {e}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # --- Verification Logic ---
    
    # Check for Linear Model Variables
    if "food_exp" in content_lower and "income" in content_lower:
        score += 10
        feedback_parts.append("Linear model variables found")
    else:
        feedback_parts.append("Linear model variables missing")

    # Extract coefficients (generic number extraction near keywords)
    # Strategy: Find lines with 'const' or 'income' and extract numbers
    
    def extract_val(pattern, text):
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return float(match.group(1))
        return None

    # Linear Intercept
    # Look for: const ... 83.4
    # We use a broad regex to catch typical regression output formats
    lin_int_match = extract_val(r"(?:const|intercept|_cons).*?([\-]?\d+\.\d+)", content)
    if lin_int_match and (exp_lin_int - tol_int <= lin_int_match <= exp_lin_int + tol_int):
        score += 10
        feedback_parts.append(f"Linear intercept correct ({lin_int_match})")
    elif lin_int_match:
        feedback_parts.append(f"Linear intercept incorrect ({lin_int_match})")
    
    # Linear Slope (income)
    # Look for: income ... 10.2
    # Ensure we don't match l_income lines if possible, but first occurrences usually work for linear
    lin_slope_match = extract_val(r"^\s*income.*?([\-]?\d+\.\d+)", content) # anchor start of line to avoid l_income
    if not lin_slope_match:
         # Try simpler if not start of line
         lin_slope_match = extract_val(r"\bincome\b.*?([\-]?\d+\.\d+)", content)

    if lin_slope_match and (exp_lin_slope - tol_slope <= lin_slope_match <= exp_lin_slope + tol_slope):
        score += 10
        feedback_parts.append(f"Linear slope correct ({lin_slope_match})")
    else:
        feedback_parts.append("Linear slope incorrect or not found")

    # Linear R-squared
    # First R2 in file is likely linear
    r2_matches = re.findall(r"r-squared\s*[:=]?\s*(\d+\.\d+)", content, re.IGNORECASE)
    if r2_matches:
        r2_val = float(r2_matches[0])
        if exp_lin_r2 - tol_r2 <= r2_val <= exp_lin_r2 + tol_r2:
            score += 5
            feedback_parts.append("Linear R2 correct")
    
    # RESET Test
    if "reset" in content_lower and ("p-value" in content_lower or "prob" in content_lower):
        score += 15
        feedback_parts.append("RESET test results found")
    else:
        feedback_parts.append("RESET test results missing")

    # Log-Log Model Variables
    if re.search(r"(l_food_exp|log_food_exp|ln_food_exp)", content_lower) and \
       re.search(r"(l_income|log_income|ln_income)", content_lower):
        score += 10
        feedback_parts.append("Log-linear model variables found")
    
    # Log-Log Intercept
    # We look for the last instance of 'const' if there are multiple models
    const_matches = re.findall(r"(?:const|intercept|_cons).*?([\-]?\d+\.\d+)", content, re.IGNORECASE)
    if len(const_matches) >= 2:
        log_int_val = float(const_matches[-1])
        if exp_log_int - tol_log_int <= log_int_val <= exp_log_int + tol_log_int:
            score += 10
            feedback_parts.append(f"Log-linear intercept correct ({log_int_val})")
    
    # Log-Log Elasticity
    log_slope_match = extract_val(r"(?:l_income|log_income|ln_income).*?([\-]?\d+\.\d+)", content)
    if log_slope_match and (exp_log_elas - tol_log_slope <= log_slope_match <= exp_log_elas + tol_log_slope):
        score += 10
        feedback_parts.append(f"Log-linear elasticity correct ({log_slope_match})")
    
    # Log-Log R2
    if len(r2_matches) >= 2:
        log_r2_val = float(r2_matches[-1])
        if exp_log_r2 - tol_log_r2 <= log_r2_val <= exp_log_r2 + tol_log_r2:
            score += 5
            feedback_parts.append("Log-linear R2 correct")

    # Structure check (multiple models)
    if len(re.findall(r"Model \d+:", content)) >= 2 or len(r2_matches) >= 2:
        score += 5
        feedback_parts.append("Multiple models detected")

    # Pass logic
    passed = score >= 60 and "RESET test results found" in feedback_parts
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }