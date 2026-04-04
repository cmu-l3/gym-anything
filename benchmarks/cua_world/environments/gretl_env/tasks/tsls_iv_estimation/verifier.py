#!/usr/bin/env python3
"""
Verifier for Gretl TSLS IV Estimation task.
"""

import json
import os
import re
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tsls_iv_estimation(traj, env_info, task_info):
    """
    Verify the Two-Stage Least Squares estimation task.
    
    Criteria:
    1. Output file exists and was created during the task.
    2. Output content indicates TSLS/IV method (not OLS).
    3. Output contains correct coefficient for 'educ' (approx 0.061).
    4. Output mentions usage of instruments (mothereduc, fathereduc).
    5. VLM verification of the final state (optional but recommended).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_coeff = metadata.get('target_coeff_val', 0.061)
    tolerance = metadata.get('target_coeff_tolerance', 0.02)
    
    # Retrieve result JSON
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

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Timestamp (20 points)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if result.get('output_size_bytes', 0) < 50:
        return {"passed": False, "score": 0, "feedback": "Output file is empty or too small."}
        
    if result.get('file_created_during_task', False):
        score += 20
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File timestamp check failed (stale file?).")

    # Decode content
    content_b64 = result.get('output_content_base64', "")
    try:
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        content = ""

    if not content:
        return {"passed": False, "score": score, "feedback": "Could not read file content."}

    # 2. Method Identification (20 points)
    # Gretl TSLS output typically contains "Two-Stage Least Squares" or "TSLS"
    method_regex = re.compile(r"(Two-Stage Least Squares|TSLS|Instrumental Variables|2SLS)", re.IGNORECASE)
    if method_regex.search(content):
        score += 20
        feedback_parts.append("Method identified as TSLS.")
    else:
        feedback_parts.append("Output does not identify TSLS method (Did you run OLS?).")
        # Check if they ran OLS instead
        if "Ordinary Least Squares" in content or "OLS" in content:
            feedback_parts.append("Detected OLS instead of TSLS.")

    # 3. Coefficient Verification (30 points)
    # Look for the 'educ' line and extract coefficient
    # Line format usually: "  educ         0.0613966    0.0270950     2.266   0.0239 **"
    # We want to be robust to whitespace
    coeff_found = False
    educ_val = None
    
    # Regex to find 'educ' followed by a float
    # Matches "educ" then whitespace then a number (possibly negative)
    match = re.search(r"^\s*educ\s+([-+]?\d*\.\d+)", content, re.MULTILINE)
    if match:
        try:
            educ_val = float(match.group(1))
            if abs(educ_val - expected_coeff) <= tolerance:
                score += 30
                feedback_parts.append(f"Coefficient for 'educ' ({educ_val}) is correct.")
                coeff_found = True
            else:
                feedback_parts.append(f"Coefficient for 'educ' ({educ_val}) is outside expected range ({expected_coeff} ± {tolerance}).")
                # Special check for OLS result (approx 0.107)
                if abs(educ_val - 0.107) < 0.02:
                    feedback_parts.append("Value matches OLS estimate, not TSLS.")
        except ValueError:
            feedback_parts.append("Could not parse 'educ' coefficient.")
    else:
        feedback_parts.append("Could not find 'educ' coefficient in output.")

    # 4. Instruments Verification (20 points)
    # Output should list instruments
    instruments_present = 0
    if re.search(r"mothereduc", content, re.IGNORECASE):
        instruments_present += 1
    if re.search(r"fathereduc", content, re.IGNORECASE):
        instruments_present += 1
        
    if instruments_present >= 1:
        score += 20
        feedback_parts.append("Instruments found in output.")
    else:
        feedback_parts.append("No instruments (mothereduc/fathereduc) mentioned in output.")

    # 5. App Running Check (10 points)
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("Gretl was open.")
    else:
        feedback_parts.append("Gretl was closed at end of task.")

    passed = (score >= 60) and coeff_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }