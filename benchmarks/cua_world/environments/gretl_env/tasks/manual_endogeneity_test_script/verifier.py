#!/usr/bin/env python3
"""
Verifier for manual_endogeneity_test_script task.

This task requires the agent to:
1. Restrict sample to working women (n=428)
2. Run 1st stage regression: educ = f(instruments)
3. Save residuals (v_hat)
4. Run 2nd stage regression: lwg = f(educ, controls, v_hat)
5. Save output

Verification checks:
1. Output file exists and was created during task.
2. Sample size in output is 428 (verifies sample restriction).
3. Variable 'v_hat' is present in the regression.
4. Coefficient for 'v_hat' is approximately 0.057 (verifies correct residuals).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manual_endogeneity_test_script(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/gretl_output/endogeneity_test_results.txt')
    target_coeff_v_hat = metadata.get('target_coeff_v_hat', 0.057)
    tolerance = metadata.get('tolerance', 0.015)
    
    score = 0
    feedback_parts = []
    
    # 1. Check Task Result JSON (Timing & Existence)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task window."}
        
    score += 10
    feedback_parts.append("File created")

    # 2. Analyze Content of the Output File
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    content = ""
    try:
        copy_from_env(expected_output_path, temp_txt.name)
        with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output file: {e}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)
            
    # Check 2.1: Sample Size (Restriction check)
    # Gretl output usually says "using observations 1-428" or "n = 428"
    # Or in the summary stats: "Mean dependent var ... (n = 428)"
    
    sample_size_correct = False
    if "428" in content:
        # stricter check
        if re.search(r"observations\s+.*428", content, re.IGNORECASE) or \
           re.search(r"n\s*=\s*428", content, re.IGNORECASE):
            sample_size_correct = True
            
    if sample_size_correct:
        score += 20
        feedback_parts.append("Sample restriction correct (n=428)")
    else:
        feedback_parts.append("Sample restriction failed (expected n=428)")

    # Check 2.2: Variable Presence (v_hat)
    # The user should have named it v_hat, but we can look for the concept if they named it differently?
    # No, instructions explicitly said "v_hat".
    
    if "v_hat" in content:
        score += 20
        feedback_parts.append("'v_hat' included")
    else:
        feedback_parts.append("'v_hat' missing from regression")

    # Check 2.3: Coefficient Values
    # We parse the line containing v_hat to find the coefficient
    # Example line: "  v_hat        0.05734   0.038..."
    
    coeff_correct = False
    v_hat_line_match = re.search(r"v_hat\s+([-\d\.]+)", content)
    
    if v_hat_line_match:
        try:
            val = float(v_hat_line_match.group(1))
            if abs(val - target_coeff_v_hat) < tolerance:
                coeff_correct = True
                score += 30
                feedback_parts.append(f"v_hat coefficient correct ({val})")
            else:
                feedback_parts.append(f"v_hat coefficient incorrect ({val}, expected ~{target_coeff_v_hat})")
        except ValueError:
            feedback_parts.append("Could not parse v_hat coefficient")
    
    # Check structural variables are also present
    vars_present = 0
    for v in ["educ", "exper", "expersq"]:
        if v in content:
            vars_present += 1
            
    if vars_present == 3:
        score += 20
        feedback_parts.append("Structural variables present")
    else:
        feedback_parts.append(f"Missing structural variables ({vars_present}/3)")

    passed = score >= 70 and sample_size_correct and coeff_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }