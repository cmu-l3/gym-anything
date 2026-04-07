#!/usr/bin/env python3
"""
Verifier for Schedule Hypertension Follow-up task in OpenEMR

Robust verification with adversarial case handling:
1. Must be for correct patient (pid=3, Jayson Fadel)
2. Must be a NEW appointment (created during task, not pre-existing)
3. Must be within 14 days from today
4. Must be in morning hours (9 AM - 12 PM)
5. Must have appropriate reason mentioning hypertension/follow-up
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_schedule_followup(traj, env_info, task_info):
    """
    Verify that a follow-up appointment was correctly scheduled.

    Scoring (100 points total):
    - Appointment exists for correct patient: 30 points
    - Appointment is newly created: 20 points
    - Date within valid range (14 days): 20 points
    - Time in morning (9-12): 15 points
    - Reason mentions hypertension/follow-up: 15 points

    Passing threshold: 70 points (must have correct patient + new + valid date minimum)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    required_days = metadata.get('required_days_ahead', 14)
    required_time_start = metadata.get('required_time_start', '09:00')
    required_time_end = metadata.get('required_time_end', '12:00')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/schedule_followup_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "newly_created": False,
            "date_valid": False,
            "time_valid": False,
            "reason_valid": False
        }

        # Extract data
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_appt_count', 0)
        current_count = result.get('current_appt_count', 0)
        appt_found = result.get('new_appointment_found', False)
        appointment = result.get('appointment', {})
        validation = result.get('validation', {})

        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}, found={appt_found}")
        logger.info(f"Appointment: {appointment}")

        # CRITERION 1: Correct patient (30 points)
        # This is critical - appointment must be for Jayson Fadel (pid=3)
        if patient_pid == expected_pid:
            if appt_found:
                score += 30
                subscores["correct_patient"] = True
                feedback_parts.append(f"Appointment found for correct patient (pid={expected_pid})")
            else:
                feedback_parts.append(f"No appointment found for patient pid={expected_pid}")
        else:
            feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            # Adversarial case: wrong patient - fail immediately
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Appointment scheduled for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        if not appt_found:
            feedback_parts.append("No new appointment was created")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Newly created appointment (20 points)
        # Must have more appointments now than before task started
        if current_count > initial_count:
            score += 20
            subscores["newly_created"] = True
            feedback_parts.append(f"New appointment created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"No new appointment detected (count unchanged: {current_count})")
            # Adversarial case: claiming existing appointment
            # Don't return early, but this is a significant failure

        # CRITERION 3: Date within valid range (20 points)
        appt_date_str = appointment.get('date', '')
        if appt_date_str:
            try:
                appt_date = datetime.strptime(appt_date_str, '%Y-%m-%d').date()
                today = datetime.now().date()
                max_date = today + timedelta(days=required_days)

                if today <= appt_date <= max_date:
                    score += 20
                    subscores["date_valid"] = True
                    feedback_parts.append(f"Date {appt_date_str} is within {required_days} days")
                else:
                    feedback_parts.append(f"Date {appt_date_str} is outside valid range ({today} to {max_date})")
            except ValueError as e:
                feedback_parts.append(f"Invalid date format: {appt_date_str}")
        else:
            feedback_parts.append("No appointment date found")

        # CRITERION 4: Time in morning hours (15 points)
        appt_start_time = appointment.get('start_time', '')
        if appt_start_time:
            try:
                # Parse time (format may be HH:MM:SS or HH:MM)
                time_parts = appt_start_time.split(':')
                hour = int(time_parts[0])

                # Morning is 9:00 (09:00) to before 12:00
                if 9 <= hour < 12:
                    score += 15
                    subscores["time_valid"] = True
                    feedback_parts.append(f"Time {appt_start_time} is in morning hours (9-12)")
                else:
                    feedback_parts.append(f"Time {appt_start_time} is not in morning hours (hour={hour})")
            except (ValueError, IndexError) as e:
                feedback_parts.append(f"Could not parse time: {appt_start_time}")
        else:
            feedback_parts.append("No appointment time found")

        # CRITERION 5: Reason mentions hypertension/follow-up (15 points)
        appt_reason = appointment.get('reason', '') or ''
        appt_title = appointment.get('title', '') or ''
        combined_reason = f"{appt_reason} {appt_title}".lower()

        # Look for relevant keywords
        hypertension_keywords = ['hypertension', 'htn', 'blood pressure', 'bp']
        followup_keywords = ['follow-up', 'followup', 'follow up', 'f/u', 'fu']

        has_hypertension = any(kw in combined_reason for kw in hypertension_keywords)
        has_followup = any(kw in combined_reason for kw in followup_keywords)

        if has_hypertension or has_followup:
            score += 15
            subscores["reason_valid"] = True
            keywords_found = []
            if has_hypertension:
                keywords_found.append("hypertension-related")
            if has_followup:
                keywords_found.append("follow-up")
            feedback_parts.append(f"Reason contains appropriate keywords: {', '.join(keywords_found)}")
        else:
            feedback_parts.append(f"Reason missing hypertension/follow-up keywords: '{combined_reason[:100]}'")

        # Determine pass/fail
        # Must have: correct patient (30) + newly created (20) + valid date (20) = 70 minimum
        passed = score >= 70 and subscores["correct_patient"] and subscores["newly_created"]

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "appointment_date": appt_date_str,
                "appointment_time": appt_start_time,
                "appointment_reason": combined_reason[:200] if combined_reason else "",
                "patient_pid": patient_pid,
                "appointments_before": initial_count,
                "appointments_after": current_count
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
