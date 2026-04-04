#!/usr/bin/env python3
"""
Verifier for regression_analysis_world_development task.

Scoring (100 points total):
  - File created during task:           20 pts
  - Sufficient data points entered:     20 pts  (≥10 points OR a list object)
  - FitLine (linear regression) present: 20 pts
  - FitLog or other nonlinear fit:       20 pts  (shows comparison)
  - Text annotation present:            20 pts

Pass threshold: 70 points

GATE: FitLine must be present for score to reach pass threshold.
      (prevents scatter-plot-only submissions from passing)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_regression_analysis_world_development(traj, env_info, task_info):
    """Verify the world development regression analysis task."""
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
            feedback_parts.append("File 'world_regression.ggb' not found (0/20)")
        else:
            feedback_parts.append("File exists but predates task session (0/20)")

    # Criterion 2: Sufficient data points entered (20 pts)
    num_pts = result.get('num_points', 0)
    num_lists = result.get('num_lists', 0)
    has_data = result.get('has_scatter_data', False)
    if has_data:
        score += 20
        subscores["has_data"] = True
        feedback_parts.append(f"Data entered ({num_pts} points, {num_lists} lists) (+20)")
    else:
        subscores["has_data"] = False
        feedback_parts.append(
            f"Insufficient data: {num_pts} points and {num_lists} lists found; need ≥10 points or 1 list (0/20)"
        )

    # Criterion 3: FitLine (linear regression) present (20 pts)
    has_fitline = result.get('has_fitline', False)
    if has_fitline:
        score += 20
        subscores["has_fitline"] = True
        slope = result.get('fitline_slope')
        if slope is not None:
            feedback_parts.append(f"FitLine (linear regression) found, slope≈{slope:.4f} (+20)")
        else:
            feedback_parts.append("FitLine (linear regression) found (+20)")
    else:
        subscores["has_fitline"] = False
        commands = result.get('xml_commands', [])
        feedback_parts.append(
            f"FitLine command not found; use FitLine(listName) in input bar (0/20). "
            f"Commands seen: {', '.join(sorted(commands)[:6])}"
        )

    # GATE: If FitLine is absent and score would reach threshold, cap it
    if not has_fitline and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped at {PASS_THRESHOLD-1}: FitLine is required")

    # Criterion 4: FitLog or other nonlinear regression (20 pts)
    has_fitlog = result.get('has_fitlog', False)
    if has_fitlog:
        score += 20
        subscores["has_fitlog"] = True
        feedback_parts.append("Non-linear regression (FitLog/FitExp/etc.) found (+20)")
    else:
        subscores["has_fitlog"] = False
        feedback_parts.append("No non-linear regression model found; use FitLog(listName) (0/20)")

    # Criterion 5: Text annotation (20 pts)
    has_annotation = result.get('has_annotation', False)
    if has_annotation:
        score += 20
        subscores["has_annotation"] = True
        feedback_parts.append("Text annotation found (+20)")
    else:
        subscores["has_annotation"] = False
        feedback_parts.append("No text annotation found; add regression equation as text label (0/20)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
