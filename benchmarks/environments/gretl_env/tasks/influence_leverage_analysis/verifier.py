#!/usr/bin/env python3
"""
Verifier for influence_leverage_analysis task.

Criteria:
1. Script file exists and is valid hansl (runs with gretlcli).
2. Script actually performs OLS (checked via validation output).
3. Report file exists and was created during task.
4. Report contains specific influence statistics (leverage/dffits).
5. Report contains correct regression coefficients (slope ~10.2).
"""

import json
import os
import base64
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_influence_leverage_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_slope = metadata.get('expected_slope', 10.2)
    slope_tolerance = metadata.get('slope_tolerance', 0.5)

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: Script Existence & Validity (30 pts) ---
    if result.get('script_exists'):
        score += 5
        feedback.append("Script file found.")
        
        if result.get('script_created_during_task'):
            score += 5
            feedback.append("Script created during task.")
        else:
            feedback.append("Script timestamp is old.")

        if result.get('script_valid_execution'):
            score += 20
            feedback.append("Script executes successfully (valid hansl).")
        else:
            feedback.append("Script execution failed (syntax errors).")
    else:
        feedback.append("Script file not found.")

    # --- Criterion 2: OLS execution check (20 pts) ---
    # We check the output of the validation run (gretlcli -b script.inp)
    script_output = ""
    if result.get('script_validation_output_b64'):
        try:
            script_output = base64.b64decode(result['script_validation_output_b64']).decode('utf-8', errors='ignore')
        except:
            pass

    if "Model 1: OLS" in script_output or "Dependent variable: food_exp" in script_output:
        score += 20
        feedback.append("Script correctly runs OLS regression.")
    elif result.get('script_valid_execution'):
        feedback.append("Script runs but didn't produce expected OLS output in validation.")

    # --- Criterion 3: Report Content (50 pts) ---
    report_content = ""
    if result.get('report_exists') and result.get('report_content_b64'):
        try:
            report_content = base64.b64decode(result['report_content_b64']).decode('utf-8', errors='ignore')
        except:
            pass
        
        # Check 3a: File exists and created during task
        if result.get('report_created_during_task'):
            score += 10
            feedback.append("Report file created during task.")
        
        # Check 3b: Keywords (Leverage/DFFITS)
        lower_content = report_content.lower()
        if "leverage" in lower_content or "hat" in lower_content:
            score += 10
            feedback.append("Report contains leverage/hat values.")
        else:
            feedback.append("Report missing leverage/hat keywords.")
            
        if "dffits" in lower_content:
            score += 10
            feedback.append("Report contains DFFITS statistics.")
        else:
            feedback.append("Report missing DFFITS keywords.")

        # Check 3c: Regression Coefficient (Slope validation)
        # Look for pattern like "income      10.2096"
        # Regex matches: income followed by whitespace and a float
        match = re.search(r'income\s+([-+]?\d*\.\d+|\d+)', report_content)
        if match:
            try:
                val = float(match.group(1))
                if abs(val - expected_slope) <= slope_tolerance:
                    score += 20
                    feedback.append(f"Slope coefficient correct ({val}).")
                else:
                    feedback.append(f"Slope coefficient {val} outside tolerance.")
            except:
                feedback.append("Could not parse slope coefficient.")
        else:
            # Fallback: check if the validation output (from gretlcli) had it
            # This handles cases where report might be formatted differently but script works
            match_script = re.search(r'income\s+([-+]?\d*\.\d+|\d+)', script_output)
            if match_script:
                 try:
                    val = float(match_script.group(1))
                    if abs(val - expected_slope) <= slope_tolerance:
                        # Partial credit if script produces it but report doesn't capture it perfectly
                        score += 10 
                        feedback.append(f"Slope correct in script execution, but not found in report file.")
                 except:
                     pass
    else:
        feedback.append("Report file not found or empty.")

    # Final logic
    passed = score >= 60 and result.get('script_valid_execution')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }