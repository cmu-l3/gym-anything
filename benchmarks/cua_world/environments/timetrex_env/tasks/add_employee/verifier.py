#!/usr/bin/env python3
"""
Verifier for Add Employee task in TimeTrex

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_employee(traj, env_info, task_info):
    """
    Verify that the expected employee was added to TimeTrex.

    The expected employee details are read from task_info metadata.
    Defaults: Sarah Johnson, Employee Number: EMP-2024-001

    STRICT verification - no partial credit:
    1. Employee with EXACT expected fname and lname exists in database
    2. Employee number EXACTLY matches expected value
    3. Employee was created during this session (count increased)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata (with defaults)
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_fname', 'Sarah')
    expected_lname = metadata.get('expected_lname', 'Johnson')
    expected_employee_number = metadata.get('expected_employee_number', 'EMP-2024-001')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_employee_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 3
        feedback_parts = []

        initial_count = result.get('initial_employee_count', 0)
        current_count = result.get('current_employee_count', 0)
        employee_found = result.get('employee_found', False)
        employee = result.get('employee', {})

        logger.info(f"Result data: initial={initial_count}, current={current_count}, found={employee_found}")
        logger.info(f"Employee data: {employee}")

        # Initialize variables for subscores
        name_match = False
        number_match = False
        newly_added = current_count > initial_count

        # Criterion 1: Check if employee exists with expected name (EXACT MATCH)
        if employee_found:
            fname = employee.get('fname', '').strip()
            lname = employee.get('lname', '').strip()

            if fname.lower() == expected_fname.lower() and lname.lower() == expected_lname.lower():
                criteria_passed += 1
                name_match = True
                feedback_parts.append(f"Employee '{expected_fname} {expected_lname}' found in database")
            else:
                feedback_parts.append(f"Employee name mismatch: expected '{expected_fname} {expected_lname}', got '{fname} {lname}'")
        else:
            feedback_parts.append(f"Employee '{expected_fname} {expected_lname}' NOT found in database")

            # Check if any new employees were added at all
            if newly_added:
                new_employees = current_count - initial_count
                feedback_parts.append(f"Note: {new_employees} new employee(s) added, but not with expected name")
            else:
                feedback_parts.append("No new employees were added to the database")

            # Early return since no employee found
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "employee_exists": False,
                    "employee_number_correct": False,
                    "newly_added": newly_added
                }
            }

        # Criterion 2: Check employee number (STRICT - no partial credit)
        emp_number = employee.get('employee_number', '').strip()
        if expected_employee_number:
            # Normalize comparison (case-insensitive, strip whitespace)
            emp_number_normalized = emp_number.lower().strip()
            expected_normalized = expected_employee_number.lower().strip()

            if emp_number_normalized == expected_normalized:
                criteria_passed += 1
                number_match = True
                feedback_parts.append(f"Employee number correct: {emp_number}")
            else:
                # NO PARTIAL CREDIT - either correct or wrong
                feedback_parts.append(f"Employee number WRONG: expected '{expected_employee_number}', got '{emp_number or '(not set)'}'")
        else:
            # No expected employee number specified - skip this criterion
            criteria_passed += 1
            number_match = True
            feedback_parts.append("Employee number validation skipped (not specified in requirements)")

        # Criterion 3: Check if employee was newly added (count increased)
        if newly_added:
            criteria_passed += 1
            feedback_parts.append(f"Employee count increased: {initial_count} -> {current_count}")
        else:
            feedback_parts.append(f"Employee count did not increase (was {initial_count}, now {current_count})")
            feedback_parts.append("WARNING: Employee may have existed before task started")

        # Calculate score - ALL criteria must pass for success
        score = int((criteria_passed / total_criteria) * 100)
        # STRICT: Must have all 3 criteria met to pass
        passed = criteria_passed == total_criteria

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "employee_exists": name_match,
                "employee_number_correct": number_match,
                "newly_added": newly_added
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
