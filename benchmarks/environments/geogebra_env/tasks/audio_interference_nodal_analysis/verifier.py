#!/usr/bin/env python3
"""
Verifier for Audio Interference Nodal Analysis task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_audio_interference(traj, env_info, task_info):
    """
    Verify the acoustic interference task.
    
    Criteria:
    1. File created during task (10 pts)
    2. Speakers placed at (-2,0) and (2,0) (10 pts)
    3. First nodal hyperbola (2a=1) present (25 pts)
    4. Second nodal hyperbola (2a=3) present (25 pts)
    5. Audience line y=5 present (10 pts)
    6. Dead spots (intersections) marked (20 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {str(e)}"}

    score = 0
    feedback = []
    
    # 1. File Check
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully (+10).")
    else:
        feedback.append("File not found or not created during task (0/10).")

    # 2. Speakers
    if result.get("speakers_correct"):
        score += 10
        feedback.append("Speakers placed correctly at ±2m (+10).")
    else:
        feedback.append("Speakers missing or incorrect coordinates (0/10).")

    # 3. Hyperbola 1 (2a = 1.0)
    if result.get("hyperbola_1_found"):
        score += 25
        feedback.append("First nodal pair (1m path diff) found (+25).")
    else:
        feedback.append("First nodal pair (1m path diff) missing (0/25).")

    # 4. Hyperbola 2 (2a = 3.0)
    if result.get("hyperbola_2_found"):
        score += 25
        feedback.append("Second nodal pair (3m path diff) found (+25).")
    else:
        feedback.append("Second nodal pair (3m path diff) missing (0/25).")

    # 5. Audience Line
    if result.get("audience_line_found"):
        score += 10
        feedback.append("Audience line y=5 found (+10).")
    else:
        feedback.append("Audience line y=5 missing (0/10).")

    # 6. Intersections
    if result.get("intersections_found"):
        score += 20
        feedback.append("Dead spots marked/intersected (+20).")
    else:
        feedback.append("Dead spots not explicitly marked (0/20).")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }