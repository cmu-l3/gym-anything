#!/usr/bin/env python3
"""
Verifier for Gateway Arch Catenary vs Parabola task.

Scoring (100 points total):
  - File created during task:      15 pts
  - Catenary (cosh) present:       25 pts
  - Parabola (x^2) present:        25 pts
  - Two distinct functions:        15 pts
  - Text annotation present:       20 pts

Pass threshold: 70 points.
CRITICAL GATE: Both cosh and x^2 must be present to pass.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_gateway_arch_catenary_parabola(traj, env_info, task_info):
    """Verify the Gateway Arch comparison task."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except OSError:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: File created during task (15 pts)
    file_ok = result.get('file_found', False) and result.get('file_created_during_task', False)
    if file_ok:
        score += 15
        subscores["file_created"] = True
        feedback_parts.append("File created during task (+15)")
    else:
        subscores["file_created"] = False
        if not result.get('file_found', False):
            feedback_parts.append("File 'gateway_arch_comparison.ggb' not found (0/15)")
        else:
            feedback_parts.append("File exists but was not created during this task session (0/15)")

    # Criterion 2: Catenary function (25 pts)
    has_cosh = result.get('has_cosh', False)
    if has_cosh:
        score += 25
        subscores["has_cosh"] = True
        feedback_parts.append("Catenary (cosh) function found (+25)")
    else:
        subscores["has_cosh"] = False
        feedback_parts.append("Catenary function (cosh) NOT found (0/25)")

    # Criterion 3: Parabola function (25 pts)
    has_parabola = result.get('has_parabola', False)
    if has_parabola:
        score += 25
        subscores["has_parabola"] = True
        feedback_parts.append("Parabola (x²) function found (+25)")
    else:
        subscores["has_parabola"] = False
        feedback_parts.append("Parabola function (x²) NOT found (0/25)")

    # Criterion 4: Two distinct functions (15 pts)
    num_funcs = result.get('num_functions', 0)
    if num_funcs >= 2:
        score += 15
        subscores["num_functions"] = True
        feedback_parts.append(f"At least two functions present ({num_funcs} found) (+15)")
    else:
        subscores["num_functions"] = False
        feedback_parts.append(f"Expected 2 functions, found {num_funcs} (0/15)")

    # Criterion 5: Text annotation (20 pts)
    has_text = result.get('has_text', False)
    if has_text:
        score += 20
        subscores["has_text"] = True
        feedback_parts.append("Text annotation found (+20)")
    else:
        subscores["has_text"] = False
        feedback_parts.append("No text annotation found (0/20)")

    # GATE: Check strict requirements for passing
    passed = score >= PASS_THRESHOLD
    
    # Specific fail condition: If either model is missing, it shouldn't pass even if other points add up
    # (e.g., file(15) + text(20) + cosh(25) = 60 < 70, so math works out naturally here)
    if not (has_cosh and has_parabola):
        passed = False
        if score >= PASS_THRESHOLD:
             # This block logically unreachable given points distribution, but good as safeguard
             feedback_parts.append("FAIL: Both models (cosh and x²) are required to pass")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }