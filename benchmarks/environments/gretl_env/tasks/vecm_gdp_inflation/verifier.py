#!/usr/bin/env python3
"""
Verifier for VECM GDP Inflation Task.

Criteria:
1. Output file exists and was created during the task.
2. Output contains VECM/Johansen estimation results.
3. Correct variables used (log transform of GDP and Inflation).
4. Correct Rank (Rank=1) specified.
5. VLM verification of trajectory (optional but recommended for robustness).
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vecm_gdp_inflation(traj, env_info, task_info):
    """
    Verifies that the agent performed a VECM analysis on Log(GDP) and Inflation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/gretl_output/vecm_results.txt')

    # --- Step 1: Load Execution Result JSON ---
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

    # --- Step 2: Check File Existence & Timestamp ---
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'vecm_results.txt' not found."}
    
    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during this task session (stale data)."}

    # --- Step 3: Analyze Output Content ---
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(expected_output_path, temp_output.name)
        with open(temp_output.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read output file: {str(e)}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    score = 0
    feedback_points = []

    # Criterion A: Is it a VECM / Johansen test? (30 pts)
    # Gretl output usually contains "Johansen test" or "Vector Error Correction" or "VECM"
    if re.search(r"(Vector Error Correction|VECM|Johansen test)", content, re.IGNORECASE):
        score += 30
        feedback_points.append("VECM/Johansen analysis detected")
    else:
        feedback_points.append("Output does not appear to be a VECM or Johansen test")

    # Criterion B: Are the correct variables used? (30 pts)
    # Needs 'l_gdp' (or similar log var) and 'inf'
    # Flexible matching for log gdp: l_gdp, log_gdp, ln_gdp, or l_usa_gdp
    has_log_gdp = re.search(r"\b(l_gdp|log_gdp|ln_gdp|l_usa_gdp)\b", content, re.IGNORECASE)
    has_inf = re.search(r"\b(inf|inflation)\b", content, re.IGNORECASE)

    if has_log_gdp and has_inf:
        score += 30
        feedback_points.append("Correct variables (Log GDP and Inflation) used")
    elif has_inf:
        score += 15
        feedback_points.append("Inflation variable found, but Log GDP missing (did you transform the variable?)")
    else:
        feedback_points.append("Required variables not found in output")

    # Criterion C: Is Rank = 1 specified/estimated? (20 pts)
    # Gretl output for VECM often says "Number of equations = 2", "Rank of Pi = 1" or lists 1 cointegrating vector
    # Look for "Rank: 1" or implicit evidence like 1 beta vector printed
    if re.search(r"(Rank of Pi\s*=\s*1|Cointegrating vectors\s*\(ranks\)\s*:\s*1|beta 1)", content, re.IGNORECASE):
        score += 20
        feedback_points.append("Cointegration Rank 1 confirmed")
    # Fallback: Check if they just ran the test (which suggests rank)
    elif "Trace test" in content and "Lmax test" in content:
        # If they only saved the test results but not the VECM estimation, give partial credit
        score += 10
        feedback_points.append("Johansen Test results found (but full VECM estimation might be missing)")

    # Criterion D: File size check (sanity check) (20 pts)
    if len(content) > 200:
        score += 20
        feedback_points.append("Output content length is valid")
    else:
        feedback_points.append("Output file is suspiciously short")

    # --- Final Scoring ---
    # Pass if Score >= 70 AND VECM detected AND Variables correct
    passed = (score >= 70) and ("VECM/Johansen analysis detected" in feedback_points) and ("Correct variables (Log GDP and Inflation) used" in feedback_points)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_points)
    }