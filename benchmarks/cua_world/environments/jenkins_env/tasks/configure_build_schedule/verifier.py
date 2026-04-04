#!/usr/bin/env python3
"""
Verifier for Configure Build Schedule task in Jenkins

Checks if a periodic build trigger was added with the correct cron schedule.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_build_schedule(traj, env_info, task_info):
    """
    Verify that a periodic build trigger was configured.

    Checks:
    1. Job exists in Jenkins
    2. Job has a TimerTrigger (periodic build trigger)
    3. Schedule contains correct time fields (midnight daily)
    4. Schedule uses Jenkins hash syntax (H) for load distribution
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_job_name = metadata.get('expected_job_name', 'Nightly-Backup')
    expected_schedule = metadata.get('expected_schedule', 'H 0 * * *')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_build_schedule_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []

        job_found = result.get('job_found', False)
        has_timer = result.get('has_timer_trigger', False)
        schedule = result.get('schedule', '').strip()

        logger.info(f"Result data: job_found={job_found}, has_timer={has_timer}, schedule='{schedule}'")

        # Criterion 1: Job exists
        if job_found:
            criteria_passed += 1
            feedback_parts.append(f"Job '{expected_job_name}' exists in Jenkins")
        else:
            feedback_parts.append(f"Job '{expected_job_name}' NOT found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "job_exists": False,
                    "has_trigger": False,
                    "correct_time": False,
                    "uses_hash": False
                }
            }

        # Criterion 2: Has TimerTrigger
        if has_timer:
            criteria_passed += 1
            feedback_parts.append("Periodic build trigger is configured")
        else:
            feedback_parts.append("No periodic build trigger found")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "job_exists": True,
                    "has_trigger": False,
                    "correct_time": False,
                    "uses_hash": False
                }
            }

        # Criterion 3: Schedule targets midnight daily
        # Valid midnight daily patterns: "H 0 * * *", "0 0 * * *", "H(0-5) 0 * * *", etc.
        schedule_parts = schedule.split()
        correct_time = False
        if len(schedule_parts) == 5:
            hour_field = schedule_parts[1]
            day_of_month = schedule_parts[2]
            month = schedule_parts[3]
            day_of_week = schedule_parts[4]

            # Hour should be 0 (midnight), other fields should be * (daily)
            if hour_field == '0' and day_of_month == '*' and month == '*' and day_of_week == '*':
                correct_time = True
                criteria_passed += 1
                feedback_parts.append(f"Schedule targets midnight daily: '{schedule}'")
            elif hour_field in ('0', '00') and '*' in day_of_month:
                # Close enough - midnight but maybe not exactly daily
                criteria_passed += 0.75
                correct_time = True
                feedback_parts.append(f"Schedule approximately correct: '{schedule}'")
            else:
                feedback_parts.append(f"Schedule time incorrect: expected midnight daily, got '{schedule}'")
        else:
            feedback_parts.append(f"Schedule format invalid: expected 5 cron fields, got '{schedule}'")

        # Criterion 4: Uses H (hash) for load balancing in minute field
        uses_hash = False
        if len(schedule_parts) == 5:
            minute_field = schedule_parts[0]
            if 'H' in minute_field or 'h' in minute_field:
                uses_hash = True
                criteria_passed += 1
                feedback_parts.append("Uses Jenkins hash (H) for load distribution")
            elif minute_field.isdigit():
                # Fixed minute - acceptable but not ideal
                criteria_passed += 0.5
                feedback_parts.append(f"Uses fixed minute ({minute_field}) instead of H for load distribution")
            else:
                feedback_parts.append(f"Minute field unexpected: '{minute_field}'")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "job_exists": job_found,
                "has_trigger": has_timer,
                "correct_time": correct_time,
                "uses_hash": uses_hash
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
