#!/usr/bin/env python3
"""Verifier for hurricane_fiona_buoy_analysis task.

Checks that the agent wrote an analysis script that properly parsed NOAA NDBC data,
filtered for September, ignored meteorological missing value markers (99.00 / 9999.0),
and output a correctly formatted summary report with the proper statistical values.
"""

import json
import os
import tempfile
import math

def verify_hurricane_fiona_buoy_analysis(traj, env_info, task_info):
    """Verify script logic and output against dynamic ground truth."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hurricane_fiona_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check for execution errors during export
    if result.get("error"):
        feedback.append(f"Warning during export: {result['error']}")

    # Criterion 1: Analysis script created (10 pts)
    if result.get("script_exists") and result.get("script_size", 0) > 20:
        score += 10
        feedback.append("Analysis script created")
    else:
        feedback.append("Analysis script missing or empty")

    # Criterion 2: Report created (10 pts)
    if result.get("report_exists") and result.get("report_size", 0) > 20:
        score += 10
        feedback.append("Summary report created")
    else:
        feedback.append("Summary report missing or empty")
        
    # Criterion 3: Formatting matches specification (10 pts)
    if result.get("format_correct"):
        score += 10
        feedback.append("Report format matches expected specification")
    else:
        feedback.append("Report format incorrect or missing expected lines")
        
    # Criterion 4: Maximum Wave Height correctness (35 pts)
    gt_wvht = result.get("gt_max_wvht")
    ag_wvht = result.get("agent_max_wvht")
    wvht_correct = False
    
    if gt_wvht is not None and ag_wvht is not None:
        if math.isclose(gt_wvht, ag_wvht, abs_tol=0.01):
            score += 35
            wvht_correct = True
            feedback.append(f"Max Wave Height correct ({ag_wvht} m)")
        else:
            feedback.append(f"Max Wave Height incorrect (expected {gt_wvht}, got {ag_wvht})")
    else:
        feedback.append("Max Wave Height value not found in report")
        
    # Criterion 5: Minimum Pressure correctness (35 pts)
    gt_pres = result.get("gt_min_pres")
    ag_pres = result.get("agent_min_pres")
    pres_correct = False
    
    if gt_pres is not None and ag_pres is not None:
        if math.isclose(gt_pres, ag_pres, abs_tol=0.01):
            score += 35
            pres_correct = True
            feedback.append(f"Min Pressure correct ({ag_pres} hPa)")
        else:
            feedback.append(f"Min Pressure incorrect (expected {gt_pres}, got {ag_pres})")
    else:
        feedback.append("Min Pressure value not found in report")
        
    # Pass threshold: 80% AND at least one statistical calculation perfectly correct
    passed = score >= 80 and (wvht_correct or pres_correct)
    
    if passed:
        feedback.append("Task successfully completed!")
    else:
        feedback.append("Task failed. Check script logic regarding missing value markers.")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "script_exists": result.get("script_exists", False),
            "report_exists": result.get("report_exists", False),
            "format_correct": result.get("format_correct", False),
            "wvht_correct": wvht_correct,
            "pres_correct": pres_correct
        }
    }