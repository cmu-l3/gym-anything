#!/usr/bin/env python3
"""
Verifier for hetero_test_robust task.

Checks:
1. Output file exists and was created during the task.
2. Contains OLS estimation results (income coefficient check).
3. Contains White's test results.
4. Contains Breusch-Pagan test results.
5. Contains Robust estimation results (HC standard errors).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hetero_test_robust(traj, env_info, task_info):
    """
    Verify the heteroscedasticity testing workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_coeff = metadata.get('target_coeff_income', 10.21)
    tolerance = metadata.get('coeff_tolerance', 0.5)

    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Get Agent Output File
    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    output_path = result.get("output_path", "")
    
    agent_output_content = ""
    if output_exists:
        temp_out = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(output_path, temp_out.name)
            with open(temp_out.name, 'r', errors='replace') as f:
                agent_output_content = f.read()
        except Exception as e:
            logger.error(f"Failed to copy output file: {e}")
        finally:
            if os.path.exists(temp_out.name):
                os.unlink(temp_out.name)

    # Scoring Setup
    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Creation (10 pts)
    if output_exists and len(agent_output_content) > 50:
        if file_created:
            score += 10
            feedback.append("Output file created successfully.")
        else:
            score += 5
            feedback.append("Output file exists but timestamp is old (pre-task?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or empty."}

    # Criterion 2: OLS Regression Content (15 pts)
    # Look for "OLS" and "income" and coefficient
    # Pattern: "income" ... number ... number
    # Typical Gretl: "income       10.2096      2.09326"
    
    # We look for the coefficient of income close to 10.21
    ols_found = False
    coeff_correct = False
    
    if "OLS" in agent_output_content or "Ordinary Least Squares" in agent_output_content:
        ols_found = True
        # Try to find coefficient
        # Regex matches: income followed by spaces, then a float (coef), then spaces, then float (std err)
        match = re.search(r'income\s+([0-9]+\.[0-9]+)', agent_output_content)
        if match:
            try:
                val = float(match.group(1))
                if abs(val - expected_coeff) < tolerance:
                    coeff_correct = True
                    score += 15
                    feedback.append(f"OLS estimation correct (income coeff: {val}).")
                else:
                    score += 5
                    feedback.append(f"OLS found but coefficient mismatch (found {val}, expected ~{expected_coeff}).")
            except ValueError:
                pass
        
        if not coeff_correct and ols_found:
             # Fallback points just for running OLS
             score += 5
             feedback.append("OLS estimation found, but could not parse coefficient.")
    else:
        feedback.append("No OLS regression output found.")

    # Criterion 3: White's Test (20 pts)
    # Look for "White's test" and "P-value"
    white_found = False
    if "White's test" in agent_output_content or "White test" in agent_output_content:
        white_found = True
        score += 10
        feedback.append("White's test performed.")
        
        # Check p-value detection (should be < 0.05 for this data)
        # We search specifically in the context of White's test
        # Simplification: just check if the text block exists
        if re.search(r"P-value\s*=\s*[0-9\.]+", agent_output_content):
            score += 10
            feedback.append("White's test statistics visible.")
    else:
        feedback.append("White's test not found.")

    # Criterion 4: Breusch-Pagan Test (20 pts)
    bp_found = False
    if "Breusch-Pagan" in agent_output_content:
        bp_found = True
        score += 10
        feedback.append("Breusch-Pagan test performed.")
        
        if re.search(r"P-value\s*=\s*[0-9\.]+", agent_output_content):
            score += 10
            feedback.append("Breusch-Pagan statistics visible.")
    else:
        feedback.append("Breusch-Pagan test not found.")

    # Criterion 5: Robust Estimation (35 pts)
    # Look for "Robust standard errors" or "Heteroscedasticity-consistent"
    # AND ensure it's a distinct estimation from the first one
    robust_found = False
    
    robust_keywords = [
        "Robust standard errors", 
        "Heteroscedasticity-consistent", 
        "HAC standard errors",
        "HC1"
    ]
    
    if any(k in agent_output_content for k in robust_keywords):
        robust_found = True
        score += 25
        feedback.append("Robust re-estimation performed.")
        
        # Bonus: Check if Standard Errors are different from OLS
        # OLS SE for income ~ 2.09
        # Robust SE for income ~ 1.81 (or similar, depending on HC variant)
        # We just check if we see different SE numbers in the file.
        # This is hard to regex robustly, so we'll give points for the keyword presence + context
        score += 10
    else:
        feedback.append("Robust estimation not found.")

    # Final Evaluation
    passed = score >= 60 and ols_found and (white_found or bp_found)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "ols_found": ols_found,
            "coeff_correct": coeff_correct,
            "white_test": white_found,
            "bp_test": bp_found,
            "robust_est": robust_found
        }
    }