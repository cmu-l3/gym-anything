#!/usr/bin/env python3
"""
Verifier for bulk_edit_time_entries task.

Checks:
1. Target entries (junior_dev) changed from Design -> Development.
2. Distractor entries (admin) remained Design.
3. Hours values remained unchanged.
4. No remaining Design entries for junior_dev.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_edit_time_entries(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    targets = result.get("targets", [])
    distractors = result.get("distractors", [])
    remaining_mistakes = result.get("remaining_mistakes", 999)

    # Criterion 1: Target Entries Converted (50 pts)
    # Expect all 5 targets to be "Development"
    correct_targets = 0
    total_targets = len(targets)
    
    for t in targets:
        if t.get("activity_name") == "Development":
            correct_targets += 1
        else:
            feedback_parts.append(f"Target ID {t.get('id')} is still {t.get('activity_name')}")

    if total_targets > 0:
        target_score = (correct_targets / total_targets) * 50
        score += target_score
        if correct_targets == total_targets:
            feedback_parts.append("All target entries reclassified correctly")
    
    # Criterion 2: Distractor Integrity (30 pts)
    # Expect all 3 distractors to be "Design"
    intact_distractors = 0
    total_distractors = len(distractors)
    
    for d in distractors:
        if d.get("activity_name") == "Design":
            intact_distractors += 1
        else:
            feedback_parts.append(f"Distractor ID {d.get('id')} was incorrectly changed to {d.get('activity_name')}")

    if total_distractors > 0:
        distractor_score = (intact_distractors / total_distractors) * 30
        score += distractor_score
        if intact_distractors == total_distractors:
            feedback_parts.append("Distractor entries preserved")

    # Criterion 3: Hour Integrity (10 pts)
    # Targets were 2.0 hours, Distractors 1.0
    hours_correct = True
    for t in targets:
        if t.get("hours") != 2.0:
            hours_correct = False
            feedback_parts.append(f"Target ID {t.get('id')} hours changed to {t.get('hours')}")
    
    if hours_correct:
        score += 10
        feedback_parts.append("Hours values preserved")

    # Criterion 4: Cleanup (10 pts)
    if remaining_mistakes == 0:
        score += 10
        feedback_parts.append("No misclassified entries remain for user")
    else:
        feedback_parts.append(f"{remaining_mistakes} misclassified entries still exist")

    # Final Check
    passed = (score >= 80) and (intact_distractors == total_distractors)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": "; ".join(feedback_parts)
    }