#!/usr/bin/env python3
"""
Verifier for Fourier Square Wave Approximation task.

Scoring Criteria (100 pts total):
1. File created during task (20 pts)
2. Slider 'n' present (20 pts)
3. Sum command used (Fourier series) (20 pts)
4. Square wave function defined (20 pts)
5. Text annotation present (20 pts)

Pass Threshold: 60 pts
GATE: The 'Sum' command must be present to score > 60.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60

def verify_fourier_square_wave_approx(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File existence and timestamp (20 pts)
    file_found = result.get("file_found", False)
    file_fresh = result.get("file_created_during_task", False)
    
    if file_found and file_fresh:
        score += 20
        feedback_parts.append("File created successfully (+20)")
    elif file_found:
        feedback_parts.append("File found but not created during this session (0/20)")
    else:
        feedback_parts.append("File 'fourier_square_wave.ggb' not found (0/20)")

    # 2. Slider Presence (20 pts)
    if result.get("has_slider", False):
        score += 20
        details = result.get("slider_details", {})
        label = details.get("label", "unknown")
        feedback_parts.append(f"Slider '{label}' found (+20)")
    else:
        feedback_parts.append("No slider found (0/20)")

    # 3. Sum Command (20 pts) - The "Fourier" Part
    has_sum = result.get("has_sum_command", False)
    if has_sum:
        score += 20
        feedback_parts.append("Sum command found (+20)")
    else:
        feedback_parts.append("Sum command NOT found - essential for Fourier series (0/20)")

    # 4. Square Wave Function (20 pts)
    if result.get("has_square_wave", False):
        score += 20
        feedback_parts.append("Square wave function (sgn/If) found (+20)")
    else:
        feedback_parts.append("Square wave target function not found (0/20)")

    # 5. Text Annotation (20 pts)
    if result.get("has_text", False):
        score += 20
        feedback_parts.append("Text annotation found (+20)")
    else:
        feedback_parts.append("No text annotation found (0/20)")

    # Gate Check
    if not has_sum and score > 60:
        score = 60
        feedback_parts.append("Score capped at 60: 'Sum' command is required for Fourier approximation.")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }