#!/usr/bin/env python3
"""
Verifier for compute_flood_volume task.
Compares agent's calculated values against ground truth computed inside the container.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_flood_volume(traj, env_info, task_info):
    """
    Verify the flood volume computation task.
    
    Scoring:
    - Script validity (15 pts)
    - Report existence (10 pts)
    - Data accuracy (75 pts split across fields)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: Script Basics (15 pts)
    if result.get("script_exists", False):
        score += 5
        if result.get("script_valid", False):
            score += 5
            if result.get("imports_h5py", False):
                score += 5
                feedback.append("Script is valid Python using h5py.")
            else:
                feedback.append("Script does not appear to import h5py.")
        else:
            feedback.append("Script has syntax errors.")
    else:
        feedback.append("Script file not found.")

    # Check 2: Report Existence (10 pts)
    if result.get("report_exists", False):
        score += 10
        feedback.append("Report file found.")
    else:
        feedback.append("Report file not found.")

    # Check 3: Data Accuracy (75 pts)
    gt = result.get("ground_truth", {})
    agent = result.get("agent_data", {})
    
    if not gt.get("success", False):
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Verifier failed to compute ground truth: {gt.get('error')}." + " ".join(feedback)
        }

    # Extract values
    try:
        gt_idx = gt["gt_peak_idx"]
        gt_count = gt["gt_xs_count"]
        gt_vol_ft3 = gt["gt_vol_ft3"]
        gt_vol_m3 = gt["gt_vol_m3"]
        
        ag_idx = int(agent["peak_idx"])
        ag_count = int(agent["xs_count"])
        ag_vol_ft3 = float(agent["vol_ft3"])
        ag_vol_m3 = float(agent["vol_m3"])
    except (ValueError, KeyError, TypeError):
        return {
            "passed": False,
            "score": score,
            "feedback": "Failed to parse numeric values from agent report. " + " ".join(feedback)
        }

    # Accuracy Checks
    
    # Cross Section Count (10 pts)
    if ag_count == gt_count:
        score += 10
        feedback.append(f"Correct XS count ({gt_count}).")
    else:
        feedback.append(f"Incorrect XS count: got {ag_count}, expected {gt_count}.")

    # Peak Index (10 pts) - Allow +/- 1 tolerance for floating point summation differences
    if abs(ag_idx - gt_idx) <= 1:
        score += 10
        feedback.append(f"Correct peak time index ({ag_idx}).")
    else:
        feedback.append(f"Incorrect peak time index: got {ag_idx}, expected {gt_idx}.")

    # Volume ft3 (25 pts) - 20% tolerance
    diff_ft3 = abs(ag_vol_ft3 - gt_vol_ft3)
    if gt_vol_ft3 > 0:
        pct_err_ft3 = (diff_ft3 / gt_vol_ft3) * 100
        if pct_err_ft3 <= 5.0:
            score += 25
            feedback.append(f"Volume (ft3) highly accurate ({pct_err_ft3:.2f}% error).")
        elif pct_err_ft3 <= 20.0:
            score += 15
            feedback.append(f"Volume (ft3) acceptable ({pct_err_ft3:.2f}% error).")
        else:
            feedback.append(f"Volume (ft3) incorrect: got {ag_vol_ft3}, expected ~{gt_vol_ft3} ({pct_err_ft3:.1f}% error).")
    
    # Volume m3 (20 pts) - Check consistency with ft3 value provided by agent
    # This proves they applied the conversion factor correctly to THEIR number
    expected_m3_from_agent_ft3 = ag_vol_ft3 * 0.0283168
    diff_consistency = abs(ag_vol_m3 - expected_m3_from_agent_ft3)
    
    if ag_vol_ft3 > 0:
        pct_err_const = (diff_consistency / expected_m3_from_agent_ft3) * 100
        if pct_err_const <= 2.0:
            score += 20
            feedback.append("Metric conversion is mathematically consistent.")
        else:
            feedback.append("Metric conversion inconsistent with reported ft3 value.")
            
    # Anti-gaming check: "Do Nothing" results in -1 values, which fail all accuracy checks.
    
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }