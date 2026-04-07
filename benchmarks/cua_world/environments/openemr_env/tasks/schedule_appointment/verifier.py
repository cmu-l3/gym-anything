#!/usr/bin/env python3
"""
Verifier for Schedule Appointment task in OpenEMR

Verifies that a new appointment was correctly scheduled for Maria Espinal.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Appointment exists for correct patient (pid=2): 30 points
- Appointment is newly created (not pre-existing): 20 points
- Date within valid range (7 days): 15 points
- Time in valid hours (9 AM - 4 PM): 10 points
- Duration at least 15 minutes: 10 points
- Comment/reason provided: 10 points
- Anti-gaming timestamp check passes: 5 points

Pass threshold: 65 points with appointment_exists AND correct_patient AND newly_created
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_schedule_appointment(traj, env_info, task_info):
    """
    Verify that an appointment was scheduled correctly for Maria Espinal.
    
    Uses copy_from_env to read the exported JSON result from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available from environment"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 2)
    expected_fname = metadata.get('patient_fname', 'Maria')
    expected_lname = metadata.get('patient_lname', 'Espinal')
    required_days = metadata.get('required_days_ahead', 7)
    required_time_start = metadata.get('required_time_start', '09:00')
    required_time_end = metadata.get('required_time_end', '16:00')
    min_duration = metadata.get('min_duration_minutes', 15)
    expected_keywords = metadata.get('expected_comment_keywords', ['routine', 'follow', 'visit', 'check'])

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
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
            "feedback": f"Failed to parse result JSON: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "appointment_exists": False,
        "correct_patient": False,
        "newly_created": False,
        "date_valid": False,
        "time_valid": False,
        "duration_valid": False,
        "comment_valid": False,
        "timestamp_check": False
    }

    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    initial_count = result.get('initial_apt_count', 0)
    current_count = result.get('current_apt_count', 0)
    max_apt_id_before = result.get('max_apt_id_before', 0)
    appt_found = result.get('new_appointment_found', False)
    appointment = result.get('appointment', {})
    validation = result.get('validation', {})
    task_start = result.get('task_start_time', 0)
    task_end = result.get('task_end_time', 0)

    logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}, found={appt_found}")
    logger.info(f"Appointment: {appointment}")

    # ================================================================
    # CRITERION 1: Appointment exists (30 points)
    # ================================================================
    if appt_found and appointment.get('eid'):
        score += 30
        subscores["appointment_exists"] = True
        subscores["correct_patient"] = True  # Already filtered by pid in export script
        feedback_parts.append(f"Appointment found for patient pid={expected_pid} ({expected_fname} {expected_lname})")
    else:
        feedback_parts.append(f"No appointment found for patient pid={expected_pid}")
        
        # Check if any appointments were created at all
        if current_count > initial_count:
            total_initial = result.get('initial_total_apt', 0)
            total_current = result.get('current_total_apt', 0)
            if total_current > total_initial:
                feedback_parts.append("Note: Appointments were created but not for the correct patient")
        
        # Early return - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # ================================================================
    # CRITERION 2: Newly created during task (20 points)
    # ================================================================
    appt_eid = appointment.get('eid', '')
    try:
        appt_eid_num = int(appt_eid) if appt_eid else 0
    except ValueError:
        appt_eid_num = 0

    if appt_eid_num > max_apt_id_before and current_count > initial_count:
        score += 20
        subscores["newly_created"] = True
        feedback_parts.append(f"Appointment newly created (eid={appt_eid} > {max_apt_id_before})")
    elif current_count > initial_count:
        score += 10  # Partial credit - count increased but ID check unclear
        subscores["newly_created"] = True
        feedback_parts.append("Appointment count increased (new appointment likely created)")
    else:
        feedback_parts.append("WARNING: Appointment may have existed before task (anti-gaming check)")

    # ================================================================
    # CRITERION 3: Date within valid range (15 points)
    # ================================================================
    appt_date_str = appointment.get('date', '')
    date_valid_from_export = validation.get('date_valid', False)
    
    if date_valid_from_export:
        score += 15
        subscores["date_valid"] = True
        feedback_parts.append(f"Date valid: {appt_date_str}")
    elif appt_date_str:
        # Double-check the date ourselves
        try:
            appt_date = datetime.strptime(appt_date_str, '%Y-%m-%d').date()
            today = datetime.now().date()
            max_date = today + timedelta(days=required_days)
            
            if today <= appt_date <= max_date:
                score += 15
                subscores["date_valid"] = True
                feedback_parts.append(f"Date valid: {appt_date_str} (within {required_days} days)")
            else:
                score += 5  # Partial credit for having a date
                feedback_parts.append(f"Date out of range: {appt_date_str} (should be {today} to {max_date})")
        except ValueError:
            feedback_parts.append(f"Invalid date format: {appt_date_str}")
    else:
        feedback_parts.append("No appointment date set")

    # ================================================================
    # CRITERION 4: Time in valid hours (10 points)
    # ================================================================
    appt_start_time = appointment.get('start_time', '')
    time_valid_from_export = validation.get('time_valid', False)
    
    if time_valid_from_export:
        score += 10
        subscores["time_valid"] = True
        feedback_parts.append(f"Time valid: {appt_start_time}")
    elif appt_start_time:
        # Double-check the time ourselves
        try:
            hour_str = appt_start_time.split(':')[0].lstrip('0') or '0'
            hour = int(hour_str)
            
            # Parse required times
            start_hour = int(required_time_start.split(':')[0])
            end_hour = int(required_time_end.split(':')[0])
            
            if start_hour <= hour < end_hour:
                score += 10
                subscores["time_valid"] = True
                feedback_parts.append(f"Time valid: {appt_start_time} (between {required_time_start} and {required_time_end})")
            else:
                score += 3  # Partial credit for having a time
                feedback_parts.append(f"Time out of range: {appt_start_time} (should be {required_time_start}-{required_time_end})")
        except (ValueError, IndexError):
            feedback_parts.append(f"Invalid time format: {appt_start_time}")
    else:
        feedback_parts.append("No appointment time set")

    # ================================================================
    # CRITERION 5: Duration at least 15 minutes (10 points)
    # ================================================================
    appt_duration = appointment.get('duration', '0')
    try:
        duration_num = int(appt_duration) if appt_duration else 0
    except ValueError:
        duration_num = 0
    
    if duration_num >= min_duration:
        score += 10
        subscores["duration_valid"] = True
        feedback_parts.append(f"Duration valid: {duration_num} minutes")
    elif duration_num > 0:
        score += 5  # Partial credit
        feedback_parts.append(f"Duration too short: {duration_num} minutes (should be >= {min_duration})")
    else:
        feedback_parts.append("No duration set")

    # ================================================================
    # CRITERION 6: Comment/reason provided (10 points)
    # ================================================================
    appt_comment = appointment.get('comment', '').lower()
    appt_title = appointment.get('title', '').lower()
    combined_text = f"{appt_comment} {appt_title}"
    
    has_keyword = any(kw in combined_text for kw in expected_keywords)
    
    if has_keyword:
        score += 10
        subscores["comment_valid"] = True
        feedback_parts.append("Comment contains relevant keywords")
    elif appt_comment or appt_title:
        score += 5  # Partial credit for having any comment
        subscores["comment_valid"] = True
        feedback_parts.append(f"Comment provided: '{appt_comment or appt_title}' (no specific keywords)")
    else:
        feedback_parts.append("No comment/reason provided")

    # ================================================================
    # CRITERION 7: Timestamp anti-gaming check (5 points)
    # ================================================================
    if task_start > 0 and task_end > 0:
        task_duration = task_end - task_start
        if task_duration > 10 and task_duration < 600:  # Between 10 sec and 10 min
            score += 5
            subscores["timestamp_check"] = True
            feedback_parts.append(f"Task completed in {task_duration}s (reasonable time)")
        elif task_duration >= 600:
            score += 3  # Partial credit - task took a long time but completed
            feedback_parts.append(f"Task took {task_duration}s (very long)")
        else:
            feedback_parts.append(f"Task completed too quickly ({task_duration}s) - suspicious")
    else:
        feedback_parts.append("Timestamp data unavailable")

    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    # Must have: appointment exists + correct patient + newly created
    key_criteria_met = (
        subscores["appointment_exists"] and 
        subscores["correct_patient"] and 
        subscores["newly_created"]
    )
    
    passed = score >= 65 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "expected_patient": f"{expected_fname} {expected_lname} (pid={expected_pid})",
            "appointment_eid": appointment.get('eid', 'N/A'),
            "appointment_date": appointment.get('date', 'N/A'),
            "appointment_time": appointment.get('start_time', 'N/A'),
            "appointment_duration": appointment.get('duration', 'N/A'),
            "score_breakdown": {
                "appointment_exists": 30 if subscores["appointment_exists"] else 0,
                "newly_created": 20 if subscores["newly_created"] else 0,
                "date_valid": 15 if subscores["date_valid"] else 0,
                "time_valid": 10 if subscores["time_valid"] else 0,
                "duration_valid": 10 if subscores["duration_valid"] else 0,
                "comment_valid": 10 if subscores["comment_valid"] else 0,
                "timestamp_check": 5 if subscores["timestamp_check"] else 0
            }
        }
    }


# For local testing
if __name__ == "__main__":
    import subprocess
    
    def local_copy(src, dst):
        """Simulate copy_from_env for local testing"""
        import shutil
        shutil.copy(src, dst)
    
    # Mock test
    test_result = {
        "task_start_time": 1700000000,
        "task_end_time": 1700000120,
        "patient_pid": 2,
        "initial_apt_count": 0,
        "current_apt_count": 1,
        "max_apt_id_before": 10,
        "new_appointment_found": True,
        "appointment": {
            "eid": "11",
            "pid": "2",
            "date": datetime.now().strftime("%Y-%m-%d"),
            "start_time": "10:00:00",
            "end_time": "10:15:00",
            "duration": "15",
            "comment": "Routine follow-up visit",
            "title": "Office Visit",
            "category_id": "5"
        },
        "validation": {
            "date_valid": True,
            "time_valid": True,
            "duration_valid": True,
            "comment_valid": True
        }
    }
    
    # Write test result
    with open("/tmp/test_result.json", "w") as f:
        json.dump(test_result, f)
    
    def test_copy(src, dst):
        import shutil
        shutil.copy("/tmp/test_result.json", dst)
    
    env_info = {"copy_from_env": test_copy}
    task_info = {"metadata": {}}
    
    result = verify_schedule_appointment({}, env_info, task_info)
    print(f"Score: {result['score']}/100")
    print(f"Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")
    print(f"Subscores: {result.get('subscores', {})}")