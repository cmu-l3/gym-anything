#!/usr/bin/env python3
"""
Verifier for wls_food_expenditure task.

Verifies:
1. Output file exists and was created during the task.
2. Output contains WLS regression results (not OLS).
3. Coefficients match expected WLS values for food.gdt (wt = 1/income).
"""

import json
import base64
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wls_food_expenditure(traj, env_info, task_info):
    """
    Verify WLS regression output.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result
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

    # Basic checks
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file wls_results.txt not found."}

    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 10, "feedback": "Output file exists but was not created during this task session."}

    # Decode content
    content_b64 = result.get("output_content_b64", "")
    if not content_b64:
        return {"passed": False, "score": 20, "feedback": "Output file is empty."}
    
    try:
        content = base64.b64decode(content_b64).decode('utf-8', errors='replace')
    except Exception:
        return {"passed": False, "score": 20, "feedback": "Could not decode output file."}

    score = 30
    feedback_parts = ["File created."]

    # Check 1: Verify it is WLS
    # Gretl WLS output usually contains "Weighted Least Squares" or "WLS"
    if re.search(r"Weighted Least Squares|WLS", content, re.IGNORECASE):
        score += 20
        feedback_parts.append("Correctly identified as WLS.")
    else:
        feedback_parts.append("Output does not identify as Weighted Least Squares.")

    # Check 2: Verify weight variable usage
    # "Weights based on: wt" or similar
    if re.search(r"Weight.*wt", content, re.IGNORECASE):
        score += 10
        feedback_parts.append("Used correct weight variable 'wt'.")
    else:
        feedback_parts.append("Could not confirm usage of weight variable 'wt'.")

    # Check 3: Coefficient Values
    # Parse coefficient table
    # Look for patterns like: "const      78.68" and "income     10.45"
    # Allow for flexible whitespace
    
    # Expected ranges (from task metadata or known values)
    # WLS with wt=1/income on food.gdt:
    # Const: ~78.68 (Range 76-82)
    # Income: ~10.45 (Range 10.3-10.8)
    
    # Regex to find coefficients
    const_match = re.search(r"const\s+([\d\.-]+)", content)
    income_match = re.search(r"income\s+([\d\.-]+)", content)

    coeffs_found = False
    coeffs_correct = False
    
    if const_match and income_match:
        try:
            const_val = float(const_match.group(1))
            income_val = float(income_match.group(1))
            coeffs_found = True
            
            # Check ranges
            const_ok = 76.0 <= const_val <= 82.0
            income_ok = 10.3 <= income_val <= 10.8
            
            if const_ok and income_ok:
                score += 40
                coeffs_correct = True
                feedback_parts.append(f"Coefficients correct (const={const_val}, income={income_val}).")
            else:
                # Check if they match OLS values (Gaming check)
                # OLS: const ~83.4, income ~10.2
                if (82.5 < const_val < 84.5) and (10.1 < income_val < 10.3):
                    feedback_parts.append("Result appears to be OLS, not WLS (coefficients match OLS).")
                    score -= 10 # Penalize if we already gave points for WLS string but numbers are OLS
                else:
                    feedback_parts.append(f"Coefficients out of range (const={const_val}, income={income_val}).")
        except ValueError:
            feedback_parts.append("Could not parse coefficient values.")
    else:
        feedback_parts.append("Could not find coefficient table in output.")

    # Final scoring logic
    passed = score >= 60 and coeffs_found and coeffs_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }