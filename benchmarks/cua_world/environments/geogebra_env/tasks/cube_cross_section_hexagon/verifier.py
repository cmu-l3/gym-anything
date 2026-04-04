#!/usr/bin/env python3
"""
Verifier for cube_cross_section_hexagon task.

Scoring (100 points total):
  - File created during task:       15 pts
  - 3D view enabled:                15 pts
  - Cube present:                   20 pts
  - Plane present:                  15 pts
  - Intersection/Hexagon present:   20 pts
  - Area calculation correct:       15 pts

Pass threshold: 70 points
Gate: Must have Cube and 3D View to pass > 50 pts.
"""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_cube_cross_section_hexagon(traj, env_info, task_info):
    """Verify the cube hexagonal cross-section task."""
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
    
    metadata = task_info.get('metadata', {})
    expected_area = metadata.get('expected_area', 5.196)
    area_tolerance = metadata.get('area_tolerance', 0.1)

    # Criterion 1: File created during task (15 pts)
    file_ok = result.get('file_found', False) and result.get('file_created_during_task', False)
    if file_ok:
        score += 15
        subscores["file_created"] = True
        feedback_parts.append("File created during task (+15)")
    else:
        subscores["file_created"] = False
        feedback_parts.append("File not found or old (0/15)")

    # Criterion 2: 3D View enabled (15 pts)
    # The construction MUST be 3D.
    has_3d = result.get('has_3d_view', False)
    if has_3d:
        score += 15
        subscores["has_3d"] = True
        feedback_parts.append("3D View enabled (+15)")
    else:
        subscores["has_3d"] = False
        feedback_parts.append("3D View NOT enabled (0/15)")

    # Criterion 3: Cube present (20 pts)
    has_cube = result.get('has_cube', False)
    if has_cube:
        score += 20
        subscores["has_cube"] = True
        feedback_parts.append("Cube found (+20)")
    else:
        subscores["has_cube"] = False
        feedback_parts.append("Cube construction not found (use Cube command or polyhedron tool) (0/20)")

    # Criterion 4: Plane present (15 pts)
    has_plane = result.get('has_plane', False)
    if has_plane:
        score += 15
        subscores["has_plane"] = True
        feedback_parts.append("Cutting plane found (+15)")
    else:
        subscores["has_plane"] = False
        feedback_parts.append("No cutting plane found (0/15)")

    # Criterion 5: Intersection present (20 pts)
    has_intersect = result.get('has_intersection', False)
    if has_intersect:
        score += 20
        subscores["has_intersect"] = True
        feedback_parts.append("Intersection polygon created (+20)")
    else:
        subscores["has_intersect"] = False
        feedback_parts.append("No Intersection/Cross-section found (use IntersectPath or similar) (0/20)")

    # Criterion 6: Area Calculation (15 pts)
    val = result.get('area_value', 0.0)
    if abs(val - expected_area) <= area_tolerance:
        score += 15
        subscores["area_correct"] = True
        feedback_parts.append(f"Area value {val:.3f} correct (+15)")
    else:
        subscores["area_correct"] = False
        if val > 0:
            feedback_parts.append(f"Area value {val:.3f} incorrect (expected ~{expected_area}) (0/15)")
        else:
            feedback_parts.append("Area text/value not found (0/15)")

    # Gate: Prevent 2D submissions or empty files from passing
    # Must have 3D view and Cube to exceed 50 points
    if (not has_3d or not has_cube) and score > 50:
        score = 50
        feedback_parts.append("Score capped at 50: 3D Cube construction required")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }