#!/usr/bin/env python3
import json
import os
import logging
import math
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lorenz_gini(traj, env_info, task_info):
    """
    Verifies the Lorenz Curve and Gini Coefficient task.
    """
    # 1. Setup & Data Extraction
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define metadata expectations
    metadata = task_info.get('metadata', {})
    expected_points = metadata.get('points', [])
    tolerance = metadata.get('tolerance', 0.05)
    expected_gini_min = metadata.get('expected_gini_min', 0.43)
    expected_gini_max = metadata.get('expected_gini_max', 0.49)

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # CRITERION 1: File Created (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully (+10)")
    elif result.get("file_found"):
        feedback.append("File found but not modified during task (0/10)")
    else:
        feedback.append("File not found (0/10)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # CRITERION 2: Data Points (25 pts)
    # Check if key cumulative points exist in the construction
    # We specifically look for the intermediate calculated points: (0.2, 0.03), (0.4, 0.111), (0.6, 0.251), (0.8, 0.477)
    found_points = result.get("points_found", [])
    
    points_matched = 0
    required_matches = 4 # We check the 4 intermediate points
    
    # Helper to check distance
    def is_close(p1, target):
        return math.hypot(p1['x'] - target['x'], p1['y'] - target['y']) < tolerance

    # Check for specific Lorenz points
    targets = [
        {'x': 0.2, 'y': 0.030},
        {'x': 0.4, 'y': 0.111},
        {'x': 0.6, 'y': 0.251},
        {'x': 0.8, 'y': 0.477}
    ]
    
    for target in targets:
        if any(is_close(p, target) for p in found_points):
            points_matched += 1

    if points_matched >= 3:
        score += 25
        feedback.append(f"Correct cumulative data points found ({points_matched}/{len(targets)}) (+25)")
    elif points_matched > 0:
        score += 10
        feedback.append(f"Some data points found ({points_matched}/{len(targets)}) (+10)")
    else:
        feedback.append("Cumulative data points not found (0/25)")

    # CRITERION 3: Curve Fitting (20 pts)
    commands = result.get("commands_found", [])
    fit_commands = ["FitPoly", "Spline", "Polynomial", "FitExp", "FitPow", "FitLog"]
    if any(cmd in commands for cmd in fit_commands):
        score += 20
        feedback.append("Curve fitting command used (+20)")
    else:
        feedback.append("No curve fitting command found (e.g., FitPoly) (0/20)")

    # CRITERION 4: Equality Line (10 pts)
    # Look for 'x' or 'y=x' in functions list
    functions = result.get("functions_found", [])
    # Clean up expressions (remove spaces, lowercase)
    clean_funcs = [f.replace(" ", "").lower() for f in functions]
    if "x" in clean_funcs or "y=x" in clean_funcs:
        score += 10
        feedback.append("Equality line (y=x) found (+10)")
    else:
        feedback.append("Equality line (y=x) not found (0/10)")

    # CRITERION 5: Integral/Area Calculation (15 pts)
    integral_commands = ["Integral", "IntegralBetween", "Area"]
    if any(cmd in commands for cmd in integral_commands):
        score += 15
        feedback.append("Integration/Area command used (+15)")
    else:
        feedback.append("No integration command found (0/15)")

    # CRITERION 6: Gini Coefficient Value (20 pts)
    # Look for a numeric value in the expected range
    numerics = result.get("numeric_values", [])
    gini_found = False
    for val in numerics:
        if expected_gini_min <= val <= expected_gini_max:
            gini_found = True
            break
            
    if gini_found:
        score += 20
        feedback.append("Calculated Gini coefficient is within expected range (+20)")
    else:
        feedback.append(f"No numeric value found in Gini range [{expected_gini_min}-{expected_gini_max}] (0/20)")

    # 3. Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }