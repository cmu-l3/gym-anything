#!/usr/bin/env python3
"""Verifier for Create Choice Activity task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_choice_activity(traj, env_info, task_info):
    """
    Verify that a Choice (poll) activity was created in CS110 with correct options.

    Scoring (100 points):
    - Criterion 1: Choice activity exists and was newly created in CS110 (20 points) - CRITICAL
    - Criterion 2: Activity name matches (15 points)
    - Criterion 3: Has at least 4 options (15 points)
    - Criterion 4: Options include all 4 expected languages (25 points)
    - Criterion 5: Allow update enabled (10 points)
    - Criterion 6: Show results set correctly (15 points)

    Pass threshold: 60 points (must have choice created + correct name)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_choice_activity_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # CRITICAL: Wrong course check
        choice_course_id = str(result.get('choice_course_id', ''))
        expected_course_id = str(result.get('course_id', ''))
        if choice_course_id and expected_course_id and choice_course_id != expected_course_id:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Choice created in wrong course (course_id={choice_course_id}, expected={expected_course_id})"
            }

        # Criterion 1: Choice exists and was newly created (20 points)
        choice_found = result.get('choice_found', False)
        initial_count = int(result.get('initial_choice_count', 0))
        current_count = int(result.get('current_choice_count', 0))
        newly_created = current_count > initial_count

        if choice_found and newly_created:
            score += 20
            subscores["choice_created"] = True
            feedback_parts.append(f"Choice activity created in CS110 (count: {initial_count} -> {current_count})")
        elif choice_found:
            score += 10
            subscores["choice_created"] = False
            feedback_parts.append("Choice found but may be pre-existing")
        else:
            subscores["choice_created"] = False
            feedback_parts.append("No matching choice activity found in CS110")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {"choice_created": False, "correct_name": False,
                              "enough_options": False, "correct_options": False,
                              "allow_update": False, "show_results": False}
            }

        # Criterion 2: Activity name matches (15 points)
        choice_name = result.get('choice_name', '').lower().strip()
        if 'preferred' in choice_name and 'programming' in choice_name and 'language' in choice_name:
            score += 15
            subscores["correct_name"] = True
            feedback_parts.append("Activity name correct")
        elif 'programming' in choice_name or 'language' in choice_name:
            score += 7
            subscores["correct_name"] = False
            feedback_parts.append(f"Activity name partial: '{result.get('choice_name', '')}'")
        else:
            subscores["correct_name"] = False
            feedback_parts.append(f"Activity name mismatch: '{result.get('choice_name', '')}'")

        # Criterion 3: At least 4 options (15 points)
        option_count = int(result.get('option_count', 0))
        if option_count >= 4:
            score += 15
            subscores["enough_options"] = True
            feedback_parts.append(f"{option_count} options created")
        elif option_count >= 2:
            score += 7
            subscores["enough_options"] = False
            feedback_parts.append(f"Only {option_count} options (expected 4)")
        else:
            subscores["enough_options"] = False
            feedback_parts.append("Too few options")

        # Criterion 4: All 4 expected languages present (25 points, ~6 each)
        languages = {
            'python': result.get('has_python', False),
            'java': result.get('has_java', False),
            'c++': result.get('has_cpp', False),
            'javascript': result.get('has_javascript', False),
        }
        found_langs = [lang for lang, present in languages.items() if present]
        missing_langs = [lang for lang, present in languages.items() if not present]
        lang_score = len(found_langs) * 6
        if len(found_langs) == 4:
            lang_score = 25  # Bonus for all 4

        score += lang_score
        subscores["correct_options"] = len(found_langs) == 4
        if found_langs:
            feedback_parts.append(f"Languages found: {', '.join(found_langs)}")
        if missing_langs:
            feedback_parts.append(f"Languages missing: {', '.join(missing_langs)}")

        # Criterion 5: Allow update enabled (10 points)
        allowupdate = int(result.get('choice_allowupdate', 0))
        if allowupdate == 1:
            score += 10
            subscores["allow_update"] = True
            feedback_parts.append("Allow choice update: Yes")
        else:
            subscores["allow_update"] = False
            feedback_parts.append("Allow choice update: No (expected Yes)")

        # Criterion 6: Show results = Always (15 points)
        # Moodle: 0=Do not publish, 1=After answering, 2=After closing, 3=Always
        showresults = int(result.get('choice_showresults', 0))
        if showresults == 3:
            score += 15
            subscores["show_results"] = True
            feedback_parts.append("Show results: Always")
        elif showresults > 0:
            score += 7
            subscores["show_results"] = False
            result_modes = {1: "After answering", 2: "After closing"}
            feedback_parts.append(f"Show results: {result_modes.get(showresults, showresults)} (expected Always)")
        else:
            subscores["show_results"] = False
            feedback_parts.append("Show results: Do not publish (expected Always)")

        passed = (score >= 60
                  and subscores.get("choice_created", False))

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
