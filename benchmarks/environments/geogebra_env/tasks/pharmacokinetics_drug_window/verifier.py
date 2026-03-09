#!/usr/bin/env python3
"""
Verifier for Pharmacokinetics Drug Window task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_pharmacokinetics_drug_window(traj, env_info, task_info):
    """
    Verify the PK Analysis task.
    Criteria:
    1. File creation (anti-gaming check).
    2. Correct Bateman function definition.
    3. Window lines defined (y=5).
    4. Intersection points identified.
    5. Duration computed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully.")
    else:
        feedback.append("File not found or pre-dated task.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Bateman Function (20 pts)
    # Heuristic check for exponential structure
    if result.get("has_bateman_function"):
        score += 20
        feedback.append("Concentration function defined.")
    else:
        feedback.append("Function definition missing or incorrect structure.")

    # 3. Window Lines (20 pts)
    if result.get("has_window_lines"):
        score += 20
        feedback.append("Therapeutic window lines found.")
    else:
        feedback.append("Missing therapeutic window lines (e.g., y=5).")

    # 4. Intersections (25 pts)
    # We expect 2 points near y=5
    intersections = result.get("intersection_points_count", 0)
    if intersections >= 2:
        score += 25
        feedback.append(f"Found {intersections} intersection points at threshold.")
    elif intersections == 1:
        score += 10
        feedback.append("Found only 1 intersection point.")
    else:
        feedback.append("No intersection points found at 5 mg/L.")

    # 5. Duration (25 pts)
    # Expected approx 9.22
    duration = result.get("duration_value")
    if duration is not None:
        score += 25
        feedback.append(f"Duration calculated correctly ({duration:.2f} hrs).")
    else:
        feedback.append("Duration not calculated or incorrect value.")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }