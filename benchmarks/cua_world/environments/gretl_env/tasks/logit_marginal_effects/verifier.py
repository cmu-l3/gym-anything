#!/usr/bin/env python3
"""
Verifier for logit_marginal_effects task.

Requires:
1. Output file exists.
2. File created during task session.
3. Content indicates "Marginal effects" or "Slope".
4. Values match ground truth (Logit model on Mroz dataset).
"""

import json
import os
import tempfile
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_logit_marginal_effects(traj, env_info, task_info):
    """
    Verify the logit marginal effects output.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/gretl_output/logit_mfx.txt')
    # Ground truth: educ coeff ~ 0.22, mean lfp ~ 0.56. MFX ~ 0.054
    target_val = metadata.get('ground_truth_educ_mfx', 0.054) 
    tolerance = metadata.get('tolerance', 0.01)

    # 1. Get result JSON
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

    # 2. Get actual output file content
    output_content = ""
    file_exists = result_data.get("output_file_exists", False)
    
    if file_exists:
        temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(expected_path, temp_output.name)
            with open(temp_output.name, 'r', errors='ignore') as f:
                output_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read output file content: {e}")
        finally:
            if os.path.exists(temp_output.name):
                os.unlink(temp_output.name)

    # Scoring
    score = 0
    feedback = []

    # Criterion 1: File Existence & Timing (20 pts)
    if file_exists:
        if result_data.get("output_file_created_during_task", False):
            score += 20
            feedback.append("Output file created successfully.")
        else:
            score += 10
            feedback.append("Output file exists but timestamp is old (reused?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Criterion 2: Content Analysis (Keywords) (30 pts)
    # Check for Logit and Marginal Effects
    content_lower = output_content.lower()
    
    has_logit = "logit" in content_lower or "logistic" in content_lower
    has_mfx = "marginal" in content_lower or "slope" in content_lower or "mfx" in content_lower
    
    if has_logit:
        score += 15
        feedback.append("Confirmed Logit model output.")
    else:
        feedback.append("Could not confirm Logit model in output.")

    if has_mfx:
        score += 15
        feedback.append("Confirmed Marginal Effects/Slope analysis.")
    else:
        feedback.append("Could not find 'Marginal effects' or 'Slope' keywords.")

    # Criterion 3: Value Accuracy (50 pts)
    # Look for the 'educ' variable and its marginal effect
    # Pattern: Look for line with 'educ', then find a number around 0.05
    # The output format usually lists Variable, Coefficient/Slope, Std Error...
    
    # Simple regex to find "educ" followed by numbers
    # Example line: "educ    0.05408    0.0102"
    match = re.search(r"educ\s+[:=]?\s*([0-9\.\-]+)", output_content, re.IGNORECASE)
    
    value_correct = False
    found_val = None
    
    if match:
        try:
            val = float(match.group(1))
            found_val = val
            if abs(val - target_val) <= tolerance:
                score += 50
                value_correct = True
                feedback.append(f"Marginal effect for 'educ' correct ({val}).")
            elif abs(val - 0.22) <= 0.05: # User might have saved raw coefficients instead of MFX
                score += 10 # Partial credit
                feedback.append(f"Found raw Logit coefficient ({val}) instead of marginal effect.")
            else:
                feedback.append(f"Value for 'educ' ({val}) is outside expected range ({target_val} ± {tolerance}).")
        except ValueError:
            feedback.append("Could not parse numerical value for 'educ'.")
    else:
        feedback.append("Could not find 'educ' variable in output.")

    # Deduct for non-logit model (e.g. if they ran OLS, coeff for educ is approx 0.038)
    if found_val and abs(found_val - 0.038) <= 0.01:
        feedback.append("Value matches OLS regression, not Logit Marginal Effects.")
        score = min(score, 40) # Cap score if wrong model used

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }