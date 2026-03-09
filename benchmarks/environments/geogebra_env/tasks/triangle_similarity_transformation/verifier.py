#!/usr/bin/env python3
"""
Verifier for triangle_similarity_transformation task.

Scoring (100 points total):
  - File created during task:                    20 pts
  - Original triangle ABC vertices correct:      20 pts
  - Dilation command used (not manual placement): 20 pts
  - Dilated triangle A'B'C' at correct coords:   20 pts
  - Measurements and text annotation present:    20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_triangle_similarity_transformation(traj, env_info, task_info):
    """Verify the triangle similarity transformation task."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

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
            feedback_parts.append("File 'triangle_similarity.ggb' not found (0/20)")
        else:
            feedback_parts.append("File exists but predates task session (0/20)")

    # Criterion 2: Original triangle ABC vertices correct (20 pts)
    # A=(0,0), B=(4,0), C=(2,3)
    vertices_ok = result.get('original_vertices_correct', False)
    if vertices_ok:
        score += 20
        subscores["vertices_correct"] = True
        feedback_parts.append("Original triangle ABC vertices at (0,0), (4,0), (2,3) found (+20)")
    else:
        subscores["vertices_correct"] = False
        pts = result.get('point_coords', [])
        num_pts = result.get('num_points', 0)
        if num_pts > 0:
            sample = pts[:4] if pts else []
            feedback_parts.append(
                f"Original vertices A(0,0), B(4,0), C(2,3) not all found; "
                f"first {len(sample)} points: {sample} (0/20)"
            )
        else:
            feedback_parts.append("No points found in construction (0/20)")

    # Criterion 3: Dilation command used (20 pts)
    has_dilation = result.get('has_dilation', False)
    if has_dilation:
        score += 20
        subscores["has_dilation"] = True
        feedback_parts.append("Dilation command found (+20)")
    else:
        subscores["has_dilation"] = False
        commands = result.get('xml_commands', [])
        feedback_parts.append(
            f"Dilate command not found; use Dilate(polygon, 1.5, A) in input bar or "
            f"Transform > Dilation tool (0/20). Commands seen: {', '.join(sorted(commands)[:6])}"
        )

    # Criterion 4: Dilated triangle present at correct coordinates (20 pts)
    # A'=(0,0), B'=(6,0), C'=(3,4.5)
    has_dilated = result.get('has_dilated_triangle', False)
    dilated_b = result.get('dilated_B_found', False)
    dilated_c = result.get('dilated_C_found', False)
    if has_dilated:
        score += 20
        subscores["dilated_correct"] = True
        feedback_parts.append("Dilated triangle A'B'C' at (6,0) and (3,4.5) found (+20)")
    elif dilated_b or dilated_c:
        score += 10
        subscores["dilated_correct"] = "partial"
        feedback_parts.append(
            f"Partial: B'(6,0)={'found' if dilated_b else 'missing'}, "
            f"C'(3,4.5)={'found' if dilated_c else 'missing'} (+10)"
        )
    else:
        subscores["dilated_correct"] = False
        num_polys = result.get('num_polygons', 0)
        feedback_parts.append(
            f"Dilated triangle not found at expected coords B'(6,0), C'(3,4.5); "
            f"found {num_polys} polygon(s) (0/20)"
        )

    # Criterion 5: Measurements and annotation (20 pts)
    has_meas = result.get('has_measurements', False)
    has_ann = result.get('has_annotation', False)
    if has_meas and has_ann:
        score += 20
        subscores["measurements_annotation"] = True
        feedback_parts.append("Side length measurements and text annotation found (+20)")
    elif has_meas or has_ann:
        score += 10
        subscores["measurements_annotation"] = "partial"
        parts_found = []
        if has_meas:
            parts_found.append("measurements")
        if has_ann:
            parts_found.append("annotation")
        feedback_parts.append(f"Partial: {', '.join(parts_found)} found (+10)")
    else:
        subscores["measurements_annotation"] = False
        feedback_parts.append("No measurements or text annotation found (0/20)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
