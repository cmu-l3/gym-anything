#!/usr/bin/env python3
"""
Verifier for Heckman Wage Selection Task (heckman_wage_selection@1)

Checks:
1. Output file exists and was created during the task.
2. File content indicates a Heckman/Heckit model (not OLS).
3. Variable 'l_wage' was created and used.
4. Correct exclusion restriction (nwifeinc in selection, not outcome).
5. Coefficients match ground truth (approximate check).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_heckman_wage_selection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_n_total = metadata.get('expected_n_total', 753)
    ground_truth_coef = metadata.get('ground_truth', {}).get('coef_educ_outcome', 0.109)
    coef_tolerance = metadata.get('ground_truth', {}).get('coef_educ_tolerance', 0.05)
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # Check 1: File Artifacts (20 pts)
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result.get('file_created_during_task'):
        feedback.append("Warning: File timestamp suggests it wasn't created during this session.")
        # We don't fail immediately, but it's suspicious
    else:
        score += 10
        feedback.append("Output file created successfully.")

    if result.get('output_size_bytes', 0) > 100:
        score += 10
    else:
        return {"passed": False, "score": score, "feedback": "Output file is empty or too small."}

    # 2. Analyze Content (80 pts)
    output_path = result.get('output_path')
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    content = ""
    
    try:
        copy_from_env(output_path, temp_output.name)
        with open(temp_output.name, 'r', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output file: {str(e)}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # Content Check A: Model Type (20 pts)
    # Gretl output typically contains "Heckman selection model" or "Heckit"
    if re.search(r"Heckman selection model|Heckit", content, re.IGNORECASE):
        score += 20
        feedback.append("Correct model type (Heckman) detected.")
    elif re.search(r"OLS|Ordinary Least Squares", content, re.IGNORECASE):
        feedback.append("Incorrect model type: Detected OLS instead of Heckman.")
    else:
        feedback.append("Could not identify model type from output.")

    # Content Check B: Variable Creation (l_wage) (10 pts)
    # Check if 'l_wage' appears in the regression equation
    if re.search(r"Dependent variable:.*l_wage", content, re.IGNORECASE):
        score += 10
        feedback.append("Correct dependent variable (l_wage) used.")
    elif re.search(r"Dependent variable:.*wage", content, re.IGNORECASE):
        feedback.append("Incorrect dependent variable: Used raw 'wage' instead of log.")
    else:
        feedback.append("Dependent variable not clearly identified.")

    # Content Check C: Exclusion Restriction (10 pts)
    # 'nwifeinc' should appear in Selection equation but NOT in Regression equation
    # This is hard to parse perfectly with regex, but we can check if it appears
    # We expect 'nwifeinc' to be listed.
    if "nwifeinc" in content:
        score += 10
        feedback.append("Exclusion variable 'nwifeinc' present in model.")
    else:
        feedback.append("Exclusion variable 'nwifeinc' missing.")

    # Content Check D: Sample Size (10 pts)
    # Look for "n = 753" or similar
    if str(expected_n_total) in content:
        score += 10
        feedback.append(f"Correct sample size ({expected_n_total}) detected.")
    
    # Content Check E: Coefficient Accuracy (30 pts)
    # Look for the education coefficient in the Outcome equation.
    # Pattern: "educ" followed by numbers.
    # Note: 'educ' appears in BOTH equations. Usually the Outcome equation comes second in Gretl Heckit output,
    # or is labeled "Equation 2".
    
    # Let's try to extract all 'educ' coefficients and see if any match the ground truth.
    # Row format often: "educ   0.10906   0.0123"
    educ_matches = re.findall(r"educ\s+([\-0-9]+\.[0-9]+)", content)
    
    found_correct_coef = False
    best_val = 0
    if educ_matches:
        for val_str in educ_matches:
            try:
                val = float(val_str)
                if abs(val - ground_truth_coef) < coef_tolerance:
                    found_correct_coef = True
                    best_val = val
                    break
            except ValueError:
                continue

    if found_correct_coef:
        score += 30
        feedback.append(f"Education coefficient ({best_val}) matches ground truth.")
    else:
        feedback.append(f"Could not find matching education coefficient (Expected ~{ground_truth_coef}). Found: {educ_matches}")

    # Pass logic
    passed = (score >= 70) and ("Heckman" in feedback[-5:] or "Heckit" in "".join(feedback))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }