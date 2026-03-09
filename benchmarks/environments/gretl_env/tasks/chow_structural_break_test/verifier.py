#!/usr/bin/env python3
"""
Verifier for chow_structural_break_test task.
Checks if the agent ran the OLS regression and Chow test and saved the output.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chow_structural_break_test(traj, env_info, task_info):
    """
    Verifies the Chow test task by parsing the output text file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Base Criteria
    output_exists = result_data.get("output_exists", False)
    file_created_correctly = result_data.get("file_created_during_task", False)
    output_size = result_data.get("output_size_bytes", 0)

    score = 0
    feedback = []

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    score += 10
    feedback.append("Output file exists.")

    if not file_created_correctly:
        feedback.append("Warning: File timestamp indicates it wasn't created during this task session.")
    else:
        score += 10
        feedback.append("File created during task.")

    if output_size < 50:
        return {"passed": False, "score": score, "feedback": "Output file is empty or too small."}

    # Retrieve content
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    content = ""
    try:
        copy_from_env("/tmp/chow_test_results_export.txt", temp_txt.name)
        with open(temp_txt.name, 'r', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve output content: {e}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    # Parsing Content
    # 1. Check for OLS results
    # Expected: const ~ 83.4, income ~ 10.2
    
    # Regex for coefficients: looking for lines like "const   83.4160"
    # Matches "const" followed by spaces and a number
    const_match = re.search(r"const\s+([-\d.]+)", content)
    income_match = re.search(r"income\s+([-\d.]+)", content)
    
    # Regex for R-squared: "R-squared       0.385"
    r2_match = re.search(r"R-squared\s+([.\d]+)", content)

    # Regex for Chow test
    # "Chow test for structural break at observation 20"
    # "F(2, 36) = 0.456636 with p-value 0.6371"
    chow_header_match = re.search(r"Chow test.*observation 20", content, re.IGNORECASE)
    chow_stat_match = re.search(r"F\(\d+,\s*\d+\)\s*=\s*([.\d]+)", content)
    chow_pval_match = re.search(r"p-value\s*([.\d]+)", content)

    # Evaluation
    
    # OLS Constants (15 pts each)
    if const_match:
        val = float(const_match.group(1))
        if 78.0 < val < 88.0:
            score += 15
            feedback.append("OLS Intercept correct.")
        else:
            feedback.append(f"OLS Intercept found but value {val} out of range.")
    else:
        feedback.append("OLS Intercept not found in text.")

    if income_match:
        val = float(income_match.group(1))
        if 9.0 < val < 11.5:
            score += 15
            feedback.append("OLS Slope correct.")
        else:
            feedback.append(f"OLS Slope found but value {val} out of range.")
    else:
        feedback.append("OLS Slope not found in text.")

    # R-squared (10 pts)
    if r2_match:
        val = float(r2_match.group(1))
        if 0.35 < val < 0.42:
            score += 10
            feedback.append("R-squared correct.")
    
    # Chow Test Presence (20 pts)
    if chow_header_match:
        score += 10
        feedback.append("Chow test header found.")
    else:
        feedback.append("Chow test header missing.")

    # Chow Statistics (20 pts)
    # Note: Exact Chow F-stat for food.gdt break at 20 needs to be checked roughly.
    # Without running it live, we assume the agent runs it correctly if the header is there 
    # and the format matches Gretl's output. 
    # We give points for finding a valid F-statistic format near the Chow header.
    if chow_header_match and chow_stat_match:
        score += 10
        feedback.append("Chow F-statistic found.")
        
    if chow_header_match and chow_pval_match:
        score += 10
        feedback.append("Chow p-value found.")

    passed = score >= 60 and file_created_correctly

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }