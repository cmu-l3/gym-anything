#!/usr/bin/env python3
"""
Verifier for Davidson-MacKinnon J-Test Manual Task.
Checks existence and content of two auxiliary regression output files.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gretl_output(content):
    """
    Parses gretl regression output to extract coefficients and t-stats.
    Returns a dictionary of {variable_name: {'coeff': float, 't_stat': float}}.
    """
    results = {}
    # Regex to capture regression table lines
    # Example line: " const        83.4160      43.4101      1.922      0.0622   *"
    # Or: " income       10.2096       2.09326     4.877      1.91e-05 ***"
    # We look for lines starting with a variable name followed by 4 or 5 numbers.
    
    lines = content.split('\n')
    parsing_coeffs = False
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # Detect start of coefficient block (usually has "coefficient" header)
        if "coefficient" in line.lower() and "std. error" in line.lower():
            parsing_coeffs = True
            continue
        
        if parsing_coeffs:
            # Stop parsing if we hit summary stats (e.g., "Mean dependent var")
            if "Mean dependent var" in line or "Sum squared resid" in line:
                parsing_coeffs = False
                continue
                
            parts = line.split()
            if len(parts) >= 5:
                try:
                    # Try to parse the numbers. 
                    # Structure: Name Coeff StdErr t-ratio p-value [stars]
                    var_name = parts[0]
                    coeff = float(parts[1])
                    t_stat = float(parts[3])
                    results[var_name] = {'coeff': coeff, 't_stat': t_stat}
                except ValueError:
                    continue
                    
    return results

def verify_davidson_mackinnon_j_test_manual(traj, env_info, task_info):
    """
    Verifies the J-Test task.
    
    Criteria:
    1. aux_linear.txt exists and was created during task.
    2. aux_linear.txt contains regression of food_exp on const, income, and yhat_log.
       - Check coefficient of fitted value term (~0.30).
    3. aux_log.txt exists and was created during task.
    4. aux_log.txt contains regression of food_exp on const, l_income, and yhat_linear.
       - Check coefficient of fitted value term (~0.72).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_linear_path = metadata.get('output_linear')
    expected_log_path = metadata.get('output_log')
    
    # Ground truth values
    exp_coeff_lin = metadata.get('expected_coeff_aux_linear_fitted', 0.30)
    exp_coeff_log = metadata.get('expected_coeff_aux_log_fitted', 0.72)
    tol = metadata.get('tolerance_coeff', 0.15)

    score = 0
    max_score = 100
    feedback_parts = []

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ---------------------------------------------------------
    # CHECK AUX LINEAR (Testing Model A)
    # ---------------------------------------------------------
    linear_ok = False
    if result_data.get('aux_linear_exists') and result_data.get('aux_linear_created_during_task'):
        score += 10 # File exists
        
        # Read file content
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(expected_linear_path, temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                content_linear = f.read()
            
            # Check content
            if "OLS" in content_linear and "food_exp" in content_linear:
                score += 10 # Is a regression output
                
                parsed_linear = parse_gretl_output(content_linear)
                
                # We expect: const, income, and a fitted value term
                # The fitted term name depends on what the agent named it (e.g., yhat_log, yhat_B)
                # Strategy: Find variable that is NOT const or income
                fitted_var_linear = None
                for var in parsed_linear:
                    if var.lower() not in ['const', 'income']:
                        fitted_var_linear = var
                        break
                
                if fitted_var_linear:
                    val = parsed_linear[fitted_var_linear]['coeff']
                    if abs(val - exp_coeff_lin) < tol:
                        score += 30 # Correct coefficient
                        linear_ok = True
                        feedback_parts.append(f"Aux Linear: Correct fitted term coeff ({val:.4f}).")
                    else:
                        feedback_parts.append(f"Aux Linear: Fitted term coeff mismatch (Got {val:.4f}, Exp ~{exp_coeff_lin}).")
                else:
                    feedback_parts.append("Aux Linear: Could not identify fitted value regressor.")
            else:
                feedback_parts.append("Aux Linear: Not a valid regression output.")
        except Exception as e:
            feedback_parts.append(f"Aux Linear error: {str(e)}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)
    else:
        feedback_parts.append("Aux Linear output missing or not created during task.")

    # ---------------------------------------------------------
    # CHECK AUX LOG (Testing Model B)
    # ---------------------------------------------------------
    log_ok = False
    if result_data.get('aux_log_exists') and result_data.get('aux_log_created_during_task'):
        score += 10 # File exists
        
        # Read file content
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(expected_log_path, temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                content_log = f.read()
            
            # Check content
            if "OLS" in content_log and "food_exp" in content_log:
                score += 10 # Is a regression output
                
                parsed_log = parse_gretl_output(content_log)
                
                # We expect: const, l_income (or similar), and a fitted value term
                # Strategy: Find variable that is NOT const and NOT starting with l_income/log/ln
                # BUT the agent might name the log variable anything. 
                # Better: Look for the fitted term which should match the linear prediction.
                # The linear prediction coefficient in this eq should be ~0.72.
                
                fitted_var_log = None
                
                # Heuristic: Find variable with coeff closest to 0.72
                best_match_var = None
                min_diff = float('inf')
                
                for var in parsed_log:
                    if var.lower() == 'const': continue
                    val = parsed_log[var]['coeff']
                    diff = abs(val - exp_coeff_log)
                    if diff < min_diff:
                        min_diff = diff
                        best_match_var = var
                
                if best_match_var and min_diff < tol:
                    score += 30 # Correct coefficient found
                    log_ok = True
                    feedback_parts.append(f"Aux Log: Correct fitted term coeff found ({parsed_log[best_match_var]['coeff']:.4f}).")
                else:
                    feedback_parts.append(f"Aux Log: No coefficient matched expected ~{exp_coeff_log} (Best match diff: {min_diff:.4f}).")

            else:
                feedback_parts.append("Aux Log: Not a valid regression output.")
        except Exception as e:
            feedback_parts.append(f"Aux Log error: {str(e)}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)
    else:
        feedback_parts.append("Aux Log output missing or not created during task.")

    # Pass if at least one side of the test was done correctly (partial credit allowed, but threshold is high)
    # Threshold 70 means getting at least one fully right (10+10+30 = 50) isn't enough.
    # Needs both files present (10+10+10+10 = 40) + at least one correct value (30) = 70.
    # Or almost both correct.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }