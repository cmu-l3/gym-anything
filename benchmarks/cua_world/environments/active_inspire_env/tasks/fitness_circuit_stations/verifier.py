#!/usr/bin/env python3
"""
Verifier for fitness_circuit_stations task.

Scoring (100 points, pass at 70):
1. File exists + valid format + created during task (15 pts)
2. Page count == 4 (10 pts)
3. Content checks (10 pts each):
   - Title "Circuit Training"
   - Safety "Warm up"
   - Station 1 "Jumping Jacks"
   - Station 2 "Wall Sit"
   - Station 3 "Push"
   - Reps/Time numbers present
4. Shapes (15 pts):
   - At least 3 circles/ellipses found
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fitness_circuit(traj, env_info, task_info):
    """
    Verify the fitness circuit flipchart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Load result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }

    score = 0
    feedback_parts = []
    
    # 1. File existence and validity (15 pts)
    # Critical gate: if file doesn't exist or wasn't created now, fail early
    file_found = result.get('file_found', False)
    file_valid = result.get('file_valid', False)
    created_now = result.get('created_during_task', False)

    if not file_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task failed: No output file found."
        }
    
    if file_valid and created_now:
        score += 15
        feedback_parts.append("Valid file created (15/15)")
    elif file_found:
        feedback_parts.append("File found but invalid format or old timestamp (0/15)")

    # 2. Page Count (10 pts)
    # Strictly 4 pages required
    page_count = result.get('page_count', 0)
    if page_count == 4:
        score += 10
        feedback_parts.append("Correct page count: 4 (10/10)")
    else:
        feedback_parts.append(f"Incorrect page count: {page_count}, expected 4 (0/10)")

    # 3. Text Content (60 pts total)
    content_checks = [
        ('has_title', "Title 'Circuit Training'", 10),
        ('has_safety', "Safety text 'Warm up'", 10),
        ('has_station1', "Station 1 'Jumping Jacks'", 10),
        ('has_station2', "Station 2 'Wall Sit'", 10),
        ('has_station3', "Station 3 'Push-Ups'", 10),
        ('has_reps', "Rep counts found", 10)
    ]

    for key, name, pts in content_checks:
        if result.get(key, False):
            score += pts
            feedback_parts.append(f"{name} found ({pts}/{pts})")
        else:
            feedback_parts.append(f"{name} missing (0/{pts})")

    # 4. Shapes (15 pts)
    circle_count = result.get('circle_count', 0)
    if circle_count >= 3:
        score += 15
        feedback_parts.append(f"Shapes found: {circle_count} circles (15/15)")
    elif circle_count > 0:
        score += 5
        feedback_parts.append(f"Few shapes found: {circle_count}, expected 3+ (5/15)")
    else:
        feedback_parts.append("No circle shapes found (0/15)")

    # 5. VLM Check (Bonus/Verification of Colors)
    # Since programmatic check covers shapes, we rely on VLM for visual confirmation
    # This example focuses on programmatic scoring as the primary driver, 
    # but implies visual verification was part of the intended strategy.
    # We will trust the robust XML parsing for now as primary.

    passed = score >= 70 and file_valid and created_now

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }