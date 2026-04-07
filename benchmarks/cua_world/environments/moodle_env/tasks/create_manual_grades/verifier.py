#!/usr/bin/env python3
"""Verifier for Create Manual Grades task in Moodle."""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_manual_grades(traj, env_info, task_info):
    """
    Verify that a manual grade item was created with correct settings and student grades.

    Scoring (100 points):
    - Grade item exists with correct name in BIO101 (15 pts)
    - Item type is manual and in correct course (15 pts)
    - Maximum grade = 50 (10 pts)
    - Grade to pass = 30 (10 pts)
    - 4 Student grades correct (12.5 pts each = 50 pts total)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_max = metadata.get('grade_max', 50.0)
    expected_pass = metadata.get('grade_pass', 30.0)
    expected_grades = metadata.get('student_grades', {})

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_manual_grades_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Basic Check: Item found
        item_found = result.get('item_found', False)
        
        # Check if actually created during task
        time_created = int(result.get('time_created', 0))
        task_start = int(result.get('task_start_time', 0))
        newly_created = time_created >= task_start
        
        # Or count check as fallback
        initial_count = int(result.get('initial_item_count', 0))
        current_count = int(result.get('current_item_count', 0))
        count_increased = current_count > initial_count
        
        is_new = newly_created or count_increased

        if not item_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Grade item 'Clinical Skills Assessment' not found in BIO101."
            }

        # Criterion 1: Existence & Name (15 pts)
        score += 15
        feedback_parts.append("Grade item created")
        subscores["item_exists"] = True

        # Criterion 2: Correct Context/Anti-gaming (15 pts)
        if is_new:
            score += 15
            feedback_parts.append("Item newly created")
            subscores["newly_created"] = True
        else:
            feedback_parts.append("Item may be pre-existing")
            subscores["newly_created"] = False

        # Criterion 3: Max Grade (10 pts)
        actual_max = float(result.get('grade_max', 0))
        if abs(actual_max - expected_max) < 0.01:
            score += 10
            feedback_parts.append(f"Max grade correct ({expected_max})")
            subscores["max_grade"] = True
        else:
            feedback_parts.append(f"Max grade mismatch: {actual_max} (expected {expected_max})")
            subscores["max_grade"] = False

        # Criterion 4: Grade to Pass (10 pts)
        actual_pass = float(result.get('grade_pass', 0))
        if abs(actual_pass - expected_pass) < 0.01:
            score += 10
            feedback_parts.append(f"Pass grade correct ({expected_pass})")
            subscores["pass_grade"] = True
        else:
            feedback_parts.append(f"Pass grade mismatch: {actual_pass} (expected {expected_pass})")
            subscores["pass_grade"] = False

        # Criterion 5: Student Grades (50 pts total)
        actual_grades = result.get('student_grades', {})
        grades_score = 0
        grades_feedback = []
        
        for user, expected_val in expected_grades.items():
            actual_val = actual_grades.get(user)
            
            if actual_val is None:
                grades_feedback.append(f"{user}: Missing")
                continue
                
            if abs(float(actual_val) - expected_val) < 0.5:
                grades_score += 12.5
                grades_feedback.append(f"{user}: OK")
            else:
                grades_feedback.append(f"{user}: Wrong ({actual_val})")
        
        score += grades_score
        if grades_score > 0:
            feedback_parts.append(f"Grades: {', '.join(grades_feedback)}")
        else:
            feedback_parts.append("No correct student grades entered")

        passed = score >= 60 and item_found

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {str(e)}"}