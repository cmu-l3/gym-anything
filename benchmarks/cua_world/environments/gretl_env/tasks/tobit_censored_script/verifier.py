#!/usr/bin/env python3
"""
Verifier for tobit_censored_script task.
Checks for correct OLS and Tobit estimation results on the Mroz dataset.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tobit_censored_script(traj, env_info, task_info):
    """
    Verify the OLS vs Tobit comparison task.
    
    Rubric (100 pts total):
    1. Output file exists and created during task (15 pts)
    2. Script file exists and created during task (10 pts)
    3. Output contains valid OLS coefficient for kidsl6 (20 pts)
    4. Output contains valid Tobit coefficient for kidsl6 (20 pts)
    5. Bias demonstrated: Tobit effect magnitude > OLS effect magnitude (15 pts)
    6. Script content check (exper_sq creation, tobit command) (10 pts)
    7. VLM verification of trajectory (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_ols = metadata.get('expected_ols_kidsl6', -342.0)
    expected_tobit = metadata.get('expected_tobit_kidsl6', -894.0)
    tol_ols = metadata.get('tolerance_ols', 20.0)
    tol_tobit = metadata.get('tolerance_tobit', 60.0) # Higher tolerance for optimization variations

    score = 0
    feedback = []
    
    # 1. Get Result JSON
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

    # 2. Check File Existence
    if result_data.get('output_exists') and result_data.get('output_created_in_task'):
        score += 15
        feedback.append("Output file created.")
    else:
        feedback.append("Output file missing or not created during task.")

    if result_data.get('script_exists') and result_data.get('script_created_in_task'):
        score += 10
        feedback.append("Script file created.")
    else:
        feedback.append("Script file missing.")

    # 3. Analyze Output Content (The numerical results)
    ols_kids_found = False
    tobit_kids_found = False
    ols_val = 0.0
    tobit_val = 0.0

    if result_data.get('output_exists'):
        temp_out = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(metadata.get('output_file'), temp_out.name)
            with open(temp_out.name, 'r', errors='ignore') as f:
                content = f.read()
                
            # Find numbers in the content
            # The agent might label them variously, so we look for numbers close to expected values
            # This is robust to formatting (matrix print vs table print)
            
            numbers = [float(x) for x in re.findall(r'-?\d+\.\d+', content)]
            
            # Check for OLS value
            for num in numbers:
                if abs(num - expected_ols) < tol_ols:
                    ols_kids_found = True
                    ols_val = num
                    break
            
            # Check for Tobit value
            for num in numbers:
                if abs(num - expected_tobit) < tol_tobit:
                    tobit_kids_found = True
                    tobit_val = num
                    break
                    
        except Exception as e:
            feedback.append(f"Error reading output content: {e}")
        finally:
            if os.path.exists(temp_out.name):
                os.unlink(temp_out.name)

    if ols_kids_found:
        score += 20
        feedback.append(f"Found valid OLS coefficient ({ols_val}).")
    else:
        feedback.append(f"Could not identify correct OLS coefficient (expected ~{expected_ols}).")

    if tobit_kids_found:
        score += 20
        feedback.append(f"Found valid Tobit coefficient ({tobit_val}).")
    else:
        feedback.append(f"Could not identify correct Tobit coefficient (expected ~{expected_tobit}).")

    # 4. Check Bias Demonstration
    if ols_kids_found and tobit_kids_found:
        # Check if magnitude of Tobit is significantly larger than OLS (as expected for censored data)
        if abs(tobit_val) > abs(ols_val) + 100:
            score += 15
            feedback.append("Results correctly demonstrate Tobit bias correction.")
        else:
            feedback.append("Warning: Tobit coefficient magnitude not significantly larger than OLS.")

    # 5. Check Script Content
    if result_data.get('script_exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
        try:
            copy_from_env(metadata.get('script_file'), temp_script.name)
            with open(temp_script.name, 'r', errors='ignore') as f:
                script_content = f.read().lower()
            
            if 'tobit' in script_content:
                score += 5
                feedback.append("Script uses 'tobit' command.")
            if 'exper' in script_content and ('^2' in script_content or '*' in script_content or 'sq' in script_content):
                score += 5
                feedback.append("Script appears to construct squared experience.")
                
        except Exception as e:
            pass
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    
    # 6. Basic VLM Check (Placeholder for trajectory check)
    # If we have a final screenshot and any score so far, give points
    if result_data.get('screenshot_path') and score > 0:
        score += 10
        feedback.append("Visual evidence exists.")

    passed = score >= 70 and ols_kids_found and tobit_kids_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }