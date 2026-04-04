#!/usr/bin/env python3
"""
Verifier for recursive_forecast_loop task.

Verifies:
1. Hansl script creation (script file exists and contains loop logic).
2. RMSFE Result Accuracy (value in text file matches ground truth).
3. Forecast Errors (CSV file exists and has correct length).
4. Anti-gaming (files created during task).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recursive_forecast(traj, env_info, task_info):
    """
    Verify the recursive forecasting script and results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_rmsfe_min = metadata.get('expected_rmsfe_min', 0.55)
    expected_rmsfe_max = metadata.get('expected_rmsfe_max', 0.75)
    
    # Files to retrieve
    script_path = metadata.get('output_script', '/home/ga/Documents/gretl_output/recursive_forecast.inp')
    result_path = metadata.get('output_result', '/home/ga/Documents/gretl_output/rmsfe_results.txt')
    csv_path = metadata.get('output_csv', '/home/ga/Documents/gretl_output/forecast_errors.csv')

    # Load task result metadata
    task_result = {}
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

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Script Verification (30 points)
    # ------------------------------------------------------------------
    script_info = task_result.get('script_info', {})
    if script_info.get('exists') and script_info.get('valid_time'):
        # Retrieve script content
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read().lower()
            
            # Check for required logic keywords
            has_loop = 'loop' in script_content
            has_smpl = 'smpl' in script_content
            has_ols = 'ols' in script_content
            
            if has_loop and has_smpl and has_ols:
                score += 30
                feedback_parts.append("Script contains recursive loop logic")
            elif has_loop:
                score += 15
                feedback_parts.append("Script has loop but missing 'smpl' resizing or 'ols'")
            else:
                score += 5
                feedback_parts.append("Script file exists but missing loop logic")
                
        except Exception:
            feedback_parts.append("Script exists but could not be read")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback_parts.append("Script file not found or not created during task")

    # ------------------------------------------------------------------
    # 2. RMSFE Result Verification (40 points)
    # ------------------------------------------------------------------
    result_info = task_result.get('result_info', {})
    rmsfe_val = None
    
    if result_info.get('exists') and result_info.get('valid_time'):
        temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(result_path, temp_res.name)
            with open(temp_res.name, 'r') as f:
                content = f.read()
                # Find first float number in file
                match = re.search(r"([0-9]+\.[0-9]+)", content)
                if match:
                    rmsfe_val = float(match.group(1))
                    
            if rmsfe_val is not None:
                if expected_rmsfe_min <= rmsfe_val <= expected_rmsfe_max:
                    score += 40
                    feedback_parts.append(f"RMSFE correct ({rmsfe_val:.4f})")
                else:
                    score += 10 # Partial credit for outputting a number
                    feedback_parts.append(f"RMSFE calculated ({rmsfe_val:.4f}) but outside expected range ({expected_rmsfe_min}-{expected_rmsfe_max})")
            else:
                feedback_parts.append("Result file exists but no numeric value found")
        except Exception:
            feedback_parts.append("Failed to parse result file")
        finally:
            if os.path.exists(temp_res.name):
                os.unlink(temp_res.name)
    else:
        feedback_parts.append("RMSFE result file not found")

    # ------------------------------------------------------------------
    # 3. Forecast Errors CSV Verification (20 points)
    # ------------------------------------------------------------------
    csv_info = task_result.get('csv_info', {})
    if csv_info.get('exists') and csv_info.get('valid_time'):
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(csv_path, temp_csv.name)
            with open(temp_csv.name, 'r') as f:
                line_count = sum(1 for line in f)
            
            # Expected roughly 103 total obs - 40 start = ~63 forecasts
            # Allow some header lines or slight off-by-one
            if 50 <= line_count <= 80:
                score += 20
                feedback_parts.append(f"Forecast errors CSV has correct line count ({line_count})")
            elif line_count > 0:
                score += 10
                feedback_parts.append(f"Forecast errors CSV exists but line count unexpected ({line_count})")
            else:
                feedback_parts.append("Forecast errors CSV is empty")
        except Exception:
            feedback_parts.append("Failed to check CSV file")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("Forecast errors CSV not found")

    # ------------------------------------------------------------------
    # 4. Environment Check (10 points)
    # ------------------------------------------------------------------
    if task_result.get('gretl_running', False):
        score += 10
        feedback_parts.append("Gretl was running")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }