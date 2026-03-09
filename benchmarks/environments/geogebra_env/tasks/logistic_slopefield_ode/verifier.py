#!/usr/bin/env python3
"""
Verifier for Logistic Slope Field ODE task.

Scoring (100 points total):
  - File created during task:           15 pts
  - SlopeField command present:         25 pts (CRITICAL)
  - At least 2 SolveODE curves:         25 pts
  - Slider parameters present (>=1):    15 pts
  - Text annotation present:            20 pts

Pass threshold: 70 points
Gate: SlopeField must be present.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_logistic_slopefield_ode(traj, env_info, task_info):
    """Verify the logistic slope field ODE task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving verification results: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # 1. File Check (15 pts)
    file_found = result.get('file_found', False)
    file_new = result.get('file_created_during_task', False)
    
    if file_found and file_new:
        score += 15
        subscores['file'] = True
        feedback_parts.append("File created successfully (+15)")
    elif file_found:
        feedback_parts.append("File found but not created during this task session (0/15)")
        subscores['file'] = False
    else:
        feedback_parts.append("File 'logistic_slopefield.ggb' not found (0/15)")
        subscores['file'] = False

    # 2. SlopeField Command (25 pts) - CRITICAL GATE
    has_slopefield = result.get('has_slopefield', False)
    if has_slopefield:
        score += 25
        subscores['slopefield'] = True
        feedback_parts.append("SlopeField command found (+25)")
    else:
        subscores['slopefield'] = False
        feedback_parts.append("SlopeField command NOT found (0/25)")

    # 3. SolveODE Curves (25 pts)
    ode_count = result.get('solve_ode_count', 0)
    if ode_count >= 2:
        score += 25
        subscores['solveode'] = True
        feedback_parts.append(f"Multiple solution curves found ({ode_count}) (+25)")
    elif ode_count == 1:
        score += 10
        subscores['solveode'] = 'partial'
        feedback_parts.append("Only one solution curve found; expected at least 2 (+10)")
    else:
        subscores['solveode'] = False
        feedback_parts.append("No SolveODE solution curves found (0/25)")

    # 4. Sliders (15 pts)
    slider_count = result.get('slider_count', 0)
    if slider_count >= 1:
        score += 15
        subscores['sliders'] = True
        feedback_parts.append(f"Sliders found ({slider_count}) (+15)")
    else:
        subscores['sliders'] = False
        feedback_parts.append("No sliders found (0/15)")

    # 5. Text Annotation (20 pts)
    has_text = result.get('has_text', False)
    if has_text:
        score += 20
        subscores['text'] = True
        feedback_parts.append("Text annotation found (+20)")
    else:
        subscores['text'] = False
        feedback_parts.append("No text annotation found (0/20)")

    # GATE CHECK
    if not has_slopefield and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append(f"Score capped at {PASS_THRESHOLD-1} because SlopeField is missing")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }