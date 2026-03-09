#!/usr/bin/env python3
"""
Verifier for Cochrane-Orcutt AR(1) Correction Task.
Verifies that the agent created a valid Gretl script and reported correct econometric statistics.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cochrane_orcutt(traj, env_info, task_info):
    """
    Verify the Cochrane-Orcutt AR(1) task.
    
    Criteria:
    1. Script file exists, was created during task, and contains key commands (ols, ar1).
    2. Results file exists and contains plausible numeric values for DW, Rho, and coefficients.
    3. GDP growth variable creation logic is present in the script.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    script_path = "/home/ga/Documents/gretl_output/cochrane_orcutt.inp"
    results_path = "/home/ga/Documents/gretl_output/cochrane_orcutt_results.txt"
    
    score = 0
    feedback_parts = []
    
    # 1. Load export result JSON
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify Script File
    script_info = task_result.get("script_file", {})
    if script_info.get("exists") and script_info.get("size", 0) > 10:
        score += 10
        if script_info.get("created_during_task"):
            score += 5  # Bonus for freshness
            
        # Analyze script content
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r') as f:
                content = f.read().lower()
                
            # Check for OLS command
            if "ols" in content:
                score += 10
                feedback_parts.append("Script contains OLS command.")
            else:
                feedback_parts.append("Script missing 'ols' command.")

            # Check for AR1 command or Cochrane-Orcutt equivalent
            if "ar1" in content or "cochrane" in content:
                score += 15
                feedback_parts.append("Script contains AR(1)/Cochrane-Orcutt command.")
            else:
                feedback_parts.append("Script missing 'ar1' command.")

            # Check for variable creation (growth rate)
            # Look for 'genr', 'diff', 'log', or mathematical operations on gdp
            if any(x in content for x in ["genr", "diff", "log(", "gdp/gdp(-1)", "growth"]):
                score += 10
                feedback_parts.append("Script appears to create transformed variable.")
            else:
                feedback_parts.append("Script may be missing growth rate calculation.")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing script content: {str(e)}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback_parts.append("Script file not found or empty.")

    # 3. Verify Results File
    results_info = task_result.get("results_file", {})
    if results_info.get("exists") and results_info.get("size", 0) > 20:
        score += 10
        
        # Analyze results content
        temp_results = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(results_path, temp_results.name)
            with open(temp_results.name, 'r') as f:
                content = f.read()
            
            # Extract all numbers from the text
            # Matches floats like 1.23, -0.45, 1.5e-3
            numbers = [float(x) for x in re.findall(r'-?\d+\.\d+', content)]
            
            # Check for DW statistic (typically 0.5 - 2.5 for this type of data)
            dw_candidates = [n for n in numbers if 0.0 < n < 4.0]
            if dw_candidates:
                score += 15
                feedback_parts.append(f"Found valid DW-like statistic ({dw_candidates[0]}).")
            else:
                feedback_parts.append("No valid Durbin-Watson statistic found in results.")

            # Check for Rho (correlation coefficient, -1 to 1)
            # Usually positive for economic time series
            rho_candidates = [n for n in numbers if -1.0 < n < 1.0]
            if rho_candidates:
                score += 15
                feedback_parts.append(f"Found valid Rho-like estimate ({rho_candidates[0]}).")
            else:
                feedback_parts.append("No valid AR(1) rho estimate found.")

            # Check for coefficients (at least 2 distinct values for intercept and slope)
            # Need at least 4 numbers total (DW, Rho, Beta0, Beta1)
            if len(numbers) >= 4:
                score += 15
                feedback_parts.append("Results file contains sufficient numeric data (coefficients).")
            else:
                feedback_parts.append("Results file contains too few numeric values.")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing results content: {str(e)}")
        finally:
            if os.path.exists(temp_results.name):
                os.unlink(temp_results.name)
    else:
        feedback_parts.append("Results file not found or empty.")

    # Anti-gaming check: File creation time
    if script_info.get("exists") and not script_info.get("created_during_task"):
        feedback_parts.append("WARNING: Script file timestamp is before task start.")
        score = max(0, score - 20)

    # Final verdict
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }