#!/usr/bin/env python3
"""
Verifier for linear_transform_eigenvector_viz task.

Scoring (100 points total):
  - File created during task:       15 pts
  - Unit square polygon present:    15 pts
  - ApplyMatrix command used:       20 pts
  - Transformed polygon geometry:   10 pts
  - Eigenvector (1,1) displayed:    15 pts
  - Eigenvector (1,-1) displayed:   15 pts
  - Text annotation present:        10 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_linear_transform_eigenvector_viz(traj, env_info, task_info):
    """Verify the linear transformation eigenvector visualization task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Retrieve result JSON
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
            feedback_parts.append("File not found (0/15)")
        else:
            feedback_parts.append("File exists but was not created during this session (0/15)")

    # Criterion 2: Unit square present (15 pts)
    if result.get('has_unit_square', False):
        score += 15
        subscores["unit_square"] = True
        feedback_parts.append("Unit square found (+15)")
    else:
        subscores["unit_square"] = False
        feedback_parts.append("Unit square vertices (0,0),(1,0),(0,1),(1,1) not found (0/15)")

    # Criterion 3: ApplyMatrix command (20 pts)
    if result.get('has_apply_matrix', False):
        score += 20
        subscores["apply_matrix"] = True
        feedback_parts.append("ApplyMatrix command found (+20)")
    else:
        subscores["apply_matrix"] = False
        feedback_parts.append("ApplyMatrix command not found; must use ApplyMatrix({{2,1},{1,2}}, object) (0/20)")

    # Criterion 4: Transformed geometry (10 pts)
    if result.get('has_transformed_poly', False):
        score += 10
        subscores["transformed_poly"] = True
        feedback_parts.append("Transformed parallelogram geometry correct (+10)")
    else:
        subscores["transformed_poly"] = False
        feedback_parts.append("Transformed vertices (2,1),(1,2),(3,3) not found (0/10)")

    # Criterion 5: Eigenvector 1 (15 pts)
    if result.get('has_eigenvector_1', False):
        score += 15
        subscores["eigenvector_1"] = True
        feedback_parts.append("Eigenvector (1,1) found (+15)")
    else:
        subscores["eigenvector_1"] = False
        feedback_parts.append("Eigenvector in direction (1,1) not found (0/15)")

    # Criterion 6: Eigenvector 2 (15 pts)
    if result.get('has_eigenvector_2', False):
        score += 15
        subscores["eigenvector_2"] = True
        feedback_parts.append("Eigenvector (1,-1) found (+15)")
    else:
        subscores["eigenvector_2"] = False
        feedback_parts.append("Eigenvector in direction (1,-1) not found (0/15)")

    # Criterion 7: Text annotation (10 pts)
    if result.get('has_text', False):
        score += 10
        subscores["text"] = True
        feedback_parts.append("Text annotation found (+10)")
    else:
        subscores["text"] = False
        feedback_parts.append("No text annotation found (0/10)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }