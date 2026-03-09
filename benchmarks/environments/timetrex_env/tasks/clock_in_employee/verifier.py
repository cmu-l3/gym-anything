#!/usr/bin/env python3
"""
Verifier for Clock In Employee task in TimeTrex

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


def verify_clock_in(traj, env_info, task_info):
    """
    Verify that a clock-in punch was recorded for the specified employee in TimeTrex.

    Expected employee: John Doe (Employee #10)

    Checks:
    1. A new punch record exists in the database
    2. The punch was for the expected employee (John Doe, #10)
    3. The punch type is 'in' (status_id = 10)
    4. The punch was created during this session (timestamp validation)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_employee_fname', 'John')
    expected_lname = metadata.get('expected_employee_lname', 'Doe')
    expected_emp_number = metadata.get('expected_employee_number', '10')
    expected_punch_status = metadata.get('punch_status_id', '10')  # 10 = In

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/clock_in_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 4  # Now 4 criteria including timestamp validation
        feedback_parts = []

        initial_count = result.get('initial_punch_count', 0)
        current_count = result.get('current_punch_count', 0)
        punch_found = result.get('punch_found', False)
        punch = result.get('punch', {})
        task_start_str = result.get('task_start_timestamp', '')
        export_timestamp_str = result.get('export_timestamp', '')

        # Parse timestamps
        try:
            export_timestamp = datetime.fromisoformat(export_timestamp_str.replace('Z', '+00:00'))
        except (ValueError, AttributeError):
            export_timestamp = datetime.now()

        logger.info(f"Result data: initial={initial_count}, current={current_count}, found={punch_found}")
        logger.info(f"Punch data: {punch}")
        logger.info(f"Task start: {task_start_str}, Export: {export_timestamp}")

        # Criterion 1: Check if a new punch record exists
        if punch_found and current_count > initial_count:
            criteria_passed += 1
            new_punches = current_count - initial_count
            feedback_parts.append(f"New punch record(s) created: {new_punches}")
        else:
            feedback_parts.append("No new punch records found in database")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "punch_created": False,
                    "correct_employee": False,
                    "correct_punch_type": False,
                    "valid_timestamp": False
                }
            }

        # Criterion 2: Check if punch is for the expected employee (name AND number)
        punch_employee_fname = punch.get('employee_fname', '').strip()
        punch_employee_lname = punch.get('employee_lname', '').strip()
        punch_employee_number = str(punch.get('employee_number', '')).strip()

        name_match = (
            punch_employee_fname.lower() == expected_fname.lower() and
            punch_employee_lname.lower() == expected_lname.lower()
        )
        number_match = punch_employee_number == str(expected_emp_number)
        employee_match = name_match and number_match

        if employee_match:
            criteria_passed += 1
            feedback_parts.append(f"Correct employee: {punch_employee_fname} {punch_employee_lname} (#{punch_employee_number})")
        elif name_match:
            feedback_parts.append(
                f"Employee name matches but number differs: expected #{expected_emp_number}, "
                f"got #{punch_employee_number}"
            )
        else:
            feedback_parts.append(
                f"Wrong employee: expected '{expected_fname} {expected_lname}' (#{expected_emp_number}), "
                f"got '{punch_employee_fname} {punch_employee_lname}' (#{punch_employee_number})"
            )

        # Criterion 3: Check if punch type is 'In' (status_id = 10)
        punch_status = str(punch.get('status_id', '')).strip()

        if punch_status == expected_punch_status:
            criteria_passed += 1
            feedback_parts.append(f"Correct punch type: In (status_id={punch_status})")
        else:
            feedback_parts.append(
                f"Wrong punch type: expected status_id={expected_punch_status} (In), "
                f"got status_id={punch_status}"
            )

        # Criterion 4: Check if punch was created during this session (timestamp validation)
        punch_timestamp_str = punch.get('timestamp', '')
        valid_timestamp = False

        if punch_timestamp_str:
            try:
                # Parse punch timestamp (may be epoch or ISO format)
                if punch_timestamp_str.isdigit() or (punch_timestamp_str.startswith('-') and punch_timestamp_str[1:].isdigit()):
                    # Epoch timestamp
                    punch_time = datetime.fromtimestamp(int(punch_timestamp_str))
                else:
                    # ISO format
                    punch_time = datetime.fromisoformat(punch_timestamp_str.replace('Z', '+00:00'))

                # Parse task start timestamp
                if task_start_str:
                    if task_start_str.isdigit():
                        task_start = datetime.fromtimestamp(int(task_start_str))
                    else:
                        try:
                            task_start = datetime.fromisoformat(task_start_str.replace('Z', '+00:00'))
                        except ValueError:
                            task_start = export_timestamp - timedelta(minutes=30)
                else:
                    # If no task start, assume task started 30 minutes before export
                    task_start = export_timestamp - timedelta(minutes=30)

                # Punch should be between task start and export (with some buffer)
                buffer = timedelta(minutes=5)
                if task_start - buffer <= punch_time <= export_timestamp + buffer:
                    criteria_passed += 1
                    valid_timestamp = True
                    feedback_parts.append(f"Valid timestamp: punch at {punch_time.strftime('%Y-%m-%d %H:%M:%S')}")
                else:
                    feedback_parts.append(
                        f"Punch timestamp outside task window: punch={punch_time}, "
                        f"task_start={task_start}, export={export_timestamp}"
                    )

                logger.info(f"Timestamp validation: punch={punch_time}, task_start={task_start}, export={export_timestamp}")

            except (ValueError, TypeError, OSError) as e:
                feedback_parts.append(f"Could not parse punch timestamp: {punch_timestamp_str}")
                logger.warning(f"Timestamp parsing error: {e}")
        else:
            feedback_parts.append("Punch missing timestamp")

        # Calculate score - stricter requirements
        score = int((criteria_passed / total_criteria) * 100)
        # STRICT: Pass requires at least 3 of 4 criteria, BUT employee and punch type are mandatory:
        # 1. Punch created (mandatory)
        # 2. Correct employee - John Doe #10 (mandatory)
        # 3. Correct punch type - In/status_id=10 (mandatory)
        # 4. Valid timestamp (can be missing if 1-3 pass)
        passed = (criteria_passed >= 3 and employee_match and
                  punch_status == expected_punch_status and
                  current_count > initial_count)

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "punch_created": current_count > initial_count,
                "correct_employee": employee_match,
                "correct_punch_type": punch_status == expected_punch_status,
                "valid_timestamp": valid_timestamp
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
