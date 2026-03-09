#!/usr/bin/env python3
"""
Verifier for Lissajous Figure Interactive Explorer task.

Scoring Breakdown (100 points total):
1. File created during task: 15 pts
   - Checks modification timestamp against task start time.
2. Valid GeoGebra Archive: 5 pts
   - Checks if file is a valid ZIP with geogebra.xml.
3. Parametric Curve Command: 25 pts
   - Essential for task. Checks for Curve() command or curveCartesian element.
4. Sin functions used: 10 pts
   - Ensures correct mathematical definition x=sin(...), y=sin(...).
5. Sliders present: 20 pts
   - At least 2 sliders required (for a and b).
6. Bonus Sliders: 5 pts
   - 3 or more sliders (for phase shift).
7. Text Annotation: 15 pts
   - Checks for text element.
8. Dynamic Linkage: 5 pts
   - Checks if curve definition references variables.

Pass Threshold: 60 points AND Curve command must be present.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lissajous_figure_explorer(traj, env_info, task_info):
    """
    Verify the Lissajous task using the JSON result exported from the container.
    """
    # 1. Setup: Retrieve result file using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Critical Error: copy_from_env function not available."
        }

    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. Score Calculation
    score = 0
    feedback_log = []
    
    # Criterion 1: File created during task (15 pts)
    # Anti-gaming: Prevents using a pre-made file
    if result.get("file_found", False) and result.get("file_created_during_task", False):
        score += 15
        feedback_log.append("PASS: New GeoGebra file created (+15)")
    elif result.get("file_found", False):
        feedback_log.append("FAIL: File exists but was created before task started (0/15)")
    else:
        feedback_log.append("FAIL: No result file found (0/15)")

    # Criterion 2: Valid Archive (5 pts)
    if result.get("file_found", False) and result.get("file_size", 0) > 0:
        score += 5
        feedback_log.append("PASS: Valid file format (+5)")
    else:
        feedback_log.append("FAIL: Invalid or empty file (0/5)")

    # Criterion 3: Curve Command (25 pts) - CRITICAL
    has_curve = result.get("has_curve_command", False)
    if has_curve:
        score += 25
        feedback_log.append("PASS: Parametric Curve command found (+25)")
    else:
        feedback_log.append("FAIL: No Parametric Curve found. Use Curve(x, y, t, start, end) (0/25)")

    # Criterion 4: Sin functions (10 pts)
    if result.get("has_sin", False):
        score += 10
        feedback_log.append("PASS: Sinusoidal functions detected (+10)")
    else:
        feedback_log.append("FAIL: No sin() functions detected in construction (0/10)")

    # Criterion 5 & 6: Sliders (20 pts + 5 bonus)
    slider_count = result.get("slider_count", 0)
    if slider_count >= 2:
        score += 20
        feedback_log.append(f"PASS: {slider_count} sliders found (>=2) (+20)")
        if slider_count >= 3:
            score += 5
            feedback_log.append("PASS: Bonus for 3rd slider (phase shift) (+5)")
    else:
        feedback_log.append(f"FAIL: Only {slider_count} sliders found. Need at least 2 for frequencies a and b (0/20)")

    # Criterion 7: Text Annotation (15 pts)
    if result.get("has_text", False):
        score += 15
        feedback_log.append("PASS: Text annotation present (+15)")
    else:
        feedback_log.append("FAIL: No text annotation found (0/15)")

    # Criterion 8: Dynamic Linkage (5 pts)
    # Heuristic check if variables are used in curve
    # Note: result["curve_uses_variables"] might be None/False if parsing failed
    if has_curve and result.get("curve_uses_variables", False):
        score += 5
        feedback_log.append("PASS: Curve appears to use variables/sliders (+5)")
    elif has_curve:
        feedback_log.append("WARN: Curve might use hardcoded values instead of sliders (0/5)")

    # 3. Final Evaluation
    # Pass requires >= 60 points AND the Curve command must be present
    passed = (score >= 60) and has_curve
    
    final_feedback = f"Final Score: {score}/100. " + " | ".join(feedback_log)
    if not has_curve:
        final_feedback += " | CRITICAL FAIL: The required Curve command is missing."

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }