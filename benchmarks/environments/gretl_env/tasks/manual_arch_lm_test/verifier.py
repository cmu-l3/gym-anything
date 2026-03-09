#!/usr/bin/env python3
"""
Verifier for manual_arch_lm_test task.
Verifies that the agent manually calculated the ARCH-LM statistic and p-value correctly.
"""

import json
import os
import re
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manual_arch_lm_test(traj, env_info, task_info):
    """
    Verify the ARCH-LM test task.
    
    Criteria:
    1. Script file exists and contains valid logic (25 pts)
       - Must create squared residuals (uhat^2)
       - Must run auxiliary regression
    2. Results file exists (15 pts)
    3. Correct LM Statistic reported (30 pts)
       - Matches ground truth within tolerance
    4. Correct P-value reported (30 pts)
       - Matches ground truth within tolerance
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    result = {}
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

    score = 0
    feedback = []
    
    # 1. Check Script (25 pts)
    script_exists = result.get('script_exists', False)
    if script_exists:
        # Fetch script content
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
        try:
            copy_from_env("/tmp/agent_script.inp", temp_script.name)
            with open(temp_script.name, 'r') as f:
                script_content = f.read().lower()
            
            # Logic Checks
            has_ols = 'ols' in script_content
            has_squaring = ('^2' in script_content) or ('**2' in script_content) or ('sq' in script_content)
            has_lag = '(-1)' in script_content
            
            if has_ols and has_squaring and has_lag:
                score += 25
                feedback.append("Script contains regression, residual squaring, and lags.")
            elif has_ols:
                score += 10
                feedback.append("Script contains regression but missing specific transformation steps.")
            else:
                feedback.append("Script exists but lacks regression commands.")
        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Script file not found.")

    # 2. Check Results File Existence (15 pts)
    results_exists = result.get('results_exists', False)
    if results_exists:
        score += 15
        feedback.append("Results file found.")
    else:
        feedback.append("Results file not found.")

    # 3. & 4. numeric Verification (60 pts total)
    if results_exists:
        try:
            # Get Ground Truth
            gt_lm_str = result.get('ground_truth_lm', '0')
            gt_pval_str = result.get('ground_truth_pval', '0')
            
            try:
                gt_lm = float(gt_lm_str)
                gt_pval = float(gt_pval_str)
            except ValueError:
                # Fallback if ground truth calc failed in shell script
                gt_lm = 13.0  # Approx for usa.gdt inf
                gt_pval = 0.0003
                logger.warning("Using fallback ground truth values")

            # Fetch agent results
            temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env("/tmp/agent_results.txt", temp_res.name)
            with open(temp_res.name, 'r') as f:
                res_content = f.read()
            if os.path.exists(temp_res.name):
                os.unlink(temp_res.name)
            
            # Extract all numbers from the text
            # We look for numbers that match the ground truth
            # This is robust to different formatting (e.g. "LM = 13.5" vs "13.5")
            numbers = [float(x) for x in re.findall(r"-?\d+\.\d+", res_content)]
            
            # Check LM Statistic (30 pts)
            # Tolerance: +/- 0.5 (allow for small sample/df differences)
            lm_found = False
            for num in numbers:
                if abs(num - gt_lm) < 0.5:
                    lm_found = True
                    break
            
            if lm_found:
                score += 30
                feedback.append(f"LM Statistic correct (found value near {gt_lm:.2f}).")
            else:
                feedback.append(f"LM Statistic incorrect or missing (Expected ~{gt_lm:.2f}).")

            # Check P-value (30 pts)
            # Tolerance: +/- 0.01
            pval_found = False
            for num in numbers:
                if abs(num - gt_pval) < 0.01:
                    pval_found = True
                    break
            
            if pval_found:
                score += 30
                feedback.append(f"P-value correct (found value near {gt_pval:.4f}).")
            else:
                # Sometimes scientific notation is used
                feedback.append(f"P-value incorrect or missing (Expected ~{gt_pval:.4f}).")

        except Exception as e:
            feedback.append(f"Error validating numeric results: {e}")

    # Pass Threshold
    # Must get script logic AND at least one correct number (LM or pval)
    # OR get both numbers correct
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }