#!/usr/bin/env python3
"""
Verifier for 3d_solid_revolution_visualization task.

Scoring (100 points total):
  - File created during task:              20 pts
  - 3D view used:                          20 pts
  - sqrt(x) function present:              20 pts
  - Surface command (solid of revolution): 20 pts
  - Slider + volume text annotation:       20 pts

Pass threshold: 70 points

GATE: If no 3D view used AND no Surface command, cap at 59 pts.
      (prevents 2D-only submissions from passing)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_3d_solid_revolution_visualization(traj, env_info, task_info):
    """Verify the 3D solid of revolution visualization task."""
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
            feedback_parts.append("File 'solid_revolution.ggb' not found (0/20)")
        else:
            feedback_parts.append("File exists but predates task session (0/20)")

    # Criterion 2: 3D view used (20 pts)
    has_3d = result.get('has_3d_view', False)
    num_3d = result.get('num_3d_elements', 0)
    if has_3d:
        score += 20
        subscores["has_3d"] = True
        feedback_parts.append(f"3D Graphics view used ({num_3d} 3D elements) (+20)")
    else:
        subscores["has_3d"] = False
        feedback_parts.append(
            "No 3D view detected; switch to 3D Graphics (View > 3D Graphics) and use "
            "parametric Surface command (0/20)"
        )

    # Criterion 3: sqrt(x) function (20 pts)
    has_sqrt = result.get('has_sqrt_function', False)
    if has_sqrt:
        score += 20
        subscores["has_sqrt"] = True
        feedback_parts.append("sqrt(x) function found in construction (+20)")
    else:
        subscores["has_sqrt"] = False
        feedback_parts.append(
            "sqrt(x) not found; enter 'f(x) = sqrt(x)' or use it in Surface() command (0/20)"
        )

    # Criterion 4: Surface command for solid of revolution (20 pts)
    has_surface = result.get('has_surface_command', False)
    if has_surface:
        score += 20
        subscores["has_surface"] = True
        surf_expr = result.get('surface_expression', '')
        feedback_parts.append(
            f"Surface/revolution command found{': ' + surf_expr if surf_expr else ''} (+20)"
        )
    else:
        subscores["has_surface"] = False
        commands = result.get('xml_commands', [])
        feedback_parts.append(
            f"Surface command not found; use Surface(sqrt(u)*cos(v), u, sqrt(u)*sin(v), u, 0, 4, v, 0, 2*pi) "
            f"(0/20). Commands seen: {', '.join(sorted(commands)[:8])}"
        )

    # GATE: 3D + Surface required; cap if neither is present
    if not has_3d and not has_surface and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(
            f"Score capped at {PASS_THRESHOLD-1}: 3D view and Surface command are required"
        )

    # Criterion 5: Slider + volume annotation (20 pts)
    has_slider = result.get('has_slider', False)
    has_text = result.get('has_volume_text', False)
    has_circle = result.get('has_circle_cross_section', False)
    if has_slider and has_text:
        score += 20
        subscores["slider_annotation"] = True
        feedback_parts.append("Slider for cross-section position and volume annotation found (+20)")
    elif has_slider or has_text or has_circle:
        score += 10
        subscores["slider_annotation"] = "partial"
        parts = []
        if has_slider:
            parts.append("slider")
        if has_text:
            parts.append("text annotation")
        if has_circle:
            parts.append("circle cross-section")
        feedback_parts.append(f"Partial: {', '.join(parts)} found (+10)")
    else:
        subscores["slider_annotation"] = False
        feedback_parts.append(
            "No slider or volume annotation found; add slider 'a' ∈ [0,4] and "
            "text showing V = π·a²/2 (0/20)"
        )

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
