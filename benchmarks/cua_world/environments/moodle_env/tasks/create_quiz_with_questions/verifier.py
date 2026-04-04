#!/usr/bin/env python3
"""Verifier for Create Quiz with Questions task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_quiz_with_questions(traj, env_info, task_info):
    """
    Verify that a quiz with correct settings and questions was created in BIO101.

    Scoring (100 points):
    - Criterion 1: Quiz exists and was newly created in BIO101 (20 points) - CRITICAL
    - Criterion 2: Quiz name matches (20 points)
    - Criterion 3: Time limit set to 60 minutes / 3600 seconds (20 points)
    - Criterion 4: Attempts limited to 1 (20 points)
    - Criterion 5: At least 2 questions added to quiz (20 points)

    Pass threshold: 60 points (must include quiz exists + correct name)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_quiz_with_questions_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # CRITICAL: Wrong course check
        quiz_course_id = str(result.get('quiz_course_id', ''))
        expected_course_id = str(result.get('course_id', ''))
        if quiz_course_id and expected_course_id and quiz_course_id != expected_course_id:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Quiz created in wrong course (course_id={quiz_course_id}, expected={expected_course_id})"
            }

        # Criterion 1: Quiz exists and was newly created (20 points)
        quiz_found = result.get('quiz_found', False)
        initial_count = int(result.get('initial_quiz_count', 0))
        current_count = int(result.get('current_quiz_count', 0))
        newly_created = current_count > initial_count

        if quiz_found and newly_created:
            score += 20
            subscores["quiz_created"] = True
            feedback_parts.append(f"Quiz created in BIO101 (count: {initial_count} -> {current_count})")
        elif quiz_found:
            score += 10
            feedback_parts.append("Quiz found but may be pre-existing")
        else:
            feedback_parts.append("No matching quiz found in BIO101")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"quiz_created": False, "correct_name": False,
                              "correct_timelimit": False, "correct_attempts": False,
                              "questions_added": False}
            }

        # Criterion 2: Quiz name matches (20 points)
        quiz_name = result.get('quiz_name', '').lower().strip()
        if 'midterm' in quiz_name and 'cell biology' in quiz_name:
            score += 20
            subscores["correct_name"] = True
            feedback_parts.append("Quiz name correct")
        else:
            subscores["correct_name"] = False
            feedback_parts.append(f"Quiz name mismatch: '{result.get('quiz_name', '')}'")

        # Criterion 3: Time limit = 3600 seconds (20 points)
        timelimit = int(result.get('quiz_timelimit', 0))
        if timelimit == 3600:
            score += 20
            subscores["correct_timelimit"] = True
            feedback_parts.append("Time limit: 60 minutes")
        elif 3000 <= timelimit <= 4200:
            # Close enough (50-70 min range) - partial credit
            score += 10
            subscores["correct_timelimit"] = False
            feedback_parts.append(f"Time limit close: {timelimit}s (expected 3600s)")
        elif timelimit > 0:
            score += 5
            subscores["correct_timelimit"] = False
            feedback_parts.append(f"Time limit set but wrong: {timelimit}s (expected 3600s)")
        else:
            subscores["correct_timelimit"] = False
            feedback_parts.append("No time limit set")

        # Criterion 4: Attempts = 1 (20 points)
        attempts = int(result.get('quiz_attempts', 0))
        if attempts == 1:
            score += 20
            subscores["correct_attempts"] = True
            feedback_parts.append("Attempts limited to 1")
        else:
            subscores["correct_attempts"] = False
            feedback_parts.append(f"Attempts: {attempts} (expected 1, 0=unlimited)")

        # Criterion 5: At least 2 questions added (20 points)
        question_count = int(result.get('question_count', 0))
        if question_count >= 2:
            score += 20
            subscores["questions_added"] = True
            feedback_parts.append(f"{question_count} questions added")
        elif question_count == 1:
            score += 10
            subscores["questions_added"] = False
            feedback_parts.append("Only 1 question added (expected 2)")
        else:
            subscores["questions_added"] = False
            feedback_parts.append("No questions added to quiz")

        # Pass requires quiz created + correct name (minimum meaningful completion)
        passed = score >= 60 and subscores.get("quiz_created", False) and subscores.get("correct_name", False)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
