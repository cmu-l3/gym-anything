#!/usr/bin/env python3
"""
Verifier for matrix_ols_manual task.

Checks:
1. Result file exists and parses correctly.
2. Script file exists and does NOT contain 'ols' command.
3. Script contains matrix operations.
4. Numerical accuracy of coefficients, SEs, and R-squared against ground truth.
"""

import json
import os
import re
import tempfile
import math

def parse_results_file(content):
    """Parses the key: value format of the results file."""
    data = {}
    for line in content.splitlines():
        if ':' in line:
            key, val = line.split(':', 1)
            key = key.strip().lower()
            try:
                data[key] = float(val.strip())
            except ValueError:
                continue
    return data

def verify_matrix_ols_manual(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata / Ground Truth
    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {
        "intercept": 83.416,
        "slope": 10.2096,
        "se_intercept": 43.410,
        "se_slope": 2.093,
        "r_squared": 0.385
    })
    tolerance = metadata.get('tolerance', {
        "coef": 1.0,
        "se": 0.5,
        "r2": 0.05
    })

    score = 0
    max_score = 100
    feedback = []

    # 1. Retrieve task_result.json
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Creation
    if not task_result.get('result_file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Results file not found."}
    
    if not task_result.get('result_created_during_task', False):
        feedback.append("Warning: Results file timestamp indicates it wasn't created during this run.")
        # We'll continue but this is suspicious
    else:
        score += 10 # Points for creating the file

    # 3. Retrieve and Parse Results File
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    parsed_data = {}
    try:
        copy_from_env("/home/ga/Documents/gretl_output/matrix_ols_results.txt", temp_res.name)
        with open(temp_res.name, 'r') as f:
            content = f.read()
            parsed_data = parse_results_file(content)
    except Exception as e:
        feedback.append(f"Failed to read results file: {e}")
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    if not parsed_data:
        return {"passed": False, "score": score, "feedback": "Results file was empty or unparseable."}

    # 4. Numerical Verification
    # Intercept
    val = parsed_data.get('intercept')
    if val is not None and abs(val - gt['intercept']) < tolerance['coef']:
        score += 15
    else:
        feedback.append(f"Intercept mismatch: got {val}, expected ~{gt['intercept']}")

    # Slope
    val = parsed_data.get('slope')
    if val is not None and abs(val - gt['slope']) < tolerance['coef']:
        score += 15
    else:
        feedback.append(f"Slope mismatch: got {val}, expected ~{gt['slope']}")

    # R-squared
    val = parsed_data.get('r_squared')
    if val is not None and abs(val - gt['r_squared']) < tolerance['r2']:
        score += 10
    else:
        feedback.append(f"R-squared mismatch: got {val}, expected ~{gt['r_squared']}")

    # Standard Errors
    val_se_int = parsed_data.get('se_intercept')
    if val_se_int is not None and abs(val_se_int - gt['se_intercept']) < tolerance['se']:
        score += 10
    else:
        feedback.append(f"SE Intercept mismatch: got {val_se_int}, expected ~{gt['se_intercept']}")

    val_se_slope = parsed_data.get('se_slope')
    if val_se_slope is not None and abs(val_se_slope - gt['se_slope']) < tolerance['se']:
        score += 10
    else:
        feedback.append(f"SE Slope mismatch: got {val_se_slope}, expected ~{gt['se_slope']}")

    # Internal Consistency (t-stats)
    # t = coef / se
    t_consistent = True
    if 't_intercept' in parsed_data and 'intercept' in parsed_data and 'se_intercept' in parsed_data:
        expected_t = parsed_data['intercept'] / parsed_data['se_intercept'] if parsed_data['se_intercept'] != 0 else 0
        if abs(parsed_data['t_intercept'] - expected_t) > 0.1:
            t_consistent = False
            feedback.append("Intercept t-stat inconsistent with coef/SE")
    
    if 't_slope' in parsed_data and 'slope' in parsed_data and 'se_slope' in parsed_data:
        expected_t = parsed_data['slope'] / parsed_data['se_slope'] if parsed_data['se_slope'] != 0 else 0
        if abs(parsed_data['t_slope'] - expected_t) > 0.1:
            t_consistent = False
            feedback.append("Slope t-stat inconsistent with coef/SE")
            
    if t_consistent:
        score += 5

    # 5. Script Verification
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    script_content = ""
    try:
        copy_from_env("/home/ga/Documents/gretl_output/matrix_ols_script.inp", temp_script.name)
        with open(temp_script.name, 'r') as f:
            script_content = f.read().lower()
            score += 5 # Script exists
    except Exception:
        feedback.append("Script file not found.")
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    if script_content:
        # Check forbidden commands
        # We need to be careful not to match words in comments or print statements if possible, 
        # but a simple check is usually sufficient for this level.
        # Remove comments first (lines starting with #)
        clean_lines = [l for l in script_content.splitlines() if not l.strip().startswith('#')]
        clean_script = "\n".join(clean_lines)

        forbidden = ['ols ', 'estimate ', 'tsls ']
        found_forbidden = [cmd for cmd in forbidden if cmd in clean_script]
        
        if found_forbidden:
            score = 0 # ZERO TOLERANCE for using built-in ols
            feedback.append(f"Forbidden command found in script: {found_forbidden}")
        else:
            score += 10 # No forbidden commands

        # Check for matrix operations
        required_ops = ['inv(', 't(', 'qform', '{', '*'] # * is loose, but 'inv(' is specific
        found_ops = [op for op in required_ops if op in clean_script]
        
        # We need at least 'inv(' or 'qform' or explicit matrix mult syntax to believe it's matrix algebra
        if 'inv(' in clean_script or ('{' in clean_script and '}' in clean_script):
            score += 10
        else:
            feedback.append("Script does not appear to use matrix inversion or construction.")

    # Final logic
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback) if feedback else "Task completed successfully"
    }