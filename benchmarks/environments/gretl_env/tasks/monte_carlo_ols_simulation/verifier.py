#!/usr/bin/env python3
"""
Verifier for monte_carlo_ols_simulation task.

Criteria:
1. Script file exists and contains simulation logic (loop, seed, ols).
2. Results file exists and contains valid mean/sd of estimator.
3. Values match expected theoretical ranges (Mean ~3.0, SD ~0.1).
4. Files created during task execution.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_results_file(content):
    """Parse key-value pairs from the results text file."""
    data = {}
    # Look for patterns like "mean_b1 = 3.001" or just "3.001" if unlabeled
    # The task specifies "mean_b1 = <value>", so we look for that first
    
    for line in content.splitlines():
        line = line.strip()
        if not line:
            continue
            
        # Try "key = value" pattern
        if '=' in line:
            key, val = line.split('=', 1)
            key = key.strip().lower()
            val = val.strip()
            try:
                data[key] = float(val)
            except ValueError:
                pass
    
    return data

def verify_monte_carlo_simulation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_mean_range = metadata.get('expected_mean_range', [2.85, 3.15])
    expected_sd_range = metadata.get('expected_sd_range', [0.05, 0.25])
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Load JSON Result
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # ================================================================
    # 2. Verify Results File (Content & Values) - 50 Points
    # ================================================================
    results_created = task_result.get('results_created_during_task', False)
    results_valid = False
    
    if results_created:
        temp_results = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/Documents/gretl_output/monte_carlo_results.txt", temp_results.name)
            with open(temp_results.name, 'r') as f:
                content = f.read()
                
            data = parse_results_file(content)
            
            # Check mean_b1
            mean_val = data.get('mean_b1')
            if mean_val is not None and expected_mean_range[0] <= mean_val <= expected_mean_range[1]:
                score += 20
                feedback_parts.append(f"Mean b1 correct ({mean_val})")
                results_valid = True
            elif mean_val is not None:
                score += 5
                feedback_parts.append(f"Mean b1 out of range ({mean_val})")
            else:
                feedback_parts.append("Mean b1 not found")
                
            # Check sd_b1
            sd_val = data.get('sd_b1')
            if sd_val is not None and expected_sd_range[0] <= sd_val <= expected_sd_range[1]:
                score += 20
                feedback_parts.append(f"SD b1 correct ({sd_val})")
            elif sd_val is not None:
                score += 5
                feedback_parts.append(f"SD b1 out of range ({sd_val})")
            else:
                feedback_parts.append("SD b1 not found")
                
            # Check true_b1
            true_val = data.get('true_b1')
            if true_val is not None and abs(true_val - 3.0) < 0.01:
                score += 10
                feedback_parts.append("True b1 correct")
            else:
                feedback_parts.append("True b1 missing/incorrect")
                
        except Exception as e:
            feedback_parts.append(f"Error reading results file: {e}")
        finally:
            if os.path.exists(temp_results.name):
                os.unlink(temp_results.name)
    else:
        feedback_parts.append("Results file not created during task")

    # ================================================================
    # 3. Verify Script File (Structure) - 40 Points
    # ================================================================
    script_created = task_result.get('script_created_during_task', False)
    
    if script_created:
        score += 10 # Base points for creating script
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
        try:
            copy_from_env("/home/ga/Documents/gretl_output/monte_carlo.inp", temp_script.name)
            with open(temp_script.name, 'r') as f:
                script_content = f.read().lower()
            
            # Check for key simulation components
            if 'seed' in script_content and '54321' in script_content:
                score += 10
                feedback_parts.append("Seed set correctly")
            else:
                feedback_parts.append("Seed 54321 missing")
                
            if 'loop' in script_content:
                score += 10
                feedback_parts.append("Loop construct found")
            else:
                feedback_parts.append("Loop missing")
                
            if 'ols' in script_content:
                score += 10
                feedback_parts.append("OLS command found")
            else:
                feedback_parts.append("OLS command missing")
                
        except Exception as e:
            feedback_parts.append(f"Error reading script file: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback_parts.append("Script file not created during task")

    # ================================================================
    # 4. App State - 10 Points
    # ================================================================
    if task_result.get('app_was_running', False):
        score += 10
    
    # Calculate final status
    # Must have valid results (mean correct) to pass
    passed = (score >= 65) and results_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }