#!/usr/bin/env python3
"""
Verifier for stepwise_backward_wage task in Gretl.

Verifies:
1. Output file existence and timestamp.
2. Correct method (Stepwise/Backward) used.
3. Correct variable selection (Retention of education/experience).
4. Correct sample size (Handling of missing wage data).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stepwise_backward_wage(traj, env_info, task_info):
    """
    Verify the stepwise regression task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring
    score = 0
    feedback = []
    
    # Criterion 1: Output file exists and was created during task (20 pts)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "No output file found at expected path."}
    
    if not result_data.get("file_created_during_task", False):
        feedback.append("Warning: Output file timestamp is before task start.")
        # We penalize but don't fail immediately in case of clock skew, 
        # checking content is more important.
        score += 5
    else:
        score += 20
        feedback.append("Output file created successfully.")

    if result_data.get("output_size_bytes", 0) < 100:
        return {"passed": False, "score": score, "feedback": "Output file is empty or too small."}

    # Retrieve content of the output file
    content = ""
    temp_content = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        # We try to copy the specific content file prepared by export_result
        copy_from_env("/tmp/stepwise_output_content.txt", temp_content.name)
        with open(temp_content.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output content: {e}"}
    finally:
        if os.path.exists(temp_content.name):
            os.unlink(temp_content.name)

    content_lower = content.lower()

    # Criterion 2: Correct Method Identification (30 pts)
    # Look for "Stepwise" or "Backward elimination"
    method_keywords = ["stepwise", "backward elimination", "dropping", "eliminated"]
    if any(k in content_lower for k in method_keywords):
        score += 30
        feedback.append("Correctly identified Stepwise/Backward elimination procedure.")
    else:
        feedback.append("Output does not clearly show Stepwise procedure (missing keywords like 'Stepwise' or 'Backward').")

    # Criterion 3: Correct Model Content & Variables (30 pts)
    # The final model for lwage usually retains: educ, exper, expersq
    # It usually drops: age (p=0.46), kidslt6 (p=0.88), city (p=0.20)
    # Sample size should be around 428 (working women)
    
    # Check for retained variables in the coefficient table
    # We look for lines starting with the variable name followed by numbers
    retained_vars = ["educ", "exper"]
    retained_count = 0
    for var in retained_vars:
        if re.search(rf"^\s*{var}\s", content, re.MULTILINE):
            retained_count += 1
    
    if retained_count == 2:
        score += 20
        feedback.append("Final model correctly retains 'educ' and 'exper'.")
    elif retained_count == 1:
        score += 10
        feedback.append("Final model retains some expected variables but misses others.")
    else:
        feedback.append("Final model does not appear to contain expected variables (educ, exper).")

    # Check for Coefficient Accuracy (Educ ~ 0.107)
    # Regex to find: educ [whitespace] 0.10...
    if re.search(r"educ\s+[\d\.\-\+]*(0\.10|0\.11)", content):
        score += 10
        feedback.append("Coefficient for 'educ' is within expected range (~0.10-0.11).")
    else:
        feedback.append("Coefficient for 'educ' not found or outside expected range.")

    # Criterion 4: Sample Size (20 pts)
    # Gretl output usually says "n = 428" or "Observations 1-753 (n = 428)"
    if "428" in content:
        score += 20
        feedback.append("Correct sample size (n=428) detected (handled missing data correctly).")
    elif "753" in content and "428" not in content:
        feedback.append("Incorrect sample size (n=753). You may have treated missing values as zeros or used the wrong dataset version.")
    else:
        # Partial credit if we can't find exact number but model looks okay
        if retained_count == 2:
            score += 10
        feedback.append("Could not explicitly verify sample size (n=428) in text.")

    # Final result calculation
    # Pass threshold: 80 points
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }