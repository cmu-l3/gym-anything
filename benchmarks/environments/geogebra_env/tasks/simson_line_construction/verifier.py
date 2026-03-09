#!/usr/bin/env python3
"""
Verifier for Simson Line Construction task.
Scores based on geometric elements found in the GeoGebra file.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_simson_line_construction(traj, env_info, task_info):
    """
    Verify the Simson Line construction.
    
    Criteria:
    1. File creation (anti-gaming): 15 pts
    2. Triangle vertices correct: 15 pts
    3. Circumcircle present: 20 pts (GATE)
    4. Point on circumcircle: 15 pts
    5. Perpendiculars to sides: 20 pts
    6. Simson Line drawn: 10 pts
    7. Annotation present: 5 pts
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {e}"}

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Check (15 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 15
        feedback_parts.append("File created (+15)")
    elif result.get("file_found"):
        feedback_parts.append("File exists but old timestamp (0/15)")
    else:
        feedback_parts.append("File not found (0/15)")

    # Criterion 2: Vertices (15 pts)
    v_found = result.get("vertices_found", 0)
    if v_found >= 3:
        score += 15
        feedback_parts.append("All 3 vertices correct (+15)")
    elif v_found > 0:
        partial = v_found * 5
        score += partial
        feedback_parts.append(f"{v_found}/3 vertices correct (+{partial})")
    else:
        feedback_parts.append("Triangle vertices incorrect (0/15)")

    # Criterion 3: Circumcircle (20 pts) - GATE CRITERION
    has_circumcircle = result.get("has_circumcircle", False)
    if has_circumcircle:
        score += 20
        feedback_parts.append("Circumcircle found (+20)")
    else:
        feedback_parts.append("Circumcircle MISSING (0/20)")

    # Criterion 4: Point on Circle (15 pts)
    if result.get("has_point_on_circle"):
        score += 15
        feedback_parts.append("Point on circle found (+15)")
    else:
        feedback_parts.append("Point on circle missing/incorrect (0/15)")

    # Criterion 5: Perpendiculars (20 pts)
    # Expect at least 2 perpendicular lines to define the Simson line
    num_perp = result.get("num_perpendiculars", 0)
    if num_perp >= 2:
        score += 20
        feedback_parts.append(f"{num_perp} perpendiculars found (+20)")
    elif num_perp == 1:
        score += 10
        feedback_parts.append("Only 1 perpendicular found (+10)")
    else:
        feedback_parts.append("Perpendicular projections missing (0/20)")

    # Criterion 6: Simson Line (10 pts)
    if result.get("has_simson_line"):
        score += 10
        feedback_parts.append("Simson line found (+10)")
    else:
        feedback_parts.append("Simson line missing (0/10)")

    # Criterion 7: Annotation (5 pts)
    if result.get("has_annotation"):
        score += 5
        feedback_parts.append("Annotation found (+5)")
    else:
        feedback_parts.append("No text annotation (0/5)")

    # Gate Check
    if not has_circumcircle and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append("FAILED GATE: Circumcircle is required to pass")

    # 3. Final Result
    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }