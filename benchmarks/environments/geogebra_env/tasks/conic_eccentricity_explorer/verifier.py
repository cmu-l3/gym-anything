#!/usr/bin/env python3
"""
Verifier for Conic Section Eccentricity Explorer task.

Scoring (100 points):
1. File created during task (15 pts)
2. Eccentricity slider present with valid range (20 pts)
3. Parametric Curve command present (25 pts)
4. Focus point at origin (15 pts)
5. Text annotation (15 pts)
6. Semi-latus rectum defined (10 pts)

Pass threshold: 70 points.
GATE: Curve command must be present to pass > 50 points.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_conic_eccentricity_explorer(traj, env_info, task_info):
    """Verify the conic eccentricity explorer task."""
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
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. File existence (15 pts)
    if result.get('file_found', False) and result.get('file_created_during_task', False):
        score += 15
        feedback_parts.append("File created (+15)")
    else:
        feedback_parts.append("File not created or old (0/15)")

    # 2. Slider (20 pts)
    if result.get('has_eccentricity_slider', False):
        if result.get('slider_range_ok', False):
            score += 20
            feedback_parts.append("Eccentricity slider with correct range found (+20)")
        else:
            score += 10
            feedback_parts.append("Slider found but range may be insufficient (needs 0 to >1) (+10)")
    else:
        feedback_parts.append("Eccentricity slider not found (0/20)")

    # 3. Curve Command (25 pts)
    has_curve = result.get('has_curve_command', False)
    uses_trig = result.get('curve_uses_trig', False)
    
    if has_curve and uses_trig:
        score += 25
        feedback_parts.append("Parametric Curve command found (+25)")
    elif has_curve:
        score += 10
        feedback_parts.append("Curve command found but trig functions not detected (+10)")
    else:
        feedback_parts.append("Curve command not found (0/25)")

    # 4. Focus Point (15 pts)
    if result.get('has_focus_point', False):
        score += 15
        feedback_parts.append("Focus point at (0,0) found (+15)")
    else:
        feedback_parts.append("Focus point not found (0/15)")

    # 5. Text Annotation (15 pts)
    if result.get('has_text_annotation', False):
        score += 15
        feedback_parts.append("Text annotation found (+15)")
    else:
        feedback_parts.append("No text annotation (0/15)")

    # 6. Latus Rectum (10 pts)
    if result.get('latus_rectum_defined', False):
        score += 10
        feedback_parts.append("Semi-latus rectum defined (+10)")
    else:
        # Implicit check: if curve exists and file exists, they likely used a constant
        if has_curve:
            score += 5
            feedback_parts.append("Implicit latus rectum (+5)")
        else:
            feedback_parts.append("Semi-latus rectum not explicitly defined (0/10)")

    # GATE RULE: Cap score if Curve command is missing (core task requirement)
    if not has_curve and score > 50:
        score = 50
        feedback_parts.append("Score capped at 50 due to missing Curve command")

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }