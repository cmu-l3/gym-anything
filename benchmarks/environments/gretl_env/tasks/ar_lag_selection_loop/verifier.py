#!/usr/bin/env python3
"""
Verifier for ar_lag_selection_loop task.
"""

import json
import os
import re
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ar_lag_selection_loop(traj, env_info, task_info):
    """
    Verifies that the agent created a Gretl script using a loop to estimate models
    and generated a report with R-squared values.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Points breakdown
    score = 0
    max_score = 100
    feedback_parts = []

    # 1. Retrieve JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check Script Existence and Content (40 points)
    script_exists = result.get("script_exists", False)
    script_created = result.get("script_created_during_task", False)
    
    script_content = ""
    if script_exists:
        # Retrieve the script file content
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
        try:
            copy_from_env("/tmp/agent_script.inp", temp_script.name)
            with open(temp_script.name, 'r') as f:
                script_content = f.read()
        except Exception:
            feedback_parts.append("Script file exists but could not be read.")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

        if script_created:
            score += 10
            feedback_parts.append("Script file created.")
        else:
            feedback_parts.append("Script file exists but verified as old.")

        # Check for loop syntax (Gretl 'loop' or 'foreach')
        # Case insensitive check
        lower_script = script_content.lower()
        if "loop" in lower_script or "foreach" in lower_script:
            score += 20
            feedback_parts.append("Loop construct found in script.")
        else:
            feedback_parts.append("No loop construct found in script.")

        # Check for OLS command
        if "ols" in lower_script:
            score += 10
            feedback_parts.append("OLS estimation command found.")
        else:
            feedback_parts.append("No OLS command found.")
    else:
        feedback_parts.append("Script file not found.")

    # 3. Check Report Existence and Content (60 points)
    report_exists = result.get("report_exists", False)
    report_content_b64 = result.get("report_content_b64", "")
    
    if report_exists and report_content_b64:
        score += 10 # Base points for creating report
        try:
            report_text = base64.b64decode(report_content_b64).decode('utf-8', errors='ignore')
            lines = report_text.strip().split('\n')
            
            # Filter for lines containing numbers
            valid_lines = []
            for line in lines:
                # Look for lines with at least two numbers (Lag and R2)
                numbers = re.findall(r"[-+]?\d*\.\d+|\d+", line)
                if len(numbers) >= 2:
                    valid_lines.append(numbers)
            
            if len(valid_lines) >= 4:
                score += 20
                feedback_parts.append(f"Report contains {len(valid_lines)} data rows (expected >= 4).")
                
                # Check R-squared plausibility
                # US Inflation AR models typically have R^2 between 0.1 and 0.9
                # We check the second number in the row (assuming first is lag index or constant)
                valid_r2 = 0
                for row in valid_lines:
                    # Heuristic: the R2 is likely the float < 1.0
                    row_floats = [float(x) for x in row]
                    r2_candidates = [x for x in row_floats if 0.0 <= x <= 1.0]
                    if r2_candidates:
                        valid_r2 += 1
                
                if valid_r2 >= 4:
                    score += 30
                    feedback_parts.append("R-squared values appear valid.")
                else:
                    score += 10
                    feedback_parts.append("Rows found, but values don't look like R-squared (0.0-1.0).")
            else:
                feedback_parts.append(f"Report too short: found {len(valid_lines)} valid lines, expected 4.")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing report content: {e}")
    else:
        feedback_parts.append("Report file not found or empty.")

    # 4. Success Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }