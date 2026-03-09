#!/usr/bin/env python3
"""
Verifier for parabola_focus_directrix_construction task.

Scoring (100 points total):
  - File created during task:        20 pts
  - Focus point near (0, 1):         20 pts
  - Directrix line at y = -1:        20 pts
  - Locus command present:           20 pts
  - Text/distance annotation:        20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_parabola_focus_directrix_construction(traj, env_info, task_info):
    """Verify the parabola focus-directrix construction task."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('tolerance', 0.15)

    # Copy result JSON from VM
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
            feedback_parts.append("File not found — save as parabola_locus.ggb in ~/Documents/GeoGebra/projects/ (0/20)")
        else:
            feedback_parts.append("File exists but was not created during this task session (0/20)")

    # Criterion 2: Focus point near (0, 1) (20 pts)
    has_focus = result.get('has_focus_point', False)
    if has_focus:
        score += 20
        subscores["has_focus"] = True
        feedback_parts.append("Focus point at (0, 1) found (+20)")
    else:
        subscores["has_focus"] = False
        coords = result.get('focus_point_coords', [])
        if coords:
            closest = min(coords, key=lambda p: (p['x']**2 + (p['y']-1.0)**2)**0.5)
            feedback_parts.append(
                f"Focus point not found near (0,1); closest point at ({closest['x']:.2f}, {closest['y']:.2f}) (0/20)"
            )
        else:
            feedback_parts.append("No points found in construction (0/20)")

    # Criterion 3: Directrix line at y = -1 (20 pts)
    has_directrix = result.get('has_directrix_line', False)
    if has_directrix:
        score += 20
        subscores["has_directrix"] = True
        feedback_parts.append("Directrix line y = -1 found (+20)")
    else:
        subscores["has_directrix"] = False
        dy = result.get('directrix_line_y')
        if dy is not None:
            feedback_parts.append(f"Horizontal line found but at y = {dy:.3f}, not y = -1 (0/20)")
        else:
            feedback_parts.append("No horizontal line at y = -1 found (0/20)")

    # Criterion 4: Locus command present (20 pts)
    has_locus = result.get('has_locus_command', False)
    if has_locus:
        score += 20
        subscores["has_locus"] = True
        feedback_parts.append(f"Locus command found ({result.get('locus_count', 1)} locus objects) (+20)")
    else:
        subscores["has_locus"] = False
        commands = result.get('xml_commands', [])
        if commands:
            feedback_parts.append(
                f"Locus command not found; existing commands: {', '.join(sorted(commands)[:8])} (0/20)"
            )
        else:
            feedback_parts.append("No Locus command found in construction (0/20)")

    # Criterion 5: Text or distance annotation present (20 pts)
    has_annotation = result.get('has_annotation', False)
    if has_annotation:
        score += 20
        subscores["has_annotation"] = True
        feedback_parts.append("Annotation/measurement found (+20)")
    else:
        subscores["has_annotation"] = False
        feedback_parts.append("No text or distance annotation found (0/20)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
