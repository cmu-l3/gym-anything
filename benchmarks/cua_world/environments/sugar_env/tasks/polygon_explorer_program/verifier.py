#!/usr/bin/env python3
"""Verifier for polygon_explorer_program task.

Checks that the agent created a TurtleBlocks program that draws a square
(repeat 4, forward 100, right 90) and equilateral triangle
(repeat 3, forward 100, right 120), saved as polygon_explorer.ta.
"""

import json
import os
import tempfile


def verify_polygon_explorer_program(traj, env_info, task_info):
    """Verify TurtleBlocks polygon program was created correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/polygon_explorer_program_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: File exists and was modified after task start (15 pts)
    if result.get('file_exists'):
        if result.get('file_modified'):
            score += 15
            feedback.append("polygon_explorer.ta saved")
        else:
            score += 5
            feedback.append("File exists but may be pre-existing (mtime check failed)")
    else:
        feedback.append("FAIL: polygon_explorer.ta not found in /home/ga/Documents/")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: File has valid content (5 pts)
    if result.get('file_size', 0) > 50:
        score += 5
        feedback.append(f"File has content ({result['file_size']} bytes)")
    else:
        feedback.append(f"File too small ({result.get('file_size', 0)} bytes)")

    # Criterion 3: Has start block (5 pts)
    if result.get('has_start'):
        score += 5
        feedback.append("start block present")
    else:
        feedback.append("Missing start block")

    # Criterion 4: Has repeat block (10 pts)
    if result.get('has_repeat'):
        score += 10
        feedback.append("repeat block present")
    else:
        feedback.append("Missing repeat block")

    # Criterion 5: Has forward block (10 pts)
    if result.get('has_forward'):
        score += 10
        feedback.append("forward block present")
    else:
        feedback.append("Missing forward block")

    # Criterion 6: Square — repeat 4 times (15 pts)
    if result.get('has_repeat_4'):
        score += 15
        feedback.append("repeat(4) for square found")
    else:
        feedback.append("Missing repeat(4) for square")

    # Criterion 7: Square — right 90 degrees (15 pts)
    if result.get('has_right_90'):
        score += 15
        feedback.append("right(90) for square corners found")
    else:
        feedback.append("Missing right(90) for square corners")

    # Criterion 8: Triangle — repeat 3 times (15 pts)
    if result.get('has_repeat_3'):
        score += 15
        feedback.append("repeat(3) for triangle found")
    else:
        feedback.append("Missing repeat(3) for triangle")

    # Criterion 9: Triangle — right 120 degrees (15 pts)
    if result.get('has_right_120'):
        score += 15
        feedback.append("right(120) for triangle corners found")
    else:
        feedback.append("Missing right(120) for triangle corners")

    # Pass: score >= 70 AND both shapes structurally present
    has_square = result.get('has_repeat_4') and result.get('has_right_90')
    has_triangle = result.get('has_repeat_3') and result.get('has_right_120')
    passed = score >= 70 and has_square and has_triangle

    if passed:
        feedback.append("Both polygon shapes correctly programmed!")
    else:
        missing = []
        if not has_square:
            missing.append("square (repeat 4, right 90)")
        if not has_triangle:
            missing.append("triangle (repeat 3, right 120)")
        if missing:
            feedback.append(f"FAILED: missing shapes: {', '.join(missing)}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "file_exists": result.get('file_exists', False),
            "has_square": has_square,
            "has_triangle": has_triangle,
            "block_count": result.get('block_count', 0)
        }
    }
