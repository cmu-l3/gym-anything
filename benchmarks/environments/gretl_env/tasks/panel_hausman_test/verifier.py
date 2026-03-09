#!/usr/bin/env python3
"""
Verifier for panel_hausman_test task.

Verifies:
1. Script file creation and content.
2. Output file generation (execution of script).
3. Correct model estimation (Fixed Effects & Random Effects coefficients).
4. Hausman test execution and results.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_panel_hausman_test(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    SCORE_SCRIPT_EXISTS = 10
    SCORE_RESULT_EXISTS = 10
    SCORE_FE_MODEL = 20
    SCORE_RE_MODEL = 20
    SCORE_HAUSMAN = 20
    SCORE_ACCURACY = 20 # 10 for FE values, 10 for RE values

    score = 0
    feedback = []
    
    # Load metadata expectations
    meta = task_info.get('metadata', {}).get('expected_values', {})
    expected_fe_mvalue = meta.get('fe_mvalue', 0.110)
    expected_fe_kstock = meta.get('fe_kstock', 0.310)
    expected_re_mvalue = meta.get('re_mvalue', 0.110)
    expected_re_kstock = meta.get('re_kstock', 0.308)
    tolerance = meta.get('tolerance', 0.02)

    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check Script
    if result.get("script_exists"):
        score += SCORE_SCRIPT_EXISTS
        feedback.append("Script file created.")
    else:
        feedback.append("Script file 'panel_analysis.inp' not found.")

    # 3. Check Result File Existence
    if result.get("result_exists") and result.get("result_created_during_task"):
        score += SCORE_RESULT_EXISTS
        feedback.append("Output file generated.")
    else:
        feedback.append("Output file 'panel_results.txt' missing or not created during task.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 4. Parse Result Content
    # We need to read the actual text content of panel_results.txt
    result_content = ""
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/panel_results.txt", temp_txt.name)
        with open(temp_txt.name, 'r', errors='replace') as f:
            result_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output content: {str(e)}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    # Normalize whitespace
    content_norm = " ".join(result_content.split())

    # Check for Fixed Effects
    has_fe = "Fixed-effects" in result_content or "Fixed Effects" in result_content
    if has_fe:
        score += SCORE_FE_MODEL
        feedback.append("Fixed Effects model found.")
    else:
        feedback.append("Fixed Effects model NOT found in output.")

    # Check for Random Effects
    has_re = "Random-effects" in result_content or "Random Effects" in result_content or "GLS" in result_content
    if has_re:
        score += SCORE_RE_MODEL
        feedback.append("Random Effects model found.")
    else:
        feedback.append("Random Effects model NOT found in output.")

    # Check for Hausman Test
    has_hausman = "Hausman test" in result_content
    if has_hausman:
        score += SCORE_HAUSMAN
        feedback.append("Hausman test found.")
    else:
        feedback.append("Hausman test NOT found in output.")

    # Check Accuracy (Regex parsing)
    # Look for patterns like: "mvalue  0.110123" or "mvalue   0.110"
    # Gretl output table usually: Variable  Coefficient  Std. Error ...
    
    def extract_coeff(var_name, text):
        # Regex: var_name followed by whitespace and a float
        # Handles scientific notation if needed, but usually standard decimals in Gretl
        pattern = re.compile(rf"{var_name}\s+([+-]?\d*\.\d+)")
        matches = pattern.findall(text)
        if matches:
            # If multiple models, this is tricky. We need to split the text.
            return [float(m) for m in matches]
        return []

    # Split text roughly by model headers to avoid confusion
    # This is a heuristic split
    parts = result_content.split("Random-effects")
    fe_part = parts[0] if len(parts) > 0 else ""
    re_part = parts[1] if len(parts) > 1 else ""

    # Verify FE Coeffs
    fe_mvalue_vals = extract_coeff("mvalue", fe_part)
    fe_kstock_vals = extract_coeff("kstock", fe_part)
    
    fe_accurate = False
    if fe_mvalue_vals and fe_kstock_vals:
        # Take the last occurrence in the FE section (in case of multiple runs)
        m = fe_mvalue_vals[-1]
        k = fe_kstock_vals[-1]
        if abs(m - expected_fe_mvalue) < tolerance and abs(k - expected_fe_kstock) < tolerance:
            fe_accurate = True
    
    if fe_accurate:
        score += 10
        feedback.append("Fixed Effects coefficients accurate.")
    elif has_fe:
        feedback.append(f"Fixed Effects coefficients incorrect or not parsed. Expected ~{expected_fe_mvalue}, ~{expected_fe_kstock}.")

    # Verify RE Coeffs
    re_mvalue_vals = extract_coeff("mvalue", re_part)
    re_kstock_vals = extract_coeff("kstock", re_part)

    re_accurate = False
    if re_mvalue_vals and re_kstock_vals:
        m = re_mvalue_vals[-1]
        k = re_kstock_vals[-1]
        if abs(m - expected_re_mvalue) < tolerance and abs(k - expected_re_kstock) < tolerance:
            re_accurate = True

    if re_accurate:
        score += 10
        feedback.append("Random Effects coefficients accurate.")
    elif has_re:
        feedback.append(f"Random Effects coefficients incorrect or not parsed. Expected ~{expected_re_mvalue}, ~{expected_re_kstock}.")

    passed = (score >= 60 and has_fe and has_hausman)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }