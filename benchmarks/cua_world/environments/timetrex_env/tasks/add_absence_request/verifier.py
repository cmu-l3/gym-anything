#!/usr/bin/env python3
"""
Verifier for Add Absence Request task in TimeTrex

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_absence_request(traj, env_info, task_info):
    """
    Verify that an absence request was created for the specified employee in TimeTrex.

    Expected employee: Heather Grant (Employee #24)
    Expected absence type: Vacation
    Expected duration: Single day (1 day)
    Expected date: Within next 7 days

    Checks:
    1. A new request record exists in the database
    2. The request is for the expected employee (Heather Grant, #24)
    3. The request is for vacation type
    4. The request is for a single day
    5. The request date is within the next 7 days
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_employee_fname', 'Heather')
    expected_lname = metadata.get('expected_employee_lname', 'Grant')
    expected_employee_number = metadata.get('expected_employee_number', '24')
    expected_absence_type = metadata.get('absence_type', 'vacation')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/absence_request_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 5  # Now 5 criteria including date and duration
        feedback_parts = []

        initial_count = result.get('initial_request_count', 0)
        current_count = result.get('current_request_count', 0)
        request_found = result.get('request_found', False)
        request = result.get('request', {})
        export_timestamp_str = result.get('export_timestamp', '')

        # Parse export timestamp
        try:
            export_timestamp = datetime.fromisoformat(export_timestamp_str.replace('Z', '+00:00'))
        except (ValueError, AttributeError):
            export_timestamp = datetime.now()

        logger.info(f"Result data: initial={initial_count}, current={current_count}, found={request_found}")
        logger.info(f"Request data: {request}")
        logger.info(f"Export timestamp: {export_timestamp}")

        # Criterion 1: Check if a new request record exists
        if request_found and current_count > initial_count:
            criteria_passed += 1
            new_requests = current_count - initial_count
            feedback_parts.append(f"New request record(s) created: {new_requests}")
        else:
            feedback_parts.append("No new request records found in database")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "request_created": False,
                    "correct_employee": False,
                    "correct_type": False,
                    "single_day": False,
                    "within_7_days": False
                }
            }

        # Criterion 2: Check if request is for the expected employee (name AND number)
        request_employee_fname = request.get('employee_fname', '').strip()
        request_employee_lname = request.get('employee_lname', '').strip()
        request_employee_number = str(request.get('employee_number', '')).strip()

        name_match = (
            request_employee_fname.lower() == expected_fname.lower() and
            request_employee_lname.lower() == expected_lname.lower()
        )
        number_match = request_employee_number == str(expected_employee_number)
        employee_match = name_match and number_match

        if employee_match:
            criteria_passed += 1
            feedback_parts.append(f"Correct employee: {request_employee_fname} {request_employee_lname} (#{request_employee_number})")
        elif name_match:
            feedback_parts.append(
                f"Employee name matches but number differs: expected #{expected_employee_number}, "
                f"got #{request_employee_number}"
            )
        else:
            feedback_parts.append(
                f"Wrong employee: expected '{expected_fname} {expected_lname}' (#{expected_employee_number}), "
                f"got '{request_employee_fname} {request_employee_lname}' (#{request_employee_number})"
            )

        # Criterion 3: Check if request is for vacation type
        absence_type_name = request.get('absence_type_name', '').strip().lower()
        type_match = 'vacation' in absence_type_name or expected_absence_type.lower() in absence_type_name

        if type_match:
            criteria_passed += 1
            feedback_parts.append(f"Correct absence type: {absence_type_name}")
        elif absence_type_name and absence_type_name != 'unknown':
            feedback_parts.append(f"Wrong absence type: expected '{expected_absence_type}', got '{absence_type_name}'")
        else:
            feedback_parts.append(f"Absence type not identified (expected: {expected_absence_type})")

        # Criterion 4: Check if request is for a single day
        duration_days = request.get('duration_days', 1)
        try:
            duration_days = int(duration_days)
        except (ValueError, TypeError):
            duration_days = 1

        single_day = duration_days == 1

        if single_day:
            criteria_passed += 1
            feedback_parts.append(f"Correct duration: single day ({duration_days} day)")
        else:
            feedback_parts.append(f"Wrong duration: expected 1 day, got {duration_days} days")

        # Criterion 5: Check if request date is within the next 7 days
        start_date_str = request.get('start_date', '') or request.get('date_stamp', '')
        within_7_days = False

        if start_date_str:
            try:
                # Parse date (handle various formats)
                if 'T' in start_date_str:
                    request_date = datetime.fromisoformat(start_date_str.replace('Z', '+00:00')).date()
                else:
                    request_date = datetime.strptime(start_date_str[:10], '%Y-%m-%d').date()

                export_date = export_timestamp.date()
                max_date = export_date + timedelta(days=7)

                # Date must be today or in the future, but within 7 days
                if export_date <= request_date <= max_date:
                    criteria_passed += 1
                    within_7_days = True
                    days_from_now = (request_date - export_date).days
                    feedback_parts.append(f"Valid date: {request_date} ({days_from_now} days from now, within 7 days)")
                elif request_date < export_date:
                    feedback_parts.append(f"Date is in the past: {request_date}")
                else:
                    days_from_now = (request_date - export_date).days
                    feedback_parts.append(f"Date too far in future: {request_date} ({days_from_now} days from now, exceeds 7 day limit)")

                logger.info(f"Date validation: request_date={request_date}, export_date={export_date}, max_date={max_date}")

            except (ValueError, TypeError) as e:
                feedback_parts.append(f"Could not parse request date: {start_date_str}")
                logger.warning(f"Date parsing error: {e}")
        else:
            feedback_parts.append("Request missing date")

        # Calculate score - stricter passing requirements
        score = int((criteria_passed / total_criteria) * 100)
        # STRICT: Pass requires ALL 5 criteria:
        # 1. Request created
        # 2. Correct employee (Heather Grant #24)
        # 3. Correct type (Vacation)
        # 4. Single day duration
        # 5. Date within 7 days
        passed = criteria_passed == total_criteria

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "request_created": current_count > initial_count,
                "correct_employee": employee_match,
                "correct_type": type_match,
                "single_day": single_day,
                "within_7_days": within_7_days
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
