#!/usr/bin/env python3
"""
Verifier for Circle Inversion Geometry Explorer task.

Scoring (100 points total):
  - File created during task:           15 pts
  - Inversion circle (r=3 at 0,0):      20 pts
  - Reflect command with circle:        25 pts
  - Line element (not through origin):  20 pts
  - Text annotation present:            20 pts

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65

def verify_circle_inversion_explorer(traj, env_info, task_info):
    """Verify the circle inversion construction task."""
    copy_from_env = env_info.get('copy_from_env')
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
            feedback_parts.append("File 'circle_inversion.ggb' not found (0/15)")
        else:
            feedback_parts.append("File exists but predates task session (0/15)")

    # Criterion 2: Inversion circle present (20 pts)
    if result.get('has_circle_radius_3', False):
        score += 20
        subscores["has_circle"] = True
        feedback_parts.append("Inversion circle (r=3) found (+20)")
    else:
        subscores["has_circle"] = False
        feedback_parts.append("Circle with radius 3 centered at origin not found (0/20)")

    # Criterion 3: Reflect command using circle (25 pts)
    if result.get('has_reflect_circle', False):
        score += 25
        subscores["has_reflect"] = True
        feedback_parts.append("Circle inversion (Reflect w/ circle) found (+25)")
    else:
        subscores["has_reflect"] = False
        feedback_parts.append("Circle inversion command not detected (ensure you Reflect an object across the Circle) (0/25)")

    # Criterion 4: Line element present (20 pts)
    if result.get('has_line', False):
        score += 20
        subscores["has_line"] = True
        feedback_parts.append("Line element (not through origin) found (+20)")
    else:
        subscores["has_line"] = False
        feedback_parts.append("Line not passing through origin not found (0/20)")

    # Criterion 5: Text annotation (20 pts)
    if result.get('has_text', False):
        score += 20
        subscores["has_text"] = True
        feedback_parts.append("Text annotation found (+20)")
    else:
        subscores["has_text"] = False
        feedback_parts.append("No text annotation found (0/20)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }