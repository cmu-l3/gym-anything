#!/usr/bin/env python3
"""Verifier for Create Assignment task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_assignment(traj, env_info, task_info):
    """
    Verify that the expected assignment was created in Moodle.

    Checks (ALL must be met to pass - no partial credit):
    1. Assignment exists in the correct course
    2. Assignment name matches expected value EXACTLY
    3. Assignment has a description
    4. Assignment was newly created during this session
    5. Assignment has online text submission enabled

    Pass threshold: 100% (all 5 criteria required)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_assignment_name', 'Lab Report: Cell Biology')
    expected_course = metadata.get('expected_course_shortname', 'BIO101')
    expected_submission_type = metadata.get('expected_submission_type', 'onlinetext')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_assignment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 5  # All 5 criteria must pass - no partial credit
        feedback_parts = []

        initial_count = result.get('initial_assignment_count', 0)
        current_count = result.get('current_assignment_count', 0)
        assignment_found = result.get('assignment_found', False)
        assignment = result.get('assignment', {})

        logger.info(f"Result: initial={initial_count}, current={current_count}, found={assignment_found}")
        logger.info(f"Assignment data: {assignment}")

        # Criterion 1: Assignment exists
        if assignment_found:
            criteria_passed += 1
            feedback_parts.append("Assignment found in course")
        else:
            feedback_parts.append("Assignment NOT found in course")
            if current_count > initial_count:
                feedback_parts.append(f"Note: {current_count - initial_count} new assignment(s) added but not matching expected")
            else:
                feedback_parts.append("No new assignments were created")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "assignment_exists": False,
                    "name_correct": False,
                    "has_description": False,
                    "newly_created": False
                }
            }

        # Criterion 2: Name matches EXACTLY (case-insensitive) - NO partial credit
        name = assignment.get('name', '')
        name_match = name.strip().lower() == expected_name.strip().lower()
        if name_match:
            criteria_passed += 1
            feedback_parts.append(f"Name correct: {expected_name}")
        else:
            feedback_parts.append(f"Name mismatch: expected '{expected_name}', got '{name}'")

        # Criterion 3: Has description
        has_description = assignment.get('has_description', False)
        if has_description:
            criteria_passed += 1
            feedback_parts.append("Assignment has a description")
        else:
            feedback_parts.append("Assignment has no description")

        # Criterion 4: Newly created (count increased)
        if current_count > initial_count:
            criteria_passed += 1
            feedback_parts.append(f"Assignment newly created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append("Assignment count did not increase")

        # Criterion 5: Has correct submission type (online text)
        has_onlinetext = assignment.get('has_onlinetext', False)
        submission_type = assignment.get('submission_type', '')
        if has_onlinetext or 'onlinetext' in submission_type.lower():
            criteria_passed += 1
            feedback_parts.append("Online text submission enabled")
        else:
            feedback_parts.append(f"Online text submission NOT enabled (type: {submission_type})")

        # Calculate score - ALL 5 criteria must pass (100% required)
        score = int((criteria_passed / total_criteria) * 100)
        passed = score == 100  # ALL 5 criteria must be met - no partial passes allowed

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "assignment_exists": assignment_found,
                "name_correct": name_match,
                "has_description": has_description,
                "newly_created": current_count > initial_count,
                "submission_type_correct": has_onlinetext or 'onlinetext' in submission_type.lower()
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
