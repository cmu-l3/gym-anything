#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_linear_restrictions_wage(traj, env_info, task_info):
    """
    Verifies that the agent performed a restricted least squares estimation
    where the return to education (coefficient of 'educ') is exactly 0.1.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve metadata and result JSON
    metadata = task_info.get('metadata', {})
    expected_coeff = metadata.get('required_coefficient', 0.1)
    
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check basic criteria
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file 'restricted_model_results.txt' not found."}
    
    if not created_during:
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during this task session."}

    # 3. Retrieve and parse the output text file
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/extracted_output.txt", temp_txt.name)
        with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 20, "feedback": f"Failed to read output file content: {str(e)}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    score = 20 # Points for file existence
    feedback = []

    # 4. Content Analysis
    # Check for variables
    if "lwage" in content:
        score += 5
    else:
        feedback.append("Dependent variable 'lwage' not found in output.")
        
    if "const" in content and "exper" in content:
        score += 5
    else:
        feedback.append("Independent variables 'const' or 'exper' missing.")

    # Check for restriction indicators
    # Gretl output typically contains "Restricted sum of squared residuals" or "Test for valid restriction"
    is_restricted_output = False
    if re.search(r"Restricted sum of squared residuals", content, re.IGNORECASE) or \
       re.search(r"Test for valid restriction", content, re.IGNORECASE) or \
       re.search(r"Restriction:", content, re.IGNORECASE):
        is_restricted_output = True
        score += 10
        feedback.append("Restriction test statistics found.")
    else:
        feedback.append("No evidence of restriction test in output.")

    # Check coefficient value for 'educ'
    # Pattern: "educ" followed by numbers. 
    # Example line: "  educ        0.100000      0.00000     ..."
    # Regex looks for 'educ', optional whitespace, then a float
    coeff_match = re.search(r"educ\s+([-+]?\d*\.\d+|\d+)", content)
    
    coeff_ok = False
    if coeff_match:
        try:
            val = float(coeff_match.group(1))
            # Strict check: must be very close to 0.1
            # Standard OLS on this data yields approx 0.09-0.11, so 0.1000 is distinct
            if abs(val - expected_coeff) < 1e-4:
                score += 60
                coeff_ok = True
                feedback.append(f"Coefficient for 'educ' is exactly {val} (Matches restriction).")
            else:
                feedback.append(f"Coefficient for 'educ' is {val}, expected exactly {expected_coeff}. Did you apply the restriction?")
        except ValueError:
            feedback.append("Could not parse 'educ' coefficient.")
    else:
        feedback.append("Variable 'educ' not found in regression table.")

    # Final logic
    passed = coeff_ok and is_restricted_output and (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }