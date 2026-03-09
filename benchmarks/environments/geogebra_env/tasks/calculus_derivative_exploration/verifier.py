#!/usr/bin/env python3
"""
Verifier for calculus_derivative_exploration task.

Scoring (100 points total):
  - File created during task:               20 pts
  - Cubic function f(x) = x³-3x+1 present: 20 pts
  - Derivative command/function present:    20 pts
  - Tangent line on moveable point:         20 pts
  - Critical points identified:             20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_calculus_derivative_exploration(traj, env_info, task_info):
    """Verify the calculus derivative exploration task."""
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

    # Criterion 1: File created during task (20 pts)
    file_ok = result.get('file_found', False) and result.get('file_created_during_task', False)
    if file_ok:
        score += 20
        subscores["file_created"] = True
        feedback_parts.append("File created during task (+20)")
    else:
        subscores["file_created"] = False
        if not result.get('file_found', False):
            feedback_parts.append("File 'derivative_explorer.ggb' not found (0/20)")
        else:
            feedback_parts.append("File exists but predates task session (0/20)")

    # Criterion 2: Cubic function present (20 pts)
    has_cubic = result.get('has_cubic_function', False)
    num_funcs = result.get('num_functions', 0)
    if has_cubic and num_funcs >= 1:
        score += 20
        subscores["has_cubic"] = True
        expr = result.get('function_expression', '')
        feedback_parts.append(f"Cubic function found{' (expr: '+expr+')' if expr else ''} (+20)")
    elif num_funcs >= 1 and not has_cubic:
        # Partial credit: has some function, just not clearly cubic
        score += 10
        subscores["has_cubic"] = "partial"
        feedback_parts.append(f"Function found but x^3 pattern not detected ({num_funcs} functions); expected f(x)=x^3-3x+1 (+10)")
    else:
        subscores["has_cubic"] = False
        feedback_parts.append(f"No function found; enter f(x) = x^3 - 3x + 1 in input bar (0/20)")

    # Criterion 3: Derivative present (20 pts)
    has_deriv = result.get('has_derivative', False)
    if has_deriv:
        score += 20
        subscores["has_derivative"] = True
        feedback_parts.append("Derivative command/function found (+20)")
    else:
        subscores["has_derivative"] = False
        commands = result.get('xml_commands', [])
        feedback_parts.append(
            f"Derivative not found; use Derivative(f) in input bar (0/20). "
            f"Commands seen: {', '.join(sorted(commands)[:8])}"
        )

    # Criterion 4: Tangent line present (20 pts)
    has_tangent = result.get('has_tangent', False)
    has_slider = result.get('has_slider_or_draggable', False)
    if has_tangent:
        score += 20
        subscores["has_tangent"] = True
        feedback_parts.append("Tangent line on moveable point found (+20)")
    elif has_slider and not has_tangent:
        # Partial: has slider but no tangent
        score += 10
        subscores["has_tangent"] = "partial"
        feedback_parts.append("Slider present but no Tangent command found; use Tangent(point, f) (+10)")
    else:
        subscores["has_tangent"] = False
        feedback_parts.append("No tangent line found; use Tangent(A, f) where A is a point on f (0/20)")

    # Criterion 5: Critical points identified (20 pts)
    has_critical = result.get('has_critical_points', False)
    critical_coords = result.get('critical_point_coords', [])
    if has_critical:
        score += 20
        subscores["has_critical"] = True
        if critical_coords:
            feedback_parts.append(
                f"Critical points found near x=±1: {critical_coords[:3]} (+20)"
            )
        else:
            feedback_parts.append("Critical points found via Extremum/Root command (+20)")
    else:
        subscores["has_critical"] = False
        feedback_parts.append(
            "Critical points not identified; use Extremum(f, -2, 0) and Extremum(f, 0, 2) "
            "or Root(f', -2, 2) (0/20)"
        )

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
