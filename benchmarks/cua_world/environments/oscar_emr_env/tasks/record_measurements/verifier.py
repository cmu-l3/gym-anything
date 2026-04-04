#!/usr/bin/env python3
"""
Verifier for Record Clinical Measurements task.
Checks that measurements were correctly recorded in the OSCAR database.
"""

import json
import logging
import os
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_measurements(traj, env_info, task_info):
    """
    Verify that the 4 measurements were recorded correctly.
    
    Expected behavior:
    - Agent logs in and finds patient (implied by success of recording).
    - 4 measurements (A1C, WAIS, GLUC, BMI) are added.
    - Values match expectations within tolerance.
    - Records were created AFTER task start time (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expectations from metadata
    metadata = task_info.get('metadata', {})
    expected_measurements = metadata.get('measurements', [])
    
    # Defaults if metadata missing
    if not expected_measurements:
        expected_measurements = [
            {"type": "A1C", "name": "HbA1c", "value": 7.2, "tolerance": 0.1},
            {"type": "WAIS", "name": "Waist Circumference", "value": 88.0, "tolerance": 1.0},
            {"type": "GLUC", "name": "Blood Glucose", "value": 8.4, "tolerance": 0.2},
            {"type": "BMI", "name": "BMI", "value": 27.3, "tolerance": 0.3}
        ]

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback = []
    
    # 1. Login & Setup check (20 points)
    # If we have any new measurements or app is running, give partial points
    measurements_found = result.get('measurements', [])
    new_measurements = [m for m in measurements_found if m.get('is_new', False)]
    
    if result.get('app_running', False):
        score += 5
        feedback.append("Application is running (+5)")
    else:
        feedback.append("Application was closed")

    if result.get('current_count', 0) > result.get('initial_count', 0):
        score += 15
        feedback.append("New measurement records detected (+15)")
    else:
        feedback.append("No new measurements found")

    # 2. Check each measurement (20 points each = 80 total)
    # Strategy: Look for a matching NEW measurement for each expected type
    
    for expected in expected_measurements:
        m_type = expected['type']
        target_val = expected['value']
        tol = expected['tolerance']
        
        # Find best match among new measurements
        found = False
        best_val = None
        
        for m in new_measurements:
            if m['type'] == m_type:
                try:
                    val = float(m['value'])
                    best_val = val
                    if abs(val - target_val) <= tol:
                        found = True
                        break
                except ValueError:
                    continue
        
        if found:
            score += 20
            feedback.append(f"PASS: {expected['name']} ({m_type}) = {best_val} (Target {target_val}) (+20)")
        elif best_val is not None:
            # Found correct type but wrong value - partial credit
            score += 5
            feedback.append(f"FAIL: {expected['name']} ({m_type}) = {best_val} (Expected {target_val} ± {tol}) (+5)")
        else:
            feedback.append(f"FAIL: {expected['name']} ({m_type}) not found")

    passed = (score >= 60) and (len(new_measurements) >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "new_measurement_count": len(new_measurements),
            "expected_count": len(expected_measurements)
        }
    }