#!/usr/bin/env python3
"""
Verifier for sur_grunfeld_investment task.

Checks:
1. Output file exists and was created during task.
2. Contains "SUR" or "Seemingly Unrelated" keywords.
3. Contains estimation results for both GE and Westinghouse equations.
4. Coefficients match expected econometric ranges for the Grunfeld data.
5. Cross-equation correlation stats are present.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sur_grunfeld_investment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_coefs = metadata.get('expected_coefficients', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Get task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Check if file exists and was created during task
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file sur_results.txt not found."}
        
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during the current task session."}
    
    score += 10 # File created
    feedback_parts.append("Output file created")

    # 2. Get content of the output file
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    content = ""
    try:
        copy_from_env("/home/ga/Documents/gretl_output/sur_results.txt", temp_output.name)
        with open(temp_output.name, 'r', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read output file content: {e}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)
            
    if len(content) < 100:
        return {"passed": False, "score": score, "feedback": "Output file is too short/empty."}
        
    # 3. Analyze Content
    content_lower = content.lower()
    
    # Check for SUR method
    if "sur" in content_lower or "seemingly unrelated" in content_lower:
        score += 10
        feedback_parts.append("Method identified as SUR")
    else:
        feedback_parts.append("SUR method not explicitly identified in output")
        
    # Check for equations
    has_ge = "invest_ge" in content_lower or "equation 1" in content_lower
    has_wh = "invest_wh" in content_lower or "equation 2" in content_lower
    
    if has_ge and has_wh:
        score += 10
        feedback_parts.append("Both equations present")
    else:
        feedback_parts.append("Missing one or more equations")

    # Helper to extract coefficient
    # Looks for lines like: "value_ge   0.03831   0.0136 ..."
    def get_coef(var_name, text):
        # Regex: Start of line or whitespace, var_name, whitespace, float (coef)
        pattern = r"\b" + re.escape(var_name) + r"\s+([+-]?\d*\.\d+)"
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            try:
                return float(match.group(1))
            except ValueError:
                return None
        return None

    # Verify Coefficients
    # Ranges: 
    # GE Value: 0.02 - 0.06 (Real ~0.038)
    # GE Capital: 0.05 - 0.25 (Real ~0.15)
    # WH Value: 0.03 - 0.09 (Real ~0.05)
    # WH Capital: 0.01 - 0.20 (Real ~0.09) (Note: often insignificant in OLS, but positive in SUR)

    # GE Equation
    val_ge = get_coef("value_ge", content)
    cap_ge = get_coef("capital_ge", content)
    
    if val_ge is not None and 0.02 <= val_ge <= 0.06:
        score += 15
        feedback_parts.append(f"GE Value coef correct ({val_ge})")
    elif val_ge is not None:
        feedback_parts.append(f"GE Value coef out of range ({val_ge})")
        
    if cap_ge is not None and 0.05 <= cap_ge <= 0.25:
        score += 10
        feedback_parts.append(f"GE Capital coef correct ({cap_ge})")
        
    # WH Equation
    val_wh = get_coef("value_wh", content)
    cap_wh = get_coef("capital_wh", content)
    
    if val_wh is not None and 0.03 <= val_wh <= 0.09:
        score += 15
        feedback_parts.append(f"WH Value coef correct ({val_wh})")
        
    if cap_wh is not None and 0.01 <= cap_wh <= 0.20:
        score += 10
        feedback_parts.append(f"WH Capital coef correct ({cap_wh})")

    # Cross-equation stats
    # Look for correlation matrix or "Cross-equation" text
    if "cross-equation" in content_lower or "correlation matrix" in content_lower or "covariance matrix" in content_lower:
        score += 10
        feedback_parts.append("System stats present")

    # Anti-gaming check: Ensure it's not just OLS
    # In pure OLS, GE Value is ~0.026. In SUR, it's often slightly different/more efficient.
    # The main check is that they actually ran the system command.
    # If they just ran OLS twice, the output format is usually different (two separate Model blocks vs one System block).
    # SUR output in Gretl explicitly groups them.
    
    # Check if "System" appears in output
    if "system" in content_lower:
        score += 10
        feedback_parts.append("System estimation confirmed")

    passed = score >= 60 and "Method identified as SUR" in feedback_parts
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }