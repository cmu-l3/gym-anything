#!/usr/bin/env python3
"""
Verifier for Fleiss' Kappa Reliability Task.

Scoring Criteria:
1. JASP Analysis File (.jasp) created and valid (20 pts)
2. Report File (.txt) created (10 pts)
3. Correct Kappa Value (approx 0.430) reported (40 pts)
4. Correct Interpretation ('Moderate') reported (30 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fleiss_kappa(traj, env_info, task_info):
    """
    Verify the Fleiss' Kappa task based on file outputs and content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_kappa_range = metadata.get('expected_kappa_range', [0.42, 0.44])
    expected_interpretation = metadata.get('expected_interpretation', "Moderate")

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. JASP File Check (20 pts)
    jasp_info = result.get('jasp_file', {})
    if jasp_info.get('exists') and jasp_info.get('size_bytes', 0) > 1000:
        if jasp_info.get('created_during_task'):
            score += 20
            feedback_parts.append("JASP analysis file saved.")
        else:
            score += 10
            feedback_parts.append("JASP file exists but timestamp is old (reused?).")
    else:
        feedback_parts.append("JASP analysis file not found or too small.")

    # 2. Report File Check (80 pts total)
    report_info = result.get('report_file', {})
    if report_info.get('exists'):
        score += 10
        feedback_parts.append("Report file created.")
        
        content = report_info.get('content', "").lower()
        
        # Check Kappa Value (40 pts)
        # Look for numbers near 0.43
        # Regex finds floating point numbers
        numbers = re.findall(r"0\.\d+", content)
        value_correct = False
        for num_str in numbers:
            try:
                val = float(num_str)
                if expected_kappa_range[0] <= val <= expected_kappa_range[1]:
                    value_correct = True
                    break
            except ValueError:
                continue
        
        if value_correct:
            score += 40
            feedback_parts.append("Correct Fleiss' Kappa value found (approx 0.43).")
        else:
            feedback_parts.append(f"Could not find correct Kappa value (expected ~0.430). Found: {numbers}")

        # Check Interpretation (30 pts)
        if expected_interpretation.lower() in content:
            score += 30
            feedback_parts.append(f"Correct interpretation '{expected_interpretation}' found.")
        else:
            feedback_parts.append(f"Interpretation '{expected_interpretation}' missing from report.")

    else:
        feedback_parts.append("Report file not found.")

    # Final Evaluation
    passed = (score >= 80)  # Requires files + at least value or interpretation correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }