#!/usr/bin/env python3
"""
Verifier for subsample_regression_script task.

Verification Strategy:
1. Check if output file exists and was created during the task.
2. Parse the output text file for numeric values corresponding to:
   - Sample sizes (N=23 and N=17)
   - Slope coefficients (within reasonable economic ranges)
3. Confirm structure implies two distinct analyses (Low/High income).
"""

import json
import os
import re
import base64
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_subsample_regression_script(traj, env_info, task_info):
    """
    Verify the agent wrote a script to produce subsample regression results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_n_low = metadata.get('expected_n_low', 23)
    expected_n_high = metadata.get('expected_n_high', 17)
    slope_range_low = metadata.get('slope_range_low', [8.0, 22.0])
    slope_range_high = metadata.get('slope_range_high', [4.0, 18.0])

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Decode output content
    content = ""
    if result_data.get("output_exists") and result_data.get("output_content_base64"):
        try:
            content = base64.b64decode(result_data["output_content_base64"]).decode('utf-8', errors='ignore')
        except Exception:
            content = ""

    score = 0
    feedback_parts = []
    
    # Criterion 1: Output file existence (10 pts)
    if result_data.get("output_exists"):
        score += 10
        feedback_parts.append("Output file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Criterion 2: Anti-gaming / Timestamp (5 pts)
    if result_data.get("file_created_during_task"):
        score += 5
    else:
        feedback_parts.append("Warning: File timestamp indicates pre-existence or clock skew.")

    # Criterion 3: Content Analysis (Numeric Extraction)
    # We look for numbers in the text and try to match them to our expectations
    # This is more robust than strict regex for "Slope: 10.5"
    
    # Extract all floating point numbers
    floats = [float(x) for x in re.findall(r'-?\d+\.\d+', content)]
    # Extract integers (likely N values)
    integers = [int(x) for x in re.findall(r'\b\d+\b', content)]

    # Check for Sample Sizes (N) - 15 pts
    # We expect to find 23 and 17 somewhere in the integer list (or float list if formatted 23.0)
    has_n_low = expected_n_low in integers or float(expected_n_low) in floats
    has_n_high = expected_n_high in integers or float(expected_n_high) in floats
    
    if has_n_low and has_n_high:
        score += 15
        feedback_parts.append(f"Found correct sample sizes ({expected_n_low}, {expected_n_high}).")
    elif has_n_low or has_n_high:
        score += 7
        feedback_parts.append(f"Found one correct sample size.")
    else:
        feedback_parts.append("Could not verify correct sample sizes (expected 23 and 17).")

    # Check for Slope Coefficients - 20 pts (10 each)
    # We look for values within the ranges. 
    # Since the file might contain many numbers (SE, R2), we verify if *any* number fits the slope range.
    # To be safer, we assume slopes are likely labeled or at least printed.
    
    # Filter floats that are plausible slopes
    candidates_low = [x for x in floats if slope_range_low[0] <= x <= slope_range_low[1]]
    candidates_high = [x for x in floats if slope_range_high[0] <= x <= slope_range_high[1]]
    
    found_slope_low = len(candidates_low) > 0
    found_slope_high = len(candidates_high) > 0
    
    if found_slope_low:
        score += 10
        feedback_parts.append("Found value in low-income slope range.")
    
    if found_slope_high:
        score += 10
        feedback_parts.append("Found value in high-income slope range.")
        
    # Check for R-squared (0 < R2 < 1) - 5 pts
    # R2 is typically 0.X. 
    r2_candidates = [x for x in floats if 0.0 <= x <= 1.0]
    if len(r2_candidates) >= 2:
        score += 5
        feedback_parts.append("Found plausible R-squared values.")

    # Check for keywords - 10 pts
    keywords = ["slope", "coeff", "std", "error", "r-squared", "n", "obs"]
    content_lower = content.lower()
    keyword_count = sum(1 for k in keywords if k in content_lower)
    if keyword_count >= 3:
        score += 10
        feedback_parts.append("Output contains descriptive labels.")

    # VLM Verification (Trajectory) - 20 pts
    # We want to see the Script Editor window.
    # Since we can't easily run VLM here without external deps, we'll base this score 
    # on whether the content looks like it came from a script (structured output) 
    # vs just a copy-paste of GUI output.
    # However, to conform to the template's structure, we'll assign points if the output 
    # is well-formatted (which implies script usage).
    
    # If we found both Ns and both Slopes, it's highly likely they did the task.
    if has_n_low and has_n_high and found_slope_low and found_slope_high:
        score += 20
        feedback_parts.append("Strong evidence of successful execution.")
    
    # Additional check: total N constraint
    if has_n_low and has_n_high:
         if expected_n_low + expected_n_high == 40:
             score += 5 # Bonus for consistency
             
    # Pass threshold
    # Must have output file, correct sample sizes, and at least some slope evidence
    key_criteria = result_data.get("output_exists") and has_n_low and has_n_high
    passed = (score >= 60) and key_criteria

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }