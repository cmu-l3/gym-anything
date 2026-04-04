#!/usr/bin/env python3
"""
Verifier for ground_floor_custom_dx_curve task.

Task: Create Quadratic Curve 'HighEff_DX_PLR' (0.085, 0.250, 0.665) and assign to 5 Ground Floor systems.

Scoring:
- Simulation Ran (10 pts)
- Curve Created Correctly (30 pts)
- Systems Updated (12 pts each x 5 = 60 pts)
Wait, total 100.
Correction:
- Sim Ran: 10
- Curve Creation: 30
- Systems: 12 * 5 = 60
Total = 100.

Pass Threshold: 60 pts.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
TARGET_COEFFS = [0.085, 0.250, 0.665]
TOLERANCE = 0.002
TARGET_SYSTEMS = ["G.S1", "G.E2", "G.N3", "G.W4", "G.C5"]

def verify_ground_floor_custom_dx_curve(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from Windows path mapped to temp file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path inside the Windows container
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Simulation (10 pts)
    if result.get('sim_ran', False):
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
    else:
        feedback_parts.append("Simulation did not run during task")

    # 2. Verify Curve Creation (30 pts)
    curve_data = result.get('curve_data', {})
    if not curve_data.get('exists', False):
        feedback_parts.append("Curve 'HighEff_DX_PLR' not found")
    else:
        # Check Type
        if not curve_data.get('type_correct', False):
            feedback_parts.append("Curve type incorrect (expected QUADRATIC)")
        else:
            # Check Coefficients
            found_coeffs = curve_data.get('found_coeffs', [])
            if not found_coeffs or len(found_coeffs) != 3:
                feedback_parts.append("Coefficients missing or incorrect length")
            else:
                # Compare values
                match = True
                for t, f in zip(TARGET_COEFFS, found_coeffs):
                    if abs(t - f) > TOLERANCE:
                        match = False
                        break
                
                if match:
                    score += 30
                    feedback_parts.append("Curve created correctly (+30)")
                else:
                    feedback_parts.append(f"Coefficients incorrect. Expected {TARGET_COEFFS}, got {found_coeffs}")

    # 3. Verify Systems (12 pts each)
    systems = result.get('systems', {})
    systems_correct = 0
    
    for sys_tag in TARGET_SYSTEMS:
        status = systems.get(sys_tag)
        if status is True:
            score += 12
            systems_correct += 1
        elif status == "Not Found":
            # Don't clutter feedback if all missing, will summarize
            pass
        else:
            # Found but wrong assignment
            pass

    feedback_parts.append(f"{systems_correct}/5 systems updated correctly (+{systems_correct * 12})")

    # Final logic
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }