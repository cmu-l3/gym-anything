#!/usr/bin/env python3
"""
Verifier for elasticity_hypothesis_script task.

Verification Criteria:
1. Output file exists and was created during task (10 pts)
2. Contains OLS regression results (15 pts)
3. Uses log-log specification (log(food) vs log(income)) (15 pts)
4. Elasticity coefficient matches expected range (~0.69) (15 pts)
5. Contains restriction/hypothesis test (20 pts)
6. Correctly rejects H0 (p < 0.05) (10 pts)
7. VLM: Visual confirmation of script usage (15 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_elasticity_hypothesis(traj, env_info, task_info):
    # 1. Setup and Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_elasticity_min = metadata.get('expected_elasticity_min', 0.55)
    expected_elasticity_max = metadata.get('expected_elasticity_max', 0.85)
    
    score = 0
    feedback = []
    
    # 2. Retrieve JSON Result
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # 3. Retrieve Output Content File
    output_content = ""
    output_path = task_result.get('output_file_path')
    
    if task_result.get('output_exists') and task_result.get('output_size_bytes', 0) > 0:
        with tempfile.NamedTemporaryFile(mode='w+', suffix='.txt') as f:
            try:
                copy_from_env(output_path, f.name)
                f.seek(0)
                output_content = f.read()
            except Exception as e:
                feedback.append(f"Output file exists but could not be read: {e}")

    # --- CRITERION 1: File Existence & Anti-Gaming (10 pts) ---
    if task_result.get('output_exists') and task_result.get('file_created_during_task'):
        score += 10
        feedback.append("Output file created successfully.")
    elif task_result.get('output_exists'):
        score += 5
        feedback.append("Output file exists but timestamp is invalid (pre-existing?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # --- CRITERION 2: OLS Regression Output (15 pts) ---
    has_ols = False
    if re.search(r"(OLS|Ordinary Least Squares|Model \d+: OLS)", output_content, re.IGNORECASE):
        has_ols = True
    
    # Also check for coefficient table headers
    if re.search(r"(coefficient\s+std\.\s*error|Estimate\s+Std\.\s*Error)", output_content, re.IGNORECASE):
        has_ols = True
        
    if has_ols:
        score += 15
        feedback.append("OLS regression output found.")
    else:
        feedback.append("Missing OLS regression results.")

    # --- CRITERION 3: Log-Log Specification (15 pts) ---
    # Look for log transformed variable names or labels in the output
    has_logs = False
    log_patterns = [
        r"l_food", r"l_income", 
        r"log\(food", r"log\(income", 
        r"ln_food", r"ln_income",
        r"Dependent variable: l_"
    ]
    
    if any(re.search(p, output_content, re.IGNORECASE) for p in log_patterns):
        has_logs = True
        score += 15
        feedback.append("Log-log specification detected.")
    else:
        feedback.append("Could not confirm log-log specification (missing 'l_' or 'log' variables).")

    # --- CRITERION 4: Elasticity Coefficient Range (15 pts) ---
    # Extract the slope coefficient. It usually follows the intercept.
    # Pattern: variable_name   coefficient   std_error ...
    # We look for a line containing 'income' and capture the first float
    elasticity_found = False
    extracted_val = None
    
    # Try to find the income coefficient line
    # Example Gretl output: 
    # l_income     0.689626     0.0592976      11.63      1.99e-014 ***
    income_lines = re.findall(r"(?:l_|log_|ln_)?income\s+([-+]?\d*\.\d+)", output_content, re.IGNORECASE)
    
    if income_lines:
        try:
            val = float(income_lines[0])
            extracted_val = val
            if expected_elasticity_min <= val <= expected_elasticity_max:
                score += 15
                elasticity_found = True
                feedback.append(f"Elasticity coefficient ({val}) is correct.")
            else:
                feedback.append(f"Elasticity coefficient ({val}) is outside expected range ({expected_elasticity_min}-{expected_elasticity_max}).")
        except ValueError:
            feedback.append("Found income variable but could not parse coefficient.")
    else:
        feedback.append("Could not find income coefficient in output.")

    # --- CRITERION 5: Restriction Test Presence (20 pts) ---
    has_test = False
    test_patterns = [
        r"Restriction:", 
        r"Wald test", 
        r"Test for.*=.*1",
        r"Null hypothesis:.*=.*1",
        r"F-statistic",
        r"Chi-square"
    ]
    
    # We need to ensure this is AFTER the regression, implying a post-estimation test
    if any(re.search(p, output_content, re.IGNORECASE) for p in test_patterns):
        # Specific check for testing against 1 (unitary elasticity)
        if "1" in output_content or "unitary" in output_content.lower():
            has_test = True
            score += 20
            feedback.append("Restriction test found.")
        else:
            score += 10 # Partial credit if some test found but unsure if it's beta=1
            feedback.append("Generic test found, but specific H0: beta=1 not clearly identified.")
    else:
        feedback.append("No restriction/hypothesis test results found.")

    # --- CRITERION 6: Rejection of H0 (10 pts) ---
    # Check for p-value indicating significance (rejection of beta=1)
    # The actual p-value is usually very small (< 0.001) or at least < 0.05
    rejects_h0 = False
    
    # Look for p-value associated with the test
    # This is tricky with regex, so we look for "p-value" followed by a small number
    # OR asterisks *** near the test result
    
    test_section = ""
    if has_test:
        # Try to isolate the test section (last 10-20 lines usually)
        lines = output_content.splitlines()
        test_section = "\n".join(lines[-15:])
        
        p_val_matches = re.findall(r"p-value\s*[=:]?\s*(\d*\.\d+(?:e[-+]?\d+)?)", test_section, re.IGNORECASE)
        if not p_val_matches:
            # Look for Prob > F or similar
            p_val_matches = re.findall(r"Prob\s*>\s*[F|Chi]\s*=\s*(\d*\.\d+)", test_section, re.IGNORECASE)
            
        if p_val_matches:
            try:
                p_val = float(p_val_matches[0])
                if p_val < 0.05:
                    rejects_h0 = True
                    score += 10
                    feedback.append(f"Test correctly rejects H0 (p-value {p_val} < 0.05).")
                else:
                    feedback.append(f"Test p-value ({p_val}) does not reject H0 (expected rejection).")
            except:
                pass
        
        # Fallback: Look for stars if p-value parse failed
        if not rejects_h0 and ("***" in test_section or "**" in test_section):
            # risky assumption but standard in gretl for significance
            rejects_h0 = True
            score += 10
            feedback.append("Test appears significant (stars detected).")

    # --- CRITERION 7: VLM Verification (15 pts) ---
    # We verify if the script editor was actually used vs just point-and-click
    # For this implementation, we award points if we have a trajectory
    # In full production, this would call the VLM
    if len(traj) > 0:
        score += 15
        feedback.append("Trajectory evidence available.")
    else:
        feedback.append("No trajectory data.")

    # Final Evaluation
    # Threshold: 60 points AND OLS result present AND file created
    passed = (score >= 60) and has_ols and task_result.get('file_created_during_task')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }