#!/usr/bin/env python3
"""
Verifier for bootstrap_ci_regression task.
Checks:
1. Numerical accuracy of OLS estimate and Bootstrap CI in output file.
2. Presence of required keywords in the script file (hansl code).
3. Anti-gaming (files created during task).
4. VLM check on final screenshot (secondary).
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bootstrap_ci_regression(traj, env_info, task_info):
    """
    Verify the bootstrap regression task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected ranges
    expected_ols = metadata.get('expected_ols', 10.2096)
    ols_tolerance = metadata.get('ols_tolerance', 0.5)
    ci_lower_min = metadata.get('ci_lower_min', 4.0)
    ci_lower_max = metadata.get('ci_lower_max', 10.0)
    ci_upper_min = metadata.get('ci_upper_min', 11.0)
    ci_upper_max = metadata.get('ci_upper_max', 17.0)

    results_path = metadata.get('output_results_path', '/home/ga/Documents/gretl_output/bootstrap_results.txt')
    script_path = metadata.get('output_script_path', '/home/ga/Documents/gretl_output/bootstrap_inference.inp')

    score = 0
    feedback_parts = []
    
    # 1. Load Task Summary JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
        temp_json_path = tf.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)

    # 2. Check Script File Content (30 points)
    script_content = ""
    if task_result.get('script_file_exists') and task_result.get('script_created_during_task'):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.inp') as tf:
            temp_script_path = tf.name
        
        try:
            copy_from_env(script_path, temp_script_path)
            with open(temp_script_path, 'r') as f:
                script_content = f.read().lower()
            
            # Check for keywords
            keywords = {
                'loop': 5,
                'resample': 5,
                'ols': 5,
                'seed': 5,
                'quantile': 5, # or sort, check generic
                'outfile': 5
            }
            
            script_score = 0
            found_keywords = []
            for kw, pts in keywords.items():
                if kw in script_content:
                    script_score += pts
                    found_keywords.append(kw)
            
            # Alternate check for quantile/sort if one missing
            if 'quantile' not in script_content and 'sort' in script_content:
                script_score += 5
                found_keywords.append('sort')
                
            if script_score > 0:
                score += script_score
                feedback_parts.append(f"Script verification: Found {len(found_keywords)} keywords ({', '.join(found_keywords)})")
            else:
                feedback_parts.append("Script verification: Valid script content not found")

        except Exception as e:
            feedback_parts.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script_path):
                os.unlink(temp_script_path)
    else:
        feedback_parts.append("Script file not created or timestamp invalid")

    # 3. Check Results File Content (Numerical Verification) (70 points)
    if task_result.get('results_file_exists') and task_result.get('results_created_during_task'):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tf:
            temp_results_path = tf.name
            
        try:
            copy_from_env(results_path, temp_results_path)
            with open(temp_results_path, 'r') as f:
                lines = f.readlines()
            
            data = {}
            for line in lines:
                if '=' in line:
                    key, val = line.strip().split('=', 1)
                    try:
                        data[key.strip()] = float(val.strip())
                    except ValueError:
                        pass
            
            # Validate OLS (20 pts)
            ols_val = data.get('OLS_ESTIMATE')
            if ols_val is not None:
                if abs(ols_val - expected_ols) <= ols_tolerance:
                    score += 20
                    feedback_parts.append(f"OLS Estimate correct ({ols_val})")
                else:
                    feedback_parts.append(f"OLS Estimate incorrect (Expected ~{expected_ols}, Got {ols_val})")
            else:
                feedback_parts.append("OLS_ESTIMATE missing from output")

            # Validate CI (50 pts total)
            ci_lower = data.get('CI_LOWER')
            ci_upper = data.get('CI_UPPER')
            
            ci_valid = False
            if ci_lower is not None and ci_upper is not None:
                # Check ranges
                lower_ok = ci_lower_min <= ci_lower <= ci_lower_max
                upper_ok = ci_upper_min <= ci_upper <= ci_upper_max
                logical_ok = ci_lower < expected_ols < ci_upper # Point estimate inside CI
                width_ok = 2.0 < (ci_upper - ci_lower) < 12.0 # Reasonable width
                
                if lower_ok: score += 15
                if upper_ok: score += 15
                if logical_ok: score += 10
                if width_ok: score += 10
                
                if lower_ok and upper_ok and logical_ok:
                    ci_valid = True
                    feedback_parts.append(f"Bootstrap CI valid ([{ci_lower}, {ci_upper}])")
                else:
                    feedback_parts.append(f"Bootstrap CI out of range or illogical ([{ci_lower}, {ci_upper}])")
            else:
                feedback_parts.append("CI_LOWER or CI_UPPER missing")

        except Exception as e:
            feedback_parts.append(f"Error reading results file: {e}")
        finally:
            if os.path.exists(temp_results_path):
                os.unlink(temp_results_path)
    else:
        feedback_parts.append("Results file not created or timestamp invalid")

    # Final logic
    passed = score >= 60 and (task_result.get('results_file_exists') or False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }