#!/usr/bin/env python3
"""
Verifier for Complex Roots of Unity Pentagon task.

Scoring (100 points total):
  - File created during task:        15 pts
  - Unit circle present:             20 pts
  - Roots of unity plotted (4/5):    25 pts
  - Polygon present:                 20 pts
  - Slider present:                  10 pts
  - Text annotation present:         10 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_complex_roots_of_unity_pentagon(traj, env_info, task_info):
    """Verify the roots of unity construction."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_roots = metadata.get('expected_roots', [])
    tolerance = metadata.get('tolerance', 0.15)

    # 1. Retrieve Result JSON
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
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: File created during task (15 pts)
    if result.get('file_found', False) and result.get('file_created_during_task', False):
        score += 15
        subscores['file_created'] = True
        feedback_parts.append("File created during task (+15)")
    else:
        subscores['file_created'] = False
        feedback_parts.append("File not found or not created during task (0/15)")

    # Criterion 2: Unit Circle (20 pts)
    if result.get('has_unit_circle', False):
        score += 20
        subscores['has_unit_circle'] = True
        feedback_parts.append("Unit circle found (+20)")
    else:
        subscores['has_unit_circle'] = False
        feedback_parts.append("Unit circle not found (0/20)")

    # Criterion 3: Roots of Unity (25 pts)
    # Check if we found points matching the 5th roots of unity
    found_points = result.get('points_found', [])
    matched_roots = 0
    
    # Mathematical ground truth for 5th roots
    roots_truth = [
        (1.0, 0.0),
        (math.cos(math.radians(72)), math.sin(math.radians(72))),
        (math.cos(math.radians(144)), math.sin(math.radians(144))),
        (math.cos(math.radians(216)), math.sin(math.radians(216))),
        (math.cos(math.radians(288)), math.sin(math.radians(288))),
    ]

    for rx, ry in roots_truth:
        # Check if any found point is close to this root
        match = False
        for px, py in found_points:
            dist = math.hypot(px - rx, py - ry)
            if dist < tolerance:
                match = True
                break
        if match:
            matched_roots += 1

    # Score scaling: need at least 4 roots for full credit, scaled otherwise
    root_score = min(25, matched_roots * 5)
    score += root_score
    subscores['roots_match_count'] = matched_roots
    if matched_roots >= 4:
        feedback_parts.append(f"Roots of unity plotted ({matched_roots}/5) (+{root_score})")
    else:
        feedback_parts.append(f"Insufficient roots found ({matched_roots}/5) (+{root_score})")

    # Criterion 4: Polygon (20 pts)
    if result.get('has_polygon', False):
        score += 20
        subscores['has_polygon'] = True
        feedback_parts.append("Polygon found (+20)")
    else:
        subscores['has_polygon'] = False
        feedback_parts.append("Polygon connecting roots not found (0/20)")

    # Criterion 5: Slider (10 pts)
    if result.get('has_slider', False):
        score += 10
        subscores['has_slider'] = True
        feedback_parts.append("Slider found (+10)")
    else:
        subscores['has_slider'] = False
        feedback_parts.append("Slider for rotation not found (0/10)")

    # Criterion 6: Text (10 pts)
    if result.get('has_text', False):
        score += 10
        subscores['has_text'] = True
        feedback_parts.append("Text annotation found (+10)")
    else:
        subscores['has_text'] = False
        feedback_parts.append("Text annotation not found (0/10)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }