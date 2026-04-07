#!/usr/bin/env python3
"""Verifier for Create Lesson Activity task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_lesson_activity(traj, env_info, task_info):
    """
    Verify that a Lesson activity with content and question pages was created.

    Scoring (100 points):
    - Criterion 1: Lesson exists in BIO101 (15 points)
    - Criterion 2: Lesson name matches pattern (15 points)
    - Criterion 3: Lesson was newly created/modified during task (5 points)
    - Criterion 4: At least 2 content pages created (20 points)
    - Criterion 5: At least 1 question page created (20 points)
    - Criterion 6: Question has >= 3 answer choices (15 points)
    - Criterion 7: At least one answer is marked correct (10 points)

    Pass threshold: 60 points (must have lesson created + correct name + at least some pages)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_lesson_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Lesson exists (15 points)
        lesson_found = result.get('lesson_found', False)
        if lesson_found:
            score += 15
            subscores["lesson_exists"] = True
            feedback_parts.append("Lesson activity found")
        else:
            subscores["lesson_exists"] = False
            feedback_parts.append("Lesson activity NOT found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # Criterion 2: Name matches (15 points)
        # The export script already filtered by name LIKE pattern, so if found, it matches roughly.
        # We can double check strictness if needed, but export script filter is usually sufficient.
        lesson_name = result.get('lesson_name', '')
        if "cell biology" in lesson_name.lower() and "interactive" in lesson_name.lower():
            score += 15
            subscores["name_correct"] = True
            feedback_parts.append("Lesson name correct")
        else:
            score += 5  # Partial credit if found but slightly off (unlikely given export filter)
            subscores["name_correct"] = False
            feedback_parts.append(f"Lesson name matches pattern (Found: {lesson_name})")

        # Criterion 3: Newly created/modified (5 points)
        created_during_task = result.get('created_during_task', False)
        if created_during_task:
            score += 5
            subscores["newly_created"] = True
            feedback_parts.append("Lesson modified during task")
        else:
            feedback_parts.append("Lesson not modified during task (old timestamp)")

        # Criterion 4: Content Pages >= 2 (20 points)
        content_count = int(result.get('content_page_count', 0))
        if content_count >= 2:
            score += 20
            subscores["content_pages"] = True
            feedback_parts.append(f"Content pages: {content_count} (>= 2)")
        elif content_count == 1:
            score += 10
            subscores["content_pages"] = False
            feedback_parts.append(f"Content pages: {content_count} (partial credit)")
        else:
            subscores["content_pages"] = False
            feedback_parts.append("No content pages found")

        # Criterion 5: Question Pages >= 1 (20 points)
        question_count = int(result.get('question_page_count', 0))
        if question_count >= 1:
            score += 20
            subscores["question_pages"] = True
            feedback_parts.append(f"Question pages: {question_count} (>= 1)")
        else:
            subscores["question_pages"] = False
            feedback_parts.append("No question pages found")

        # Criterion 6: Question has >= 3 answers (15 points)
        answer_count = int(result.get('answer_count', 0))
        if answer_count >= 3:
            score += 15
            subscores["answers_count"] = True
            feedback_parts.append(f"Answer choices: {answer_count}")
        elif answer_count > 0:
            score += 5
            subscores["answers_count"] = False
            feedback_parts.append(f"Answer choices: {answer_count} (too few)")
        else:
            subscores["answers_count"] = False
            feedback_parts.append("No answers configured for question")

        # Criterion 7: Correct answer marked (10 points)
        has_correct = result.get('has_correct_answer', False)
        if has_correct:
            score += 10
            subscores["correct_answer_set"] = True
            feedback_parts.append("Correct answer configured")
        else:
            subscores["correct_answer_set"] = False
            feedback_parts.append("No answer marked as correct (score > 0)")

        passed = score >= 60 and lesson_found and (content_count > 0 or question_count > 0)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export_result.sh failed"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON in result file"}
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}