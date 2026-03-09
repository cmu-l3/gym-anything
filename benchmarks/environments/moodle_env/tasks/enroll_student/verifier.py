#!/usr/bin/env python3
"""Verifier for Enroll Student task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_enroll_student(traj, env_info, task_info):
    """
    Verify that the expected student was enrolled in the expected course.

    Checks (ALL must be met to pass - no partial credit):
    1. User is enrolled in the course
    2. Enrollment was newly created (not pre-existing) - CRITICAL
    3. User has the correct role (student)

    Pass threshold: 100% (all 3 criteria required)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_username = metadata.get('expected_username', 'epatel')
    expected_course = metadata.get('expected_course_shortname', 'BIO101')
    expected_role = metadata.get('expected_role', 'student')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/enroll_student_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 3  # All 3 criteria must pass - no partial credit
        feedback_parts = []

        is_enrolled = result.get('is_enrolled', False)
        was_already_enrolled = result.get('was_already_enrolled', False)
        enrollment_role = result.get('enrollment_role', '')
        initial_count = result.get('initial_enrollment_count', 0)
        current_count = result.get('current_enrollment_count', 0)

        logger.info(f"Result: enrolled={is_enrolled}, was_already={was_already_enrolled}, "
                     f"role={enrollment_role}, initial={initial_count}, current={current_count}")

        # Criterion 1: User is enrolled in the course
        if is_enrolled:
            criteria_passed += 1
            feedback_parts.append(f"User '{expected_username}' is enrolled in {expected_course}")
        else:
            feedback_parts.append(f"User '{expected_username}' is NOT enrolled in {expected_course}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "user_enrolled": False,
                    "correct_role": False,
                    "newly_enrolled": False
                }
            }

        # Criterion 2: User has the expected role - NO partial credit
        role_match = False
        if enrollment_role:
            role_match = enrollment_role.strip().lower() == expected_role.strip().lower()
            if role_match:
                criteria_passed += 1
                feedback_parts.append(f"Role correct: {expected_role}")
            else:
                feedback_parts.append(f"Role mismatch: expected '{expected_role}', got '{enrollment_role}'")
        else:
            feedback_parts.append("User enrolled but role could not be determined")

        # Criterion 3: Enrollment was newly created - CRITICAL, no partial credit
        newly_enrolled = not was_already_enrolled
        if newly_enrolled:
            criteria_passed += 1
            feedback_parts.append("Enrollment was newly created during task")
        else:
            # User was already enrolled before task started - FAILS this criterion
            feedback_parts.append("FAIL: User was already enrolled before task started (pre-existing)")

        # Calculate score - ALL 3 criteria must pass (100% required)
        score = int((criteria_passed / total_criteria) * 100)
        passed = score == 100  # ALL 3 criteria must be met - no partial passes

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "user_enrolled": is_enrolled,
                "correct_role": role_match,
                "newly_enrolled": newly_enrolled
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
