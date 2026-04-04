#!/usr/bin/env python3
"""
Verifier for Mohr's Circle Stress Analysis Task.
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mohrs_circle_stress_analysis(traj, env_info, task_info):
    """
    Verifies the Mohr's Circle construction.
    
    Criteria:
    1. File creation/modification during task.
    2. Sliders for Stress Components (sig_x, sig_y, tau).
    3. Construction Logic (Circle exists).
    4. Calibration State (Agent set sliders to 80, -40, 25).
    5. Resulting Principal Stresses (Circle intersects x-axis at 85 and -45).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_p1 = metadata.get('expected_p1', 85.0)
    expected_p2 = metadata.get('expected_p2', -45.0)
    tolerance = metadata.get('tolerance', 0.5)

    # Load result
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

    # 1. File Check (10 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback.append("File created successfully.")
    else:
        feedback.append("File not found or not created during task.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Sliders Check (20 pts)
    sliders = result.get('sliders_found', [])
    # Look for variable names roughly matching sigma/tau
    sig_vars = [s for s in sliders if 'sig' in s.lower() or 'x' in s.lower() or 'y' in s.lower()]
    tau_vars = [s for s in sliders if 'tau' in s.lower() or 't' in s.lower()]
    
    if len(sliders) >= 3:
        score += 20
        feedback.append(f"Sliders found: {sliders}")
    elif len(sliders) > 0:
        score += 10
        feedback.append(f"Some sliders found: {sliders}")
    else:
        feedback.append("No sliders found.")

    # 3. Circle Construction (20 pts)
    if result.get('circle_found'):
        score += 20
        feedback.append("Circle construction found.")
    else:
        feedback.append("No circle found in construction.")

    # 4. Calibration Check (20 pts)
    # Check if sliders are set to target values (80, -40, 25)
    # We allow loose matching on variable names, checking values mostly
    cal_values = result.get('calibration_values', {}).values()
    
    # We look for the presence of the specific target numbers in the slider values
    has_80 = any(abs(v - 80) < 1.0 for v in cal_values)
    has_neg40 = any(abs(v - (-40)) < 1.0 for v in cal_values)
    has_25 = any(abs(v - 25) < 1.0 for v in cal_values)

    if has_80 and has_neg40 and has_25:
        score += 20
        feedback.append("Sliders calibrated correctly to (80, -40, 25).")
    else:
        feedback.append(f"Sliders NOT calibrated to target values. Found: {list(cal_values)}")

    # 5. Principal Stresses (30 pts)
    # Check if we have points on the x-axis matching 85 and -45
    stresses = result.get('principal_stresses', [])
    
    found_p1 = any(abs(s - expected_p1) < tolerance for s in stresses)
    found_p2 = any(abs(s - expected_p2) < tolerance for s in stresses)

    if found_p1 and found_p2:
        score += 30
        feedback.append(f"Principal stresses found at {expected_p1} and {expected_p2}.")
    elif found_p1 or found_p2:
        score += 15
        feedback.append(f"One principal stress found (Values on axis: {stresses}).")
    else:
        feedback.append(f"Principal stresses not identified on x-axis (Values on axis: {stresses}).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }