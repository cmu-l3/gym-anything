#!/usr/bin/env python3
"""
Verifier for Create Schedule task in TimeTrex

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


def is_weekday(date_obj):
    """Check if date is a weekday (Monday=0 through Friday=4)"""
    return date_obj.weekday() < 5


def is_future_date(date_obj, export_timestamp):
    """Check if date is in the future relative to export timestamp"""
    # Date should be today or in the future
    export_date = export_timestamp.date() if isinstance(export_timestamp, datetime) else export_timestamp
    return date_obj >= export_date


def verify_create_schedule(traj, env_info, task_info):
    """
    Verify that a work schedule was created for the specified employee in TimeTrex.

    Expected employee: Jane Doe (Employee #20)
    Expected times: 9:00 AM to 5:00 PM (09:00 - 17:00)
    Expected date: Future weekday (Monday-Friday)

    Checks:
    1. A new schedule record exists in the database
    2. The schedule is for the expected employee (Jane Doe, Employee #20)
    3. The schedule has the expected start and end times (09:00 - 17:00)
    4. The schedule is for a future weekday
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_employee_fname', 'Jane')
    expected_lname = metadata.get('expected_employee_lname', 'Doe')
    expected_employee_number = metadata.get('expected_employee_number', '20')
    expected_start = metadata.get('expected_start_time', '09:00')
    expected_end = metadata.get('expected_end_time', '17:00')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_schedule_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 4  # Now 4 criteria including date validation
        feedback_parts = []

        initial_count = result.get('initial_schedule_count', 0)
        current_count = result.get('current_schedule_count', 0)
        schedule_found = result.get('schedule_found', False)
        schedule = result.get('schedule', {})
        export_timestamp_str = result.get('export_timestamp', '')

        # Parse export timestamp
        try:
            export_timestamp = datetime.fromisoformat(export_timestamp_str.replace('Z', '+00:00'))
        except (ValueError, AttributeError):
            export_timestamp = datetime.now()

        logger.info(f"Result data: initial={initial_count}, current={current_count}, found={schedule_found}")
        logger.info(f"Schedule data: {schedule}")
        logger.info(f"Export timestamp: {export_timestamp}")

        # Criterion 1: Check if a new schedule record exists
        if schedule_found and current_count > initial_count:
            criteria_passed += 1
            new_schedules = current_count - initial_count
            feedback_parts.append(f"New schedule record(s) created: {new_schedules}")
        else:
            feedback_parts.append("No new schedule records found in database")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "schedule_created": False,
                    "correct_employee": False,
                    "correct_times": False,
                    "valid_date": False
                }
            }

        # Criterion 2: Check if schedule is for the expected employee (name AND number)
        schedule_employee_fname = schedule.get('employee_fname', '').strip()
        schedule_employee_lname = schedule.get('employee_lname', '').strip()
        schedule_employee_number = str(schedule.get('employee_number', '')).strip()

        name_match = (
            schedule_employee_fname.lower() == expected_fname.lower() and
            schedule_employee_lname.lower() == expected_lname.lower()
        )
        number_match = schedule_employee_number == str(expected_employee_number)

        employee_match = name_match and number_match

        if employee_match:
            criteria_passed += 1
            feedback_parts.append(f"Correct employee: {schedule_employee_fname} {schedule_employee_lname} (#{schedule_employee_number})")
        elif name_match:
            # Name matches but number doesn't - partial information
            feedback_parts.append(
                f"Employee name matches but number differs: expected #{expected_employee_number}, "
                f"got #{schedule_employee_number}"
            )
        else:
            feedback_parts.append(
                f"Wrong employee: expected '{expected_fname} {expected_lname}' (#{expected_employee_number}), "
                f"got '{schedule_employee_fname} {schedule_employee_lname}' (#{schedule_employee_number})"
            )

        # Criterion 3: Check if schedule has the expected times
        start_time = schedule.get('start_time', '').strip()
        end_time = schedule.get('end_time', '').strip()

        # Normalize time formats (handle HH:MM:SS vs HH:MM)
        start_time_normalized = start_time[:5] if len(start_time) >= 5 else start_time
        end_time_normalized = end_time[:5] if len(end_time) >= 5 else end_time

        times_match = (
            start_time_normalized == expected_start and
            end_time_normalized == expected_end
        )

        if times_match:
            criteria_passed += 1
            feedback_parts.append(f"Correct times: {start_time_normalized} - {end_time_normalized}")
        elif start_time and end_time:
            feedback_parts.append(
                f"Times differ: expected {expected_start}-{expected_end}, "
                f"got {start_time_normalized}-{end_time_normalized}"
            )
        else:
            feedback_parts.append("Schedule missing start/end times")

        # Criterion 4: Check if schedule is for a future weekday
        date_stamp = schedule.get('date_stamp', '').strip()
        valid_date = False
        weekday_names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

        if date_stamp:
            try:
                # Parse date (handle various formats)
                if 'T' in date_stamp:
                    schedule_date = datetime.fromisoformat(date_stamp.replace('Z', '+00:00')).date()
                else:
                    schedule_date = datetime.strptime(date_stamp[:10], '%Y-%m-%d').date()

                export_date = export_timestamp.date()
                day_name = weekday_names[schedule_date.weekday()]

                # Check if it's a weekday
                is_wkday = is_weekday(schedule_date)
                # Check if it's not in the past (today or future)
                is_not_past = schedule_date >= export_date

                if is_wkday and is_not_past:
                    criteria_passed += 1
                    valid_date = True
                    feedback_parts.append(f"Valid date: {schedule_date} ({day_name}, future weekday)")
                elif is_wkday and not is_not_past:
                    feedback_parts.append(f"Date is a weekday but in the past: {schedule_date} ({day_name})")
                elif not is_wkday and is_not_past:
                    feedback_parts.append(f"Date is in the future but not a weekday: {schedule_date} ({day_name})")
                else:
                    feedback_parts.append(f"Invalid date: {schedule_date} ({day_name}) - past weekend date")

                logger.info(f"Date validation: date={schedule_date}, weekday={is_wkday}, future={is_not_past}")

            except (ValueError, TypeError) as e:
                feedback_parts.append(f"Could not parse schedule date: {date_stamp}")
                logger.warning(f"Date parsing error: {e}")
        else:
            feedback_parts.append("Schedule missing date")

        # Calculate score - all 4 criteria must pass for full success
        score = int((criteria_passed / total_criteria) * 100)
        # STRICT: Pass requires ALL 4 criteria:
        # 1. Schedule created
        # 2. Correct employee (Jane Doe #20)
        # 3. Correct times (09:00-17:00)
        # 4. Valid date (future weekday)
        passed = criteria_passed == total_criteria

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "schedule_created": current_count > initial_count,
                "correct_employee": employee_match,
                "correct_times": times_match,
                "valid_date": valid_date
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
