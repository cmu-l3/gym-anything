#!/usr/bin/env python3
"""Verifier for Create Course task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_course(traj, env_info, task_info):
    """
    Verify that the expected course was created in Moodle.

    Checks (ALL must be met to pass - no partial credit):
    1. Course with expected shortname exists in database
    2. Course shortname matches expected value EXACTLY
    3. Course fullname matches expected value EXACTLY
    4. Course is in the expected category
    5. Course was newly created during this session (count increased) - CRITICAL

    Pass threshold: 100% (all 5 criteria required)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_fullname = metadata.get('expected_fullname', 'Data Science 101')
    expected_shortname = metadata.get('expected_shortname', 'DS101')
    expected_category = metadata.get('expected_category', 'Science')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_course_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 5  # All 5 criteria must pass - no partial credit
        feedback_parts = []

        initial_count = result.get('initial_course_count', 0)
        current_count = result.get('current_course_count', 0)
        course_found = result.get('course_found', False)
        course = result.get('course', {})

        # Check if course was newly created (CRITICAL: prevents pre-existing courses from passing)
        newly_created = current_count > initial_count

        logger.info(f"Result: initial={initial_count}, current={current_count}, found={course_found}")
        logger.info(f"Course data: {course}")

        # Criterion 1: Course exists in database
        if course_found:
            criteria_passed += 1
            feedback_parts.append("Course found in database")
        else:
            feedback_parts.append("Course NOT found in database")
            if current_count > initial_count:
                feedback_parts.append(f"Note: {current_count - initial_count} new course(s) added but not matching expected")
            else:
                feedback_parts.append("No new courses were added")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "course_exists": False,
                    "fullname_correct": False,
                    "shortname_correct": False,
                    "category_correct": False,
                    "newly_created": False
                }
            }

        # Criterion 2: Shortname matches EXACTLY (case-insensitive)
        shortname = course.get('shortname', '')
        shortname_match = shortname.strip().lower() == expected_shortname.strip().lower()
        if shortname_match:
            criteria_passed += 1
            feedback_parts.append(f"Short name correct: {expected_shortname}")
        else:
            feedback_parts.append(f"Short name mismatch: expected '{expected_shortname}', got '{shortname}'")

        # Criterion 3: Fullname matches EXACTLY (case-insensitive) - NO partial credit
        fullname = course.get('fullname', '')
        fullname_match = fullname.strip().lower() == expected_fullname.strip().lower()
        if fullname_match:
            criteria_passed += 1
            feedback_parts.append(f"Full name correct: {expected_fullname}")
        else:
            feedback_parts.append(f"Full name mismatch: expected '{expected_fullname}', got '{fullname}'")

        # Criterion 4: Category matches EXACTLY (case-insensitive)
        category_name = course.get('category_name', '')
        category_match = category_name.strip().lower() == expected_category.strip().lower()
        if category_match:
            criteria_passed += 1
            feedback_parts.append(f"Category correct: {expected_category}")
        else:
            feedback_parts.append(f"Category mismatch: expected '{expected_category}', got '{category_name}'")

        # Criterion 5: Course was newly created (count increased) - REQUIRED
        if newly_created:
            criteria_passed += 1
            feedback_parts.append(f"Course newly created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"FAIL: Course count unchanged ({initial_count}) - task requires creating NEW course")

        # Calculate score - ALL 5 criteria must pass (100% required)
        score = int((criteria_passed / total_criteria) * 100)
        passed = score == 100  # ALL 5 criteria must be met - no partial passes allowed

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "course_exists": course_found,
                "fullname_correct": fullname_match,
                "shortname_correct": shortname_match,
                "category_correct": category_match,
                "newly_created": newly_created
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
