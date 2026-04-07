#!/usr/bin/env python3
"""
Verifier for Hydrology Catchment Calibration Task (airGR).

Criteria:
1. 'airGR' package installed (10 pts)
2. Script modified & uses correct functions (10 pts)
3. Data split correctly & Metrics CSV created (15 pts)
4. Calibration NSE > 0.70 (25 pts)
5. Validation NSE > 0.60 (25 pts)
6. Hydrograph plot created & valid (15 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hydrology_calibration(traj, env_info, task_info):
    """
    Verify the agent calibrated the hydrological model correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata for thresholds
    metadata = task_info.get('metadata', {})
    min_calib = metadata.get('min_calibration_nse', 0.70)
    min_valid = metadata.get('min_validation_nse', 0.60)

    # Read result JSON
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
    feedback_parts = []
    
    # 1. Package Installation (10 pts)
    if result.get('package_installed', False):
        score += 10
        feedback_parts.append("airGR installed (+10)")
    else:
        feedback_parts.append("airGR NOT installed (0)")

    # 2. Script (10 pts)
    if result.get('script_modified', False) and result.get('script_has_calib_func', False):
        score += 10
        feedback_parts.append("Script modified with proper functions (+10)")
    elif result.get('script_modified', False):
        score += 5
        feedback_parts.append("Script modified but missing Calibration_Michel (+5)")
    else:
        feedback_parts.append("Script not modified (0)")

    # 3. Metrics CSV Existence (15 pts)
    if result.get('metrics_csv_exists', False) and result.get('metrics_created_during_task', False):
        score += 15
        feedback_parts.append("Metrics CSV created (+15)")
    else:
        feedback_parts.append("Metrics CSV missing or old (0)")

    # 4. Calibration Performance (25 pts)
    calib_nse = result.get('calibration_nse', 0.0)
    if calib_nse >= min_calib:
        score += 25
        feedback_parts.append(f"Calibration NSE {calib_nse:.3f} >= {min_calib} (+25)")
    elif calib_nse > 0:
        score += 10
        feedback_parts.append(f"Calibration NSE {calib_nse:.3f} too low (expected > {min_calib}) (+10)")
    else:
        feedback_parts.append("No valid Calibration NSE (0)")

    # 5. Validation Performance (25 pts)
    valid_nse = result.get('validation_nse', 0.0)
    if valid_nse >= min_valid:
        score += 25
        feedback_parts.append(f"Validation NSE {valid_nse:.3f} >= {min_valid} (+25)")
    elif valid_nse > 0:
        score += 10
        feedback_parts.append(f"Validation NSE {valid_nse:.3f} too low (expected > {min_valid}) (+10)")
    else:
        feedback_parts.append("No valid Validation NSE (0)")

    # 6. Hydrograph Plot (15 pts)
    if result.get('plot_exists', False) and result.get('plot_created_during_task', False):
        size = result.get('plot_size_bytes', 0)
        if size > 30000:  # >30KB implies real content
            score += 15
            feedback_parts.append("Hydrograph plot created (+15)")
        else:
            score += 5
            feedback_parts.append(f"Hydrograph plot too small ({size} bytes) (+5)")
    else:
        feedback_parts.append("Hydrograph plot missing (0)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }